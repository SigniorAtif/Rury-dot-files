"""Tool plumbing. A tool is a name, a JSON schema, a kind (which the permission gate reads) and an async run()."""
from __future__ import annotations

import asyncio
import os
import signal
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable

from .. import paths


@dataclass
class Result:
    text: str = ""
    images: list[str] = field(default_factory=list)   # data: URLs, shown to vision models
    ok: bool = True
    meta: dict = field(default_factory=dict)            # extra for the UI (diff, todo list, path ...)


@dataclass
class Ctx:
    """What a running tool can see and do."""
    session_id: str
    cwd: str
    mode: str
    emit: Callable[[str, dict], Awaitable[None]]                 # (event, payload) to the UI
    ask_user: Callable[[str, list[str]], Awaitable[str]]         # question, options -> answer
    services: Any = None                                         # the daemon's shared services (registry, mcp, desk ...)
    procs: set = field(default_factory=set)                      # running child processes (killed on stop)
    vision: bool = False
    state: dict = field(default_factory=dict)                    # per-session scratch (todo list, loaded tools)


@dataclass
class Tool:
    name: str
    description: str
    params: dict
    kind: str                                   # read | write | exec | desk | meta | risky | mcp
    run: Callable[[dict, Ctx], Awaitable[Result]]
    summary: Callable[[dict], str] | None = None   # one line for the UI card
    modes: tuple[str, ...] = ("plan", "ask", "auto")

    def schema(self) -> dict:
        return {"type": "function", "function": {"name": self.name, "description": self.description,
                                                 "parameters": self.params}}

    def describe(self, args: dict) -> str:
        if self.summary:
            try:
                return self.summary(args)
            except Exception:
                pass
        first = next(iter(args.values()), "") if args else ""
        return str(first)[:120]


def obj(props: dict, required: list[str] | None = None) -> dict:
    return {"type": "object", "properties": props, "required": required or []}


def s(desc: str, **kw) -> dict:
    return {"type": "string", "description": desc, **kw}


def i(desc: str, **kw) -> dict:
    return {"type": "integer", "description": desc, **kw}


def b(desc: str) -> dict:
    return {"type": "boolean", "description": desc}


async def run_proc(argv: list[str] | str, ctx: Ctx | None = None, *, cwd: str | None = None, timeout: float = 120,
                   env: dict | None = None, shell: bool = False, stdin: bytes | None = None) -> tuple[int, str]:
    """Run a command in its own process group; output is stdout+stderr merged. Killed on timeout or stop."""
    kw = dict(stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
              stdin=asyncio.subprocess.PIPE if stdin is not None else asyncio.subprocess.DEVNULL,
              cwd=cwd, env=env, start_new_session=True)
    if shell:
        p = await asyncio.create_subprocess_exec("bash", "-c", argv, **kw)
    else:
        p = await asyncio.create_subprocess_exec(*argv, **kw)
    if ctx is not None:
        ctx.procs.add(p)
    try:
        out, _ = await asyncio.wait_for(p.communicate(stdin), timeout=timeout)
        return p.returncode or 0, out.decode(errors="replace")
    except asyncio.TimeoutError:
        kill_group(p)
        out = b""
        try:
            out, _ = await asyncio.wait_for(p.communicate(), timeout=3)
        except (asyncio.TimeoutError, ValueError):
            pass
        return 124, out.decode(errors="replace") + f"\n[timed out after {timeout:.0f}s and was killed]"
    except asyncio.CancelledError:
        kill_group(p)
        raise
    finally:
        if ctx is not None:
            ctx.procs.discard(p)


def kill_group(p) -> None:
    try:
        os.killpg(p.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass


def clip(text: str, limit: int, session_id: str = "", label: str = "out") -> tuple[str, str]:
    """Head + tail of a long output; the whole thing goes to a file the model can read_file."""
    if len(text) <= limit:
        return text, ""
    paths.OUTPUTS.mkdir(parents=True, exist_ok=True)
    import time
    f = paths.OUTPUTS / f"{session_id or 'x'}-{label}-{int(time.time() * 1000)}.txt"
    f.write_text(text)
    head = text[: int(limit * 0.6)]
    tail = text[-int(limit * 0.35):]
    cut = len(text) - len(head) - len(tail)
    return f"{head}\n\n[... {cut} chars cut; full output in {f} ...]\n\n{tail}", str(f)
