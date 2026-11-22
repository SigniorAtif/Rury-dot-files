"""bash: one command per call, cwd carried between calls like a terminal."""
from __future__ import annotations

import os
import re

from . import Ctx, Result, Tool, clip, i, obj, run_proc, s

MARK = "__RURY_CWD__"


async def bash(args: dict, ctx: Ctx) -> Result:
    cmd = str(args.get("command", "")).strip()
    if not cmd:
        return Result("empty command", ok=False)
    timeout = min(int(args.get("timeout") or (ctx.services.settings.bash_timeout if ctx.services else 120)), 1800)
    cwd = ctx.cwd if os.path.isdir(ctx.cwd) else os.path.expanduser("~")
    script = f"{cmd}\n__rc=$?\nprintf '\\n{MARK}%s' \"$PWD\"\nexit $__rc"
    env = dict(os.environ)
    env.setdefault("TERM", "dumb")
    env["PAGER"] = "cat"
    env["GIT_PAGER"] = "cat"
    env["SYSTEMD_PAGER"] = ""
    code, out = await run_proc(script, ctx, cwd=cwd, timeout=timeout, env=env, shell=True)
    m = re.search(re.escape(MARK) + r"(.*)$", out)
    if m:
        new_cwd = m.group(1).strip()
        out = out[: m.start()].rstrip("\n")
        if new_cwd and os.path.isdir(new_cwd):
            ctx.cwd = new_cwd
    limit = ctx.services.settings.tool_output_chars if ctx.services else 6000
    text, full = clip(out, limit, ctx.session_id, "bash")
    if code:
        text = f"{text}\n[exit code {code}]".strip()
    return Result(text or "(no output)", ok=code == 0, meta={"exit": code, "cwd": ctx.cwd, "full": full})


def tools() -> list[Tool]:
    return [Tool(
        "bash",
        "Run a bash command on Atif's machine (Arch Linux, Hyprland). The working directory carries over "
        "between calls. Non-interactive only: no sudo (it is refused; ask Atif to run it), no editors, no "
        "pagers. Prefer read_file/grep/glob for reading files.",
        obj({"command": s("the command"), "timeout": i("seconds (default 120, max 1800)")}, ["command"]),
        "exec", bash, lambda a: a.get("command", "").split("\n")[0][:160])]
