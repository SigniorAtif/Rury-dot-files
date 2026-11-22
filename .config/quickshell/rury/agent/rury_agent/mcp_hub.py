"""MCP servers from mcp.json (Claude Code's `mcpServers` shape: command/args/env/cwd, or type http + url).

Their tools are deferred: the system prompt lists names only, and tool_search() loads a tool's schema into
the session so the model can call it. Each server runs in its own task (the SDK's streams must be opened and
closed by the same task). Servers listed in settings.desk_mcp_servers are started inside the agent desk's
environment, so a browser they open shows up on the desk.
"""
from __future__ import annotations

import asyncio
import json
import os
from contextlib import AsyncExitStack
from dataclasses import dataclass, field

from . import paths
from .desk import child_env

@dataclass
class McpTool:
    server: str
    name: str
    description: str
    schema: dict

    @property
    def full(self) -> str:
        return f"mcp__{self.server}__{self.name}"


@dataclass
class Server:
    name: str
    cfg: dict
    desk: bool = False
    tools: list[McpTool] = field(default_factory=list)
    error: str = ""
    session: object = None
    task: asyncio.Task | None = None
    stop: asyncio.Event = field(default_factory=asyncio.Event)
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    @property
    def state(self) -> str:
        return "on" if self.session else ("error" if self.error else "off")


def load_config() -> dict[str, dict]:
    try:
        d = json.loads(paths.MCP_JSON.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return {k: v for k, v in (d.get("mcpServers") or {}).items() if not v.get("disabled")}


def _field(obj, *names):
    for n in names:
        v = getattr(obj, n, None)
        if v is not None:
            return v
    return None


class Hub:
    def __init__(self, desk=None, desk_servers: list[str] | None = None):
        self.desk = desk
        self.desk_servers = set(desk_servers or [])
        self.servers: dict[str, Server] = {}
        self.cache_path = paths.STATE / "mcp-tools.json"
        self.reload()

    def reload(self) -> None:
        cfg = load_config()
        cached = self._read_cache()
        for name in list(self.servers):
            if name not in cfg:
                asyncio.ensure_future(self._close(self.servers.pop(name)))
        for name, c in cfg.items():
            if name not in self.servers:
                s = Server(name, c, desk=name in self.desk_servers)
                s.tools = [McpTool(name, t["name"], t.get("description", ""), t.get("schema", {}))
                           for t in cached.get(name, [])]
                self.servers[name] = s

    def _read_cache(self) -> dict:
        try:
            return json.loads(self.cache_path.read_text())
        except (OSError, json.JSONDecodeError):
            return {}

    def _write_cache(self) -> None:
        data = {n: [{"name": t.name, "description": t.description, "schema": t.schema} for t in s.tools]
                for n, s in self.servers.items() if s.tools}
        self.cache_path.parent.mkdir(parents=True, exist_ok=True)
        self.cache_path.write_text(json.dumps(data))

    # ---- lifecycle ----
    async def connect(self, name: str, timeout: float = 90) -> Server:
        s = self.servers[name]
        async with s.lock:
            if s.session:
                return s
            if s.desk and self.desk:
                await self.desk.start()
            s.error = ""
            s.stop = asyncio.Event()
            ready: asyncio.Future = asyncio.get_running_loop().create_future()
            s.task = asyncio.create_task(self._runner(s, ready))
            try:
                await asyncio.wait_for(asyncio.shield(ready), timeout)
            except Exception as e:  # noqa: BLE001 - any start failure is reported the same way
                s.error = s.error or f"{type(e).__name__}: {e}"
                s.stop.set()
                raise RuntimeError(f"MCP server {name} failed to start: {s.error}") from e
            self._write_cache()
            return s

    async def _runner(self, s: Server, ready: asyncio.Future) -> None:
        from mcp import ClientSession, StdioServerParameters
        from mcp.client.stdio import stdio_client
        try:
            async with AsyncExitStack() as stack:
                c = s.cfg
                if c.get("type") in ("http", "streamable-http", "sse") or c.get("url"):
                    if c.get("type") == "sse":
                        from mcp.client.sse import sse_client
                        read, write = await stack.enter_async_context(sse_client(c["url"], headers=c.get("headers")))
                    else:
                        from mcp.client.streamable_http import streamablehttp_client
                        read, write, _ = await stack.enter_async_context(
                            streamablehttp_client(c["url"], headers=c.get("headers")))
                else:
                    base = child_env() if s.desk else dict(os.environ)
                    env = {**base, **{k: os.path.expandvars(str(v)) for k, v in (c.get("env") or {}).items()}}
                    paths.LOGS.mkdir(parents=True, exist_ok=True)
                    errlog = stack.enter_context(open(paths.LOGS / f"mcp-{s.name}.log", "a"))
                    params = StdioServerParameters(command=c["command"], args=[os.path.expandvars(os.path.expanduser(str(a))) for a in c.get("args", [])],
                                                   env=env, cwd=c.get("cwd"))
                    read, write = await stack.enter_async_context(stdio_client(params, errlog=errlog))
                session = await stack.enter_async_context(ClientSession(read, write))
                await session.initialize()
                listed = await session.list_tools()
                # mcp >= 2 renamed the pydantic fields to snake_case; accept both
                s.tools = [McpTool(s.name, t.name, t.description or "",
                                   _field(t, "input_schema", "inputSchema") or {"type": "object"})
                           for t in listed.tools]
                s.session = session
                if not ready.done():
                    ready.set_result(True)
                await s.stop.wait()
        except BaseException as e:  # noqa: BLE001
            while isinstance(e, BaseExceptionGroup) and e.exceptions:   # anyio wraps the real cause
                e = e.exceptions[0]
            s.error = s.error or f"{type(e).__name__}: {e}"
            if not ready.done():
                ready.set_exception(RuntimeError(s.error))
        finally:
            s.session = None

    async def _close(self, s: Server) -> None:
        s.stop.set()
        if s.task:
            try:
                await asyncio.wait_for(s.task, 5)
            except (asyncio.TimeoutError, Exception):  # noqa: BLE001
                s.task.cancel()

    async def close(self) -> None:
        await asyncio.gather(*(self._close(s) for s in self.servers.values()), return_exceptions=True)

    async def close_desk(self) -> None:
        """The desk is going away: stop the servers whose browser lives on it."""
        await asyncio.gather(*(self._close(s) for s in self.servers.values() if s.desk and s.session),
                             return_exceptions=True)

    async def warm(self) -> None:
        """Connect the non-desk servers in the background so their tool lists are fresh."""
        for name, s in self.servers.items():
            if not s.desk and not s.session:
                try:
                    await self.connect(name)
                except RuntimeError:
                    pass

    # ---- tools ----
    def all_tools(self) -> list[McpTool]:
        return [t for s in self.servers.values() for t in s.tools]

    def find(self, full: str) -> McpTool | None:
        return next((t for t in self.all_tools() if t.full == full), None)

    async def ensure_listed(self) -> None:
        """Servers with no cached tool list get started to learn their tools (a failed one is retried)."""
        for name, s in self.servers.items():
            if not s.tools:
                try:
                    await self.connect(name)
                except RuntimeError:
                    pass

    # when many tools match equally well, offer the everyday actions first
    CORE_VERBS = ("navigate", "snapshot", "click", "type", "fill", "press", "select", "wait", "tabs", "screenshot",
                  "back", "hover", "scroll", "read", "list", "search", "get", "create", "open")

    def search(self, query: str, limit: int = 8) -> list[McpTool]:
        q = [w for w in query.lower().replace(",", " ").split() if w]
        scored = []
        for t in self.all_tools():
            if t.full == query or t.name == query:
                return [t]
            hay = f"{t.full} {t.description}".lower()
            score = sum(3 if w in t.name.lower() else 1 for w in q if w in hay)
            if score:
                verb = next((i for i, v in enumerate(self.CORE_VERBS) if v in t.name.lower()), len(self.CORE_VERBS))
                scored.append((-score, verb, t.name, t))
        scored.sort(key=lambda x: x[:3])
        return [x[3] for x in scored[:limit]]

    async def call(self, full: str, args: dict, timeout: float = 300):
        t = self.find(full)
        if not t:
            raise KeyError(full)
        s = self.servers[t.server]
        if s.desk and self.desk and not await self.desk.running():
            await self._close(s)  # the desk restarted: the server's display address is stale
        if not s.session:
            await self.connect(t.server)
        return await asyncio.wait_for(s.session.call_tool(t.name, args), timeout)

    def status(self) -> list[dict]:
        return [{"name": n, "state": s.state, "error": s.error, "desk": s.desk, "tools": len(s.tools),
                 "command": s.cfg.get("command") or s.cfg.get("url", "")} for n, s in self.servers.items()]
