"""The agent's hands and eyes on its own desk. Coordinates are 0-1000 on both axes, (0,0) top-left."""
from __future__ import annotations

import asyncio
import base64
import io
import os
import re
import shlex

from .. import paths
from . import Ctx, Result, Tool, b, i, obj, run_proc, s

COORD = "0-1000 (0 = left/top edge, 1000 = right/bottom edge)"
FONT = "/usr/share/fonts/noto/NotoSans-Regular.ttf"

KEY_ALIASES = {
    "enter": "Return", "return": "Return", "esc": "Escape", "escape": "Escape", "tab": "Tab",
    "backspace": "BackSpace", "bksp": "BackSpace", "delete": "Delete", "del": "Delete", "space": "space",
    "up": "Up", "down": "Down", "left": "Left", "right": "Right", "home": "Home", "end": "End",
    "pageup": "Page_Up", "pgup": "Page_Up", "pagedown": "Page_Down", "pgdn": "Page_Down", "insert": "Insert",
    "menu": "Menu", "print": "Print",
}
MODS = {"ctrl": "ctrl", "control": "ctrl", "shift": "shift", "alt": "alt", "super": "logo", "meta": "logo",
        "win": "logo", "logo": "logo", "cmd": "logo", "altgr": "altgr"}
BUTTONS = {"left": "button1", "middle": "button2", "right": "button3"}


def _desk(ctx: Ctx):
    return ctx.services.desk


async def _shot(ctx: Ctx, grid: bool = False, region: tuple[int, int, int, int] | None = None) -> tuple[str, str]:
    """(data URL, note). region is in 0-1000 coords; the crop is scaled up and gridded in screen coords."""
    from PIL import Image, ImageDraw, ImageFont
    desk = _desk(ctx)
    env = await desk.ensure()
    p = await asyncio.create_subprocess_exec("grim", "-c", "-t", "png", "-", stdout=asyncio.subprocess.PIPE,
                                             stderr=asyncio.subprocess.PIPE, env=env)
    out, err = await p.communicate()
    if p.returncode:
        raise RuntimeError(f"screenshot failed: {err.decode(errors='replace').strip()}")
    img = Image.open(io.BytesIO(out)).convert("RGB")
    W, H = img.size
    x0, y0, x1, y1 = 0, 0, 1000, 1000
    if region:
        x0, y0, x1, y1 = [max(0, min(1000, int(v))) for v in region]
        if x1 - x0 < 20 or y1 - y0 < 20:
            raise ValueError("zoom region is too small (at least 20 units each way)")
        img = img.crop((round(x0 / 1000 * W), round(y0 / 1000 * H), round(x1 / 1000 * W), round(y1 / 1000 * H)))
        scale = min(1280 / img.width, 800 / img.height)
        img = img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)
    if grid or region:
        d = ImageDraw.Draw(img, "RGBA")
        try:
            font = ImageFont.truetype(FONT, 13)
        except OSError:
            font = ImageFont.load_default()
        span = max(x1 - x0, y1 - y0)
        step = 100 if span > 500 else 50 if span > 200 else 20 if span > 80 else 10
        for v in range((x0 // step + 1) * step, x1, step):
            X = round((v - x0) / (x1 - x0) * img.width)
            d.line((X, 0, X, img.height), fill=(255, 230, 0, 60))
            d.text((X + 2, 2), str(v), fill=(255, 230, 0, 235), font=font, stroke_width=2, stroke_fill=(0, 0, 0, 200))
        for v in range((y0 // step + 1) * step, y1, step):
            Y = round((v - y0) / (y1 - y0) * img.height)
            d.line((0, Y, img.width, Y), fill=(255, 230, 0, 60))
            d.text((2, Y + 2), str(v), fill=(255, 230, 0, 235), font=font, stroke_width=2, stroke_fill=(0, 0, 0, 200))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=82)
    paths.RUN.mkdir(parents=True, exist_ok=True)
    (paths.RUN / "desk-last.jpg").write_bytes(buf.getvalue())
    note = (f"desk screenshot, region x {x0}-{x1}, y {y0}-{y1} (grid labels are screen coordinates)"
            if region else "desk screenshot" + (" with a coordinate grid" if grid else ""))
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode(), note


async def _windows_text(ctx: Ctx) -> str:
    wins = await _desk(ctx).windows()
    if not wins:
        return "no windows open on the desk"
    return "\n".join(f"{'*' if w['focused'] else ' '} id={w['id']} {w['app'] or '?'} \"{w['title'][:80]}\" "
                     f"box={w['box']}" for w in wins)


async def desk_screenshot(args: dict, ctx: Ctx) -> Result:
    if not ctx.vision:
        return Result("this model can't see images; use desk_windows and the playwright browser tools instead.\n"
                      + await _windows_text(ctx), ok=False)
    url, note = await _shot(ctx, grid=bool(args.get("grid")))
    return Result(f"{note}\nwindows:\n{await _windows_text(ctx)}", images=[url])


async def desk_zoom(args: dict, ctx: Ctx) -> Result:
    if not ctx.vision:
        return Result("this model can't see images", ok=False)
    reg = (args.get("x1", 0), args.get("y1", 0), args.get("x2", 1000), args.get("y2", 1000))
    try:
        url, note = await _shot(ctx, region=tuple(int(v) for v in reg))
    except ValueError as e:
        return Result(str(e), ok=False)
    return Result(note, images=[url])


async def desk_windows(args: dict, ctx: Ctx) -> Result:
    return Result(await _windows_text(ctx))


async def _cursor(ctx: Ctx, x, y) -> tuple[int, int]:
    X, Y = _desk(ctx).px(x, y)
    code, out = await _desk(ctx).swaymsg("seat", "-", "cursor", "set", str(X), str(Y))
    if code:
        raise RuntimeError(out.strip())
    return X, Y


async def desk_click(args: dict, ctx: Ctx) -> Result:
    btn = BUTTONS.get(str(args.get("button", "left")).lower(), "button1")
    clicks = max(1, min(int(args.get("clicks") or 1), 3))
    await _cursor(ctx, args["x"], args["y"])
    for n in range(clicks):
        await _desk(ctx).swaymsg("seat", "-", "cursor", "press", btn)
        await _desk(ctx).swaymsg("seat", "-", "cursor", "release", btn)
        if n + 1 < clicks:
            await asyncio.sleep(0.05)
    await asyncio.sleep(0.3)
    what = f"{'double-' if clicks == 2 else ''}{args.get('button', 'left')} click at ({args['x']}, {args['y']})"
    _desk(ctx).note(what)
    return await _after(ctx, args, what)


async def desk_move(args: dict, ctx: Ctx) -> Result:
    await _cursor(ctx, args["x"], args["y"])
    _desk(ctx).note(f"hover ({args['x']}, {args['y']})")
    return await _after(ctx, args, f"moved the pointer to ({args['x']}, {args['y']})")


async def desk_drag(args: dict, ctx: Ctx) -> Result:
    await _cursor(ctx, args["x1"], args["y1"])
    await _desk(ctx).swaymsg("seat", "-", "cursor", "press", "button1")
    steps = 8
    for k in range(1, steps + 1):
        x = args["x1"] + (args["x2"] - args["x1"]) * k / steps
        y = args["y1"] + (args["y2"] - args["y1"]) * k / steps
        await _cursor(ctx, x, y)
        await asyncio.sleep(0.02)
    await _desk(ctx).swaymsg("seat", "-", "cursor", "release", "button1")
    what = f"dragged ({args['x1']}, {args['y1']}) to ({args['x2']}, {args['y2']})"
    _desk(ctx).note(what)
    return await _after(ctx, args, what)


async def desk_scroll(args: dict, ctx: Ctx) -> Result:
    direction = str(args.get("direction", "down")).lower()
    btn = {"up": "button4", "down": "button5", "left": "button6", "right": "button7"}.get(direction, "button5")
    if "x" in args and "y" in args:
        await _cursor(ctx, args["x"], args["y"])
    for _ in range(max(1, min(int(args.get("amount") or 3), 30))):
        await _desk(ctx).swaymsg("seat", "-", "cursor", "press", btn)
    await asyncio.sleep(0.2)
    what = f"scrolled {direction}"
    _desk(ctx).note(what)
    return await _after(ctx, args, what)


def _wtype_key_args(combo: str) -> list[str]:
    parts = [p for p in re.split(r"\s*\+\s*", combo.strip()) if p]
    if not parts:
        raise ValueError("empty key")
    *mods, key = parts
    argv: list[str] = []
    for m in mods:
        mm = MODS.get(m.lower())
        if not mm:
            raise ValueError(f"unknown modifier {m!r}")
        argv += ["-M", mm]
    k = KEY_ALIASES.get(key.lower(), key)
    if re.fullmatch(r"[fF]\d{1,2}", k):
        k = k.upper()
    if len(k) == 1 and not k.isalnum():
        if mods:
            raise ValueError(f"use the key name for {k!r} with modifiers (e.g. slash, comma, period, minus)")
        return ["--", k]   # a lone punctuation key: just type it
    if len(k) == 1:
        k = k.lower()      # keysym "l", not "L" (which would mean shift)
    argv += ["-k", k]
    for m in reversed(mods):
        argv += ["-m", MODS[m.lower()]]
    return argv


async def desk_key(args: dict, ctx: Ctx) -> Result:
    env = await _desk(ctx).ensure()
    keys = str(args.get("keys", ""))
    done = []
    for combo in keys.split():
        try:
            argv = _wtype_key_args(combo)
        except ValueError as e:
            return Result(str(e), ok=False)
        code, out = await run_proc(["wtype", *argv], ctx, env=env, timeout=10)
        if code:
            return Result(f"wtype failed on {combo}: {out.strip()}", ok=False)
        done.append(combo)
        await asyncio.sleep(0.05)
    what = "pressed " + " ".join(done)
    _desk(ctx).note(what)
    return await _after(ctx, args, what)


async def desk_type(args: dict, ctx: Ctx) -> Result:
    env = await _desk(ctx).ensure()
    text = str(args.get("text", ""))
    code, out = await run_proc(["wtype", "-d", "4", "--", text], ctx, env=env, timeout=120)
    if code:
        return Result(f"typing failed: {out.strip()}", ok=False)
    if args.get("enter"):
        await run_proc(["wtype", "-k", "Return"], ctx, env=env, timeout=10)
    what = f"typed {len(text)} characters" + (" and pressed Enter" if args.get("enter") else "")
    _desk(ctx).note(what)
    return await _after(ctx, args, what)


BROWSERS = {
    "firefox": lambda: f"firefox --no-remote --profile {shlex.quote(str(paths.DATA / 'firefox'))}",
    "brave": lambda: f"brave --user-data-dir={shlex.quote(str(paths.DATA / 'brave'))} --no-first-run "
                     f"--ozone-platform=wayland --force-renderer-accessibility",
    "chromium": lambda: f"chromium --user-data-dir={shlex.quote(str(paths.DATA / 'chromium'))} --no-first-run "
                        f"--ozone-platform=wayland",
}


async def desk_launch(args: dict, ctx: Ctx) -> Result:
    cmd = str(args.get("command", "")).strip()
    if not cmd:
        return Result("empty command", ok=False)
    first, _, rest = cmd.partition(" ")
    if first in BROWSERS:
        (paths.DATA / first).mkdir(parents=True, exist_ok=True)
        cmd = BROWSERS[first]() + (" " + rest if rest else "")
    code, out = await _desk(ctx).swaymsg("exec", cmd)
    if code:
        return Result(f"launch failed: {out.strip()}", ok=False)
    await asyncio.sleep(float(args.get("wait") or 3))
    _desk(ctx).note(f"launched {first}")
    return await _after(ctx, {**args, "screenshot": args.get("screenshot", True)}, f"launched {first} on the desk")


async def desk_focus(args: dict, ctx: Ctx) -> Result:
    wid = args.get("id")
    sel = f"[con_id={int(wid)}]" if wid is not None else f"[title=\"(?i){re.escape(str(args.get('title', '')))}\"]"
    code, out = await _desk(ctx).swaymsg(sel, "focus")
    if code or '"success": false' in out:
        return Result(f"focus failed: {out.strip()}", ok=False)
    _desk(ctx).note("focused a window")
    return Result("focused\n" + await _windows_text(ctx))


async def desk_close(args: dict, ctx: Ctx) -> Result:
    code, out = await _desk(ctx).swaymsg(f"[con_id={int(args['id'])}]", "kill")
    return Result("closed" if not code else out.strip(), ok=not code)


async def _after(ctx: Ctx, args: dict, what: str) -> Result:
    if args.get("screenshot") and ctx.vision:
        url, note = await _shot(ctx)
        return Result(f"{what}. {note} after the action:", images=[url])
    return Result(what + ". (take a desk_screenshot to check the result)")


XY = {"x": i(f"x, {COORD}"), "y": i(f"y, {COORD}")}
SHOT = {"screenshot": b("take a screenshot after the action")}


def tools() -> list[Tool]:
    return [
        Tool("desk_screenshot", "See your own desktop (the agent desk, not Atif's screen). Coordinates in every desk "
             f"tool are {COORD}. grid=true overlays labelled coordinate lines to help you aim.",
             obj({"grid": b("overlay a labelled coordinate grid")}), "read", desk_screenshot,
             lambda a: "grid" if a.get("grid") else ""),
        Tool("desk_zoom", "Look closely at part of your desk: a crop scaled up, gridded in screen coordinates. "
             "Use it before clicking small things.",
             obj({"x1": i("left"), "y1": i("top"), "x2": i("right"), "y2": i("bottom")}, ["x1", "y1", "x2", "y2"]),
             "read", desk_zoom, lambda a: f"({a.get('x1')},{a.get('y1')})-({a.get('x2')},{a.get('y2')})"),
        Tool("desk_windows", "List the windows on your desk with ids, titles and boxes.", obj({}), "read",
             desk_windows),
        Tool("desk_click", "Click on your desk with your own pointer.",
             obj({**XY, "button": s("left, right or middle"), "clicks": i("1, 2 (double) or 3"), **SHOT},
                 ["x", "y"]),
             "desk", desk_click, lambda a: f"({a.get('x')}, {a.get('y')}) {a.get('button', '')}".strip()),
        Tool("desk_move", "Move your pointer (hover).", obj({**XY, **SHOT}, ["x", "y"]), "desk", desk_move,
             lambda a: f"({a.get('x')}, {a.get('y')})"),
        Tool("desk_drag", "Drag with the left button held.",
             obj({"x1": i("from x"), "y1": i("from y"), "x2": i("to x"), "y2": i("to y"), **SHOT},
                 ["x1", "y1", "x2", "y2"]), "desk", desk_drag),
        Tool("desk_scroll", "Scroll on your desk, at a point if given.",
             obj({**XY, "direction": s("up, down, left or right"), "amount": i("notches (default 3)"), **SHOT},
                 ["direction"]), "desk", desk_scroll, lambda a: f"{a.get('direction')} {a.get('amount', 3)}"),
        Tool("desk_type", "Type text into the focused window on your desk.",
             obj({"text": s("text to type"), "enter": b("press Enter after"), **SHOT}, ["text"]), "desk",
             desk_type, lambda a: str(a.get("text", ""))[:60]),
        Tool("desk_key", "Press keys on your desk: space-separated combos like `ctrl+l`, `Return`, `alt+F4`, "
             "`ctrl+shift+t Tab Tab`.",
             obj({"keys": s("key combos"), **SHOT}, ["keys"]), "desk", desk_key, lambda a: a.get("keys", "")),
        Tool("desk_launch", "Start an app on your desk (e.g. `firefox https://example.com`, `brave`, `nautilus`, "
             "`foot`). Browsers get the agent's own profile. Takes a screenshot after.",
             obj({"command": s("command line"), "wait": i("seconds to wait before the screenshot (default 3)")},
                 ["command"]), "desk", desk_launch, lambda a: a.get("command", "")),
        Tool("desk_focus", "Focus a desk window by id or title.",
             obj({"id": i("window id from desk_windows"), "title": s("part of the title")}), "desk", desk_focus),
        Tool("desk_close", "Close a desk window by id.", obj({"id": i("window id")}, ["id"]), "desk", desk_close),
    ]
