"""Command line: `agent daemon | ask | status | models | desk start|stop|view|status`."""
from __future__ import annotations

import argparse
import asyncio
import json
import sys

from . import desk as desk_mod, paths


def _p(*a, **k):
    print(*a, **k, flush=True)


async def ask(args) -> int:
    """Run one prompt in-process (no daemon needed) and stream what happens. Like `claude -p`."""
    from .services import Services
    sv = Services()
    await sv.start()
    if args.model:
        sv.registry.get(args.model)
    agent = sv.new_session(args.mode, args.model, args.cwd)
    if args.think:
        sv.store.update(agent.sid, think=1)
    q = sv.subscribe()
    prompt = " ".join(args.prompt) if args.prompt else sys.stdin.read()
    await agent.send(prompt)
    try:
        await _stream(args, agent, q)
    finally:
        await sv.close()
        import gc
        gc.collect()            # finish finished subprocess transports while the loop still runs
        await asyncio.sleep(0.05)
    return 0


async def _stream(args, agent, q) -> None:
    in_text = False
    while True:
        ev = await q.get()
        e = ev["ev"]
        if args.json:
            _p(json.dumps({k: v for k, v in ev.items() if k != "images"}))
        elif e == "delta":
            if ev["kind"] == "text":
                sys.stdout.write(ev["text"])
                in_text = True
            elif args.show_thinking:
                sys.stdout.write(f"\x1b[2m{ev['text']}\x1b[0m")
            sys.stdout.flush()
        elif e == "item" and ev["item"]["type"] == "tool":
            it = ev["item"]
            _p(("\n" if in_text else "") + f"\x1b[36m● {it['name']}\x1b[0m {it.get('summary', '')}")
            in_text = False
        elif e == "item_update" and ev["item"]["type"] == "tool":
            it = ev["item"]
            mark = {"ok": "\x1b[32m✓", "error": "\x1b[31m✗", "denied": "\x1b[31m⊘", "blocked": "\x1b[33m⊘",
                    "cancelled": "\x1b[33m■"}.get(it["status"], "·")
            out = (it.get("output") or "").strip().splitlines()
            preview = (" " + out[0][:150]) if out else ""
            _p(f"  {mark}\x1b[0m{preview}" + (f" (+{len(out) - 1} lines)" if len(out) > 1 else ""))
        elif e == "item" and ev["item"]["type"] == "notice":
            _p(f"\n\x1b[33m[{ev['item']['text']}]\x1b[0m")
        elif e == "status" and ev["state"] == "loading":
            _p(f"\x1b[2m({ev['detail']}…)\x1b[0m")
        elif e in ("approval", "question", "plan"):
            ans = await _answer(ev, args.yes)
            agent.answer(ev["rid"], ans)
        elif e == "usage" and args.verbose:
            _p(f"\x1b[2m[{ev['prompt_tokens']}/{ev['ctx']} tok, {ev['tps']} tok/s, {ev['elapsed']}s]\x1b[0m")
        elif e == "done":
            _p("")
            break


async def _answer(ev: dict, yes: bool) -> dict:
    try:
        return await _answer_inner(ev, yes)
    except EOFError:
        _p("  (no input: denied)")
        return {"decision": "deny", "answer": ""}


async def _answer_inner(ev: dict, yes: bool) -> dict:
    loop = asyncio.get_running_loop()
    if ev["ev"] == "approval":
        tag = "RISKY " if ev.get("risky") else ""
        _p(f"\n\x1b[35m? {tag}{ev['tool']}: {ev.get('summary', '')}\x1b[0m" +
           (f"\n  ({ev['reason']})" if ev.get("reason") else ""))
        if yes:
            _p("  auto-approved (--yes)")
            return {"decision": "allow"}
        r = (await loop.run_in_executor(None, input, "  allow? [y]es / [n]o / [s]ession: ")).strip().lower()
        return {"decision": {"y": "allow", "s": "session"}.get(r[:1], "deny")}
    if ev["ev"] == "plan":
        _p(f"\n\x1b[35m── plan ──\x1b[0m\n{ev['plan']}\n")
        if yes:
            return {"decision": "auto"}
        r = (await loop.run_in_executor(None, input, "  approve? [a]uto / a[s]k / [k]eep planning: ")).strip().lower()
        return {"decision": {"a": "auto", "s": "ask"}.get(r[:1], "keep")}
    _p(f"\n\x1b[35m? {ev['question']}\x1b[0m " + (f"({' / '.join(ev['options'])})" if ev.get("options") else ""))
    if yes:
        return {"answer": ev["options"][0] if ev.get("options") else "yes"}
    return {"answer": await loop.run_in_executor(None, input, "  > ")}


async def call_daemon(msg: dict) -> dict:
    r, w = await asyncio.open_unix_connection(str(paths.SOCKET))
    msg = {"rid": 1, **msg}
    w.write((json.dumps(msg) + "\n").encode())
    await w.drain()
    while line := await r.readline():
        ev = json.loads(line)
        if ev.get("ev") == "reply" and ev.get("rid") == 1:
            w.close()
            if not ev["ok"]:
                raise RuntimeError(ev["error"])
            return ev["data"]
    raise RuntimeError("daemon closed the connection")


async def desk_cmd(args) -> int:
    action = args.action
    if paths.SOCKET.exists():
        try:
            d = await call_daemon({"cmd": "desk", "action": action, "control": args.control})
            _p(json.dumps(d))
            return 0
        except (OSError, RuntimeError):
            pass
    d = desk_mod.Desk()
    if action == "start" or action == "view":
        await d.start()
    if action == "stop":
        await d.stop()
    if action == "view":
        desk_mod.open_viewer(args.control)
    _p(json.dumps({"running": await d.running()}))
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="agent", description="SigniorAtif agent")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("daemon", help="run the daemon (systemd: rury-agent.service)")
    a = sub.add_parser("ask", help="run one prompt in-process and stream it")
    a.add_argument("prompt", nargs="*")
    a.add_argument("--mode", default="ask", choices=["chat", "plan", "ask", "auto"])
    a.add_argument("--model")
    a.add_argument("--cwd")
    a.add_argument("--think", action="store_true", help="let the model think before answering")
    a.add_argument("--yes", action="store_true", help="approve every ask (hard denies still refuse)")
    a.add_argument("--json", action="store_true", help="print raw events")
    a.add_argument("--show-thinking", action="store_true")
    a.add_argument("-v", "--verbose", action="store_true")
    sub.add_parser("models", help="list models")
    sub.add_parser("status", help="daemon status")
    d = sub.add_parser("desk", help="the agent's own desktop")
    d.add_argument("action", choices=["start", "stop", "view", "status"])
    d.add_argument("--control", action="store_true", default=None, help="view with mouse/keyboard control")
    args = ap.parse_args(argv)

    if args.cmd == "daemon":
        from .daemon import main as dmain
        dmain()
        return 0
    if args.cmd == "ask":
        return asyncio.run(ask(args))
    if args.cmd == "models":
        from .models import Registry

        async def go():
            r = Registry()
            await r.refresh()
            for m in r.listing():
                _p(f"{'*' if m['default'] else ' '} {m['id']:<50} {m['kind']:<9} vision={m['vision']} ctx={m['ctx']}")
        asyncio.run(go())
        return 0
    if args.cmd == "status":
        try:
            _p(json.dumps(asyncio.run(call_daemon({"cmd": "status"})), indent=1))
        except (OSError, RuntimeError) as e:
            _p(f"daemon not reachable: {e}")
            return 1
        return 0
    if args.cmd == "desk":
        return asyncio.run(desk_cmd(args))
    return 1
