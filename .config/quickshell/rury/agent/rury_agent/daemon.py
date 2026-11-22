"""The daemon: a unix socket speaking JSON lines.

Client -> daemon: {"cmd": "...", "rid": 1, ...}            reply: {"ev": "reply", "rid": 1, "ok": true, "data": ...}
Daemon -> every client: events {"ev": "...", "sid": "...", ...} (status, delta, item, item_update, approval,
question, plan, resolved, todo, usage, error, done, session, queued, model_state, desk, automations, models)
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import time
import traceback

from . import automations, desk as desk_mod, paths
from .services import Services

log = logging.getLogger("rury-agent")


class Daemon:
    def __init__(self):
        self.sv = Services()
        self.server: asyncio.AbstractServer | None = None
        self.stopping = asyncio.Event()
        self.ui_clients: dict[int, bool] = {}

    async def run(self) -> None:
        await self.sv.start()
        paths.RUN.mkdir(parents=True, exist_ok=True)
        if paths.SOCKET.exists():
            paths.SOCKET.unlink()
        self.server = await asyncio.start_unix_server(self.client, path=str(paths.SOCKET), limit=64 * 1024 * 1024)
        os.chmod(paths.SOCKET, 0o600)
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, self.stopping.set)
        bg = [asyncio.create_task(self.scheduler()), asyncio.create_task(self.reaper()),
              asyncio.create_task(self.sv.mcp.warm())]
        log.info("listening on %s", paths.SOCKET)
        await self.stopping.wait()
        for t in bg:
            t.cancel()
        self.server.close()
        await self.sv.close()
        try:
            paths.SOCKET.unlink()
        except OSError:
            pass

    # ---- clients ----
    async def client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        q = self.sv.subscribe()
        cid = id(writer)

        async def pump():
            while True:
                ev = await q.get()
                writer.write((json.dumps(ev) + "\n").encode())
                await writer.drain()

        pumper = asyncio.create_task(pump())
        try:
            while line := await reader.readline():
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    continue
                rid = msg.get("rid")
                try:
                    data = await self.handle(msg, cid)
                    reply = {"ev": "reply", "rid": rid, "ok": True, "data": data}
                except Exception as e:  # noqa: BLE001 - errors go back to the caller
                    log.warning("%s failed: %s: %s", msg.get("cmd"), type(e).__name__, e)
                    log.debug(traceback.format_exc())
                    reply = {"ev": "reply", "rid": rid, "ok": False, "error": f"{type(e).__name__}: {e}"}
                q.put_nowait(reply)
        except (ConnectionResetError, BrokenPipeError):
            pass
        finally:
            pumper.cancel()
            self.sv.unsubscribe(q)
            self.ui_clients.pop(cid, None)
            self.sv.ui_open = any(self.ui_clients.values())
            writer.close()

    async def handle(self, m: dict, cid: int):
        cmd = m.get("cmd", "")
        sv = self.sv
        if cmd in ("send", "stop", "answer", "set", "desk", "archive", "compact", "model_stop") or cmd.startswith("automation_"):
            detail = {k: m[k] for k in ("sid", "action", "control", "mode", "model", "id") if k in m}
            log.info("client %s: %s %s", cid, cmd, detail or "")

        if cmd == "hello":
            return {"version": 1, "models": sv.registry.listing(), "default_mode": sv.settings.default_mode,
                    "sessions": sv.store.list(30), "model_state": sv.llama.state,
                    "loaded_model": sv.llama.spec.id if sv.llama.spec else "",
                    "desk": await sv.desk.running(), "automations": sv.store.automations()}
        if cmd == "ui":
            self.ui_clients[cid] = bool(m.get("open"))
            sv.ui_open = any(self.ui_clients.values())
            return {}
        if cmd == "new":
            a = sv.new_session(m.get("mode"), m.get("model"), m.get("cwd"))
            return a.public()
        if cmd == "sessions":
            return sv.store.list(int(m.get("limit", 50)))
        if cmd == "load":
            a = sv.agent(m["sid"])
            return {"session": a.public(), "items": sv.store.items(a.sid)}
        if cmd == "archive":
            await sv.agent(m["sid"]).stop()
            sv.store.archive(m["sid"])
            sv.agents.pop(m["sid"], None)
            return {}
        if cmd == "send":
            sid = m.get("sid")
            a = sv.agent(sid) if sid else sv.new_session(m.get("mode"), m.get("model"), m.get("cwd"))
            images = [sv.store.save_image(u) if u.startswith("data:") else sv.store.keep_image(u)
                      for u in m.get("images", [])]
            await a.send(str(m.get("text", "")), images)
            return {"sid": a.sid}
        if cmd == "stop":
            await sv.agent(m["sid"]).stop()
            return {}
        if cmd == "answer":
            ok = sv.agent(m["sid"]).answer(m["rid_answer"], m.get("answer") or {})
            return {"ok": ok}
        if cmd == "set":
            a = sv.agent(m["sid"])
            if "mode" in m:
                await a.set_mode(m["mode"])
            if "model" in m:
                sv.registry.get(m["model"])  # raises on unknown ids
                sv.store.update(a.sid, model=m["model"])
            if "think" in m:
                sv.store.update(a.sid, think=1 if m["think"] else 0)
            if "cwd" in m:
                a.ctx.cwd = os.path.expanduser(m["cwd"])
                sv.store.update(a.sid, cwd=a.ctx.cwd)
            if "title" in m:
                sv.store.update(a.sid, title=str(m["title"])[:80])
            pub = a.public()
            await sv.broadcast({"ev": "session", "sid": a.sid, "session": pub})
            return pub
        if cmd == "compact":
            a = sv.agent(m["sid"])
            if a.running:
                raise RuntimeError("wait for the current run to finish")
            await a.compact()
            await a.set_status("idle")
            return {}
        if cmd == "models":
            await sv.registry.refresh()
            data = sv.registry.listing()
            await sv.broadcast({"ev": "models", "models": data})
            return data
        if cmd == "model_stop":
            await sv.llama.stop()
            return {}
        if cmd == "skills":
            return [{"name": s.name, "description": s.description, "path": str(s.path)} for s in sv.skills()]
        if cmd == "mcp":
            if m.get("reload"):
                sv.mcp.reload()
                asyncio.create_task(sv.mcp.warm())
            return sv.mcp.status()
        if cmd == "automations":
            return sv.store.automations()
        if cmd == "automation_set":
            sv.store.update_automation(m["id"], **{k: m[k] for k in ("enabled", "name", "prompt", "schedule", "mode")
                                                   if k in m})
            if "schedule" in m or m.get("enabled"):
                a = next(x for x in sv.store.automations() if x["id"] == m["id"])
                sv.store.update_automation(m["id"], next_run=automations.next_run(a["schedule"]))
            await self._automations_changed()
            return {}
        if cmd == "automation_delete":
            sv.store.delete_automation(m["id"])
            await self._automations_changed()
            return {}
        if cmd == "automation_run":
            a = next(x for x in sv.store.automations() if x["id"] == m["id"])
            return {"sid": await self.run_automation(a)}
        if cmd == "desk":
            action = m.get("action", "status")
            if action == "start":
                await sv.desk.start()
            elif action == "stop":
                await sv.mcp.close_desk()
                await sv.desk.stop()
            elif action == "view":
                await sv.refresh_session_env()
                await sv.desk.start()
                await asyncio.to_thread(desk_mod.open_viewer, m.get("control"), m.get("toggle", True))
            return {"running": await sv.desk.running(), "last_action": sv.desk.last_action,
                    "control": desk_mod.viewer_control, "shown": desk_mod.special_visible()}
        if cmd == "status":
            return {"sessions": {sid: a.status for sid, a in sv.agents.items()}, "model_state": sv.llama.state,
                    "desk": await sv.desk.running()}
        raise ValueError(f"unknown command {cmd!r}")

    async def _automations_changed(self) -> None:
        await self.sv.broadcast({"ev": "automations", "automations": self.sv.store.automations()})

    # ---- background ----
    async def run_automation(self, a: dict) -> str:
        sv = self.sv
        agent = sv.new_session(a.get("mode") or "auto", a.get("model") or None, kind="automation",
                               title=f"⏱ {a['name']}")
        sv.store.update_automation(a["id"], last_run=time.time(), last_session=agent.sid)
        await agent.send(a["prompt"])

        async def report():
            await agent.task
            items = sv.store.items(agent.sid)
            last = next((it.get("text", "") for it in reversed(items) if it["type"] == "assistant" and it.get("text")),
                        "")
            await asyncio.create_subprocess_exec("notify-send", "-a", "SigniorAtif Agent", f"Automation: {a['name']}",
                                                 (last or "finished")[:300])
        asyncio.create_task(report())
        return agent.sid

    async def scheduler(self) -> None:
        while True:
            await asyncio.sleep(20)
            now = time.time()
            for a in self.sv.store.automations():
                if not a["enabled"] or not a["next_run"] or a["next_run"] > now:
                    continue
                try:
                    nxt = automations.next_run(a["schedule"], now)
                except ValueError:
                    nxt = None
                self.sv.store.update_automation(a["id"], next_run=nxt, enabled=1 if nxt else 0)
                try:
                    await self.run_automation(a)
                except Exception:  # noqa: BLE001
                    log.exception("automation %s failed to start", a["id"])
                await self._automations_changed()

    async def reaper(self) -> None:
        while True:
            await asyncio.sleep(30)
            busy = any(a.running for a in self.sv.agents.values())
            await self.sv.llama.reap_idle(busy)


def main() -> None:
    paths.ensure_dirs()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s",
                        handlers=[logging.StreamHandler(), logging.FileHandler(paths.LOGS / "daemon.log")])
    asyncio.run(Daemon().run())
