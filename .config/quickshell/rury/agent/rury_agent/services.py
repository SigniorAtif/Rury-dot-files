"""Everything sessions share: settings, models, the llama-server, storage, the desk, MCP, skills, event fan-out."""
from __future__ import annotations

import asyncio
import json
import os
import time
from contextlib import asynccontextmanager

import httpx

from . import paths, settings as settings_mod, skills as skills_mod
from .desk import Desk
from .loop import Agent
from .mcp_hub import Hub, McpTool, _field
from .models import LlamaServer, Registry, ModelSpec, resolve_key
from .sessions import Store
from .tools import Ctx, Result, Tool, desk as desk_tools, files, meta, shell, web

SESSION_KEYS = {"HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "DISPLAY", "XDG_CURRENT_DESKTOP",
                "XDG_SESSION_TYPE", "DBUS_SESSION_BUS_ADDRESS"}


class Services:
    def __init__(self, store: Store | None = None):
        paths.ensure_dirs()
        self.settings = settings_mod.load()
        self.store = store or Store()
        self.registry = Registry()
        self.llama = LlamaServer(idle_stop=self.settings.llama_idle_stop)
        self.desk = Desk(self.settings.desk_width, self.settings.desk_height)
        self.mcp = Hub(self.desk, self.settings.desk_mcp_servers)
        self.http = httpx.AsyncClient()
        self.core_tools: list[Tool] = files.tools() + shell.tools() + web.tools() + desk_tools.tools() + meta.tools()
        self.agents: dict[str, Agent] = {}
        self.listeners: set[asyncio.Queue] = set()
        self._locks: dict[str, asyncio.Lock] = {}
        self._skills: list | None = None
        self._skills_t = 0.0
        self._keys: dict[str, str] = {}
        self.ui_open = False          # the sidebar or HUD is showing (approvals also go to notifications when not)
        self.llama.on_state = lambda st, mid: self._fire({"ev": "model_state", "state": st, "model": mid})
        self.desk.on_change = lambda d: self._fire({"ev": "desk", **d})

    async def start(self) -> None:
        await self.registry.refresh()

    async def refresh_session_env(self) -> None:
        """Pick up the current Hyprland session's addresses from the systemd user manager. The daemon can outlive
        a Hyprland restart (new instance signature) or start before Hyprland exported them."""
        if time.time() - getattr(self, "_env_t", 0) < 10:
            return
        self._env_t = time.time()
        try:
            p = await asyncio.create_subprocess_exec("systemctl", "--user", "show-environment",
                                                     stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
            out, _ = await p.communicate()
        except OSError:
            return
        for line in out.decode(errors="replace").splitlines():
            k, _, v = line.partition("=")
            if k in SESSION_KEYS and v:
                os.environ[k] = v

    async def close(self) -> None:
        for a in list(self.agents.values()):
            await a.stop()
        await self.mcp.close()
        await self.llama.stop()
        await self.http.aclose()

    # ---- events ----
    def _fire(self, ev: dict) -> None:
        for q in list(self.listeners):
            q.put_nowait(ev)

    async def broadcast(self, ev: dict) -> None:
        self._fire(ev)

    def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue()
        self.listeners.add(q)
        return q

    def unsubscribe(self, q: asyncio.Queue) -> None:
        self.listeners.discard(q)

    # ---- sessions ----
    def agent(self, sid: str) -> Agent:
        if sid not in self.agents:
            s = self.store.get(sid)
            if not s:
                raise KeyError(f"no session {sid}")
            self.agents[sid] = Agent(self, s)
        return self.agents[sid]

    def new_session(self, mode: str | None = None, model: str | None = None, cwd: str | None = None,
                    kind: str = "chat", title: str = "") -> Agent:
        s = self.store.create(mode=mode or self.settings.default_mode, model=model or self.registry.default,
                              cwd=cwd or str(paths.HOME), kind=kind, title=title)
        return self.agent(s["id"])

    def current_model_id(self, sid: str) -> str:
        s = self.store.get(sid)
        return (s or {}).get("model") or self.registry.default

    # ---- models ----
    @asynccontextmanager
    async def llm_lock(self, base_url: str):
        lock = self._locks.setdefault(base_url, asyncio.Lock())
        async with lock:
            yield

    async def endpoint(self, spec: ModelSpec, agent: Agent | None = None) -> str:
        if spec.kind == "llama.cpp":
            if self.llama.state != "on" or not self.llama.spec or self.llama.spec.gguf != spec.gguf:
                if agent:
                    await agent.set_status("loading", f"loading {spec.name}")
            # one llama-server: wait for whoever is using it before swapping the model under them
            async with self.llm_lock(self.llama.base_url):
                return await self.llama.ensure(spec)
        if not spec.base_url:
            raise RuntimeError(f"model {spec.id} has no base_url")
        return spec.base_url

    def touch_model(self, spec: ModelSpec) -> None:
        if spec.kind == "llama.cpp":
            self.llama.touch()

    def key_for(self, spec: ModelSpec) -> str:
        if spec.id not in self._keys:
            self._keys[spec.id] = resolve_key(spec)
        return self._keys[spec.id]

    # ---- skills / mcp ----
    def skills(self):
        if self._skills is None or time.time() - self._skills_t > 30:
            self._skills = skills_mod.load()
            self._skills_t = time.time()
        return self._skills

    def skills_index(self) -> str:
        return skills_mod.index(self.skills())

    def mcp_tool(self, mt: McpTool) -> Tool:
        hub = self.mcp

        async def run(args: dict, ctx: Ctx) -> Result:
            res = await hub.call(mt.full, args)
            texts, images = [], []
            for c in getattr(res, "content", []) or []:
                ct = getattr(c, "type", "")
                if ct == "text":
                    texts.append(c.text)
                elif ct == "image":
                    images.append(f"data:{_field(c, 'mime_type', 'mimeType')};base64,{c.data}")
                elif ct == "resource":
                    r = getattr(c, "resource", None)
                    texts.append(getattr(r, "text", "") or f"[resource {getattr(r, 'uri', '')}]")
            if images and not ctx.vision:
                images = []
                texts.append("[an image was returned; this model can't see it]")
            text = "\n".join(texts) or "(no output)"
            if mt.server in self.settings.desk_mcp_servers:
                self.desk.note(f"{mt.name}")
            return Result(text, images=images, ok=not _field(res, "is_error", "isError"))

        params = mt.schema if mt.schema.get("type") == "object" else {"type": "object", "properties": {}}
        return Tool(mt.full, mt.description[:900], params, "mcp", run,
                    lambda a: json.dumps(a)[:120] if a else "")

    # ---- approvals when the UI is closed ----
    def maybe_notify(self, agent: Agent, info: dict) -> None:
        if self.ui_open or info["kind"] not in ("approval", "question", "plan"):
            return
        asyncio.create_task(self._notify(agent, info))

    async def _notify(self, agent: Agent, info: dict) -> None:
        if info["kind"] == "approval":
            title = "Agent wants to run " + info["tool"] + (" (risky)" if info.get("risky") else "")
            body = (info.get("summary") or "")[:200] + (f"\n{info['reason']}" if info.get("reason") else "")
            actions = ["--action=allow=Allow", "--action=deny=Deny"]
        elif info["kind"] == "plan":
            title, body = "Agent has a plan ready", "Open the sidebar (Super+A) to review it."
            actions = ["--action=open=Review"]
        else:
            title, body = "Agent has a question", info.get("question", "")[:240]
            actions = ["--action=open=Answer"]
        p = await asyncio.create_subprocess_exec(
            "notify-send", "-a", "SigniorAtif Agent", "-u", "critical", "--wait", *actions, title, body,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        try:
            out, _ = await asyncio.wait_for(p.communicate(), timeout=3600)
        except asyncio.TimeoutError:
            p.kill()
            return
        choice = out.decode().strip()
        if choice in ("allow", "deny"):
            agent.answer(info["rid"], {"decision": choice})
        elif choice == "open":
            await asyncio.create_subprocess_exec("qs", "-c", "rury", "ipc", "call", "sidebarLeft", "open",
                                                 stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
