"""read_file, write_file, edit_file, glob, grep."""
from __future__ import annotations

import base64
import difflib
import io
import mimetypes
import os
from pathlib import Path

from ..permissions import resolve
from . import Ctx, Result, Tool, b, i, obj, run_proc, s

IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"}


def _p(args: dict, ctx: Ctx) -> Path:
    return Path(resolve(str(args.get("path", "")), ctx.cwd))


def image_data_url(path: Path, max_side: int = 1280) -> str:
    from PIL import Image
    img = Image.open(path)
    img = img.convert("RGB")
    img.thumbnail((max_side, max_side))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=85)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


async def read_file(args: dict, ctx: Ctx) -> Result:
    p = _p(args, ctx)
    if not p.exists():
        return Result(f"{p} does not exist", ok=False)
    if p.is_dir():
        names = sorted(os.listdir(p))[:500]
        return Result(f"{p} is a directory:\n" + "\n".join(names))
    if p.suffix.lower() in IMAGE_EXT:
        if not ctx.vision:
            return Result(f"{p} is an image and this model can't see images", ok=False)
        return Result(f"image {p}", images=[image_data_url(p)])
    data = p.read_bytes()
    if b"\x00" in data[:4096]:
        mt = mimetypes.guess_type(p.name)[0] or "binary"
        return Result(f"{p} is a binary file ({mt}, {len(data)} bytes)", ok=False)
    lines = data.decode(errors="replace").splitlines()
    off = max(int(args.get("offset") or 1), 1)
    lim = int(args.get("limit") or 400)
    chunk = lines[off - 1: off - 1 + lim]
    body = "\n".join(f"{n:>5}\t{line[:500]}" for n, line in enumerate(chunk, off))
    more = len(lines) - (off - 1 + len(chunk))
    if more > 0:
        body += f"\n[{more} more lines; read again with offset={off + len(chunk)}]"
    return Result(body or "(empty file)")


async def write_file(args: dict, ctx: Ctx) -> Result:
    p = _p(args, ctx)
    content = str(args.get("content", ""))
    old = p.read_text(errors="replace") if p.is_file() else None
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    diff = _diff(old or "", content, str(p)) if old is not None else ""
    verb = "overwrote" if old is not None else "created"
    return Result(f"{verb} {p} ({len(content)} chars)", meta={"path": str(p), "diff": diff})


async def edit_file(args: dict, ctx: Ctx) -> Result:
    p = _p(args, ctx)
    if not p.is_file():
        return Result(f"{p} does not exist", ok=False)
    old_s, new_s = str(args.get("old", "")), str(args.get("new", ""))
    text = p.read_text(errors="replace")
    n = text.count(old_s) if old_s else 0
    if n == 0:
        return Result("old text not found; read the file again and copy the text exactly (whitespace included)",
                      ok=False)
    if n > 1 and not args.get("replace_all"):
        return Result(f"old text occurs {n} times; add surrounding lines to make it unique or set replace_all",
                      ok=False)
    out = text.replace(old_s, new_s) if args.get("replace_all") else text.replace(old_s, new_s, 1)
    p.write_text(out)
    return Result(f"edited {p} ({n if args.get('replace_all') else 1} replacement)",
                  meta={"path": str(p), "diff": _diff(text, out, str(p))})


def _diff(a: str, b_: str, name: str) -> str:
    d = difflib.unified_diff(a.splitlines(), b_.splitlines(), name, name, n=2, lineterm="")
    return "\n".join(list(d)[:400])


async def glob_(args: dict, ctx: Ctx) -> Result:
    root = Path(resolve(str(args.get("path") or ctx.cwd), ctx.cwd))
    pat = str(args.get("pattern", "*"))
    try:
        hits = [p for p in root.glob(pat) if ".git/" not in str(p)]
    except (ValueError, OSError) as e:
        return Result(f"bad pattern: {e}", ok=False)
    hits.sort(key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    shown = hits[:200]
    txt = "\n".join(str(p) for p in shown) or "no matches"
    if len(hits) > 200:
        txt += f"\n[{len(hits) - 200} more]"
    return Result(txt)


async def grep(args: dict, ctx: Ctx) -> Result:
    root = resolve(str(args.get("path") or ctx.cwd), ctx.cwd)
    argv = ["rg", "--no-heading", "--line-number", "--color=never", "--max-columns=300", "-m", "50"]
    if args.get("ignore_case"):
        argv.append("-i")
    if args.get("glob"):
        argv += ["--glob", str(args["glob"])]
    if args.get("files_only"):
        argv.append("-l")
    if c := args.get("context"):
        argv += ["-C", str(int(c))]
    argv += ["--", str(args.get("pattern", "")), root]
    code, out = await run_proc(argv, ctx, timeout=60)
    if code == 1:
        return Result("no matches")
    lines = out.splitlines()
    if len(lines) > 300:
        out = "\n".join(lines[:300]) + f"\n[{len(lines) - 300} more lines]"
    return Result(out, ok=code in (0, 1))


def tools() -> list[Tool]:
    return [
        Tool("read_file", "Read a text file (line-numbered), list a directory, or look at an image.",
             obj({"path": s("absolute path or relative to cwd"),
                  "offset": i("first line, 1-based"), "limit": i("how many lines (default 400)")}, ["path"]),
             "read", read_file, lambda a: a.get("path", "")),
        Tool("write_file", "Create or overwrite a file with the given content.",
             obj({"path": s("file path"), "content": s("the whole new content")}, ["path", "content"]),
             "write", write_file, lambda a: a.get("path", "")),
        Tool("edit_file", "Replace exact text in a file. `old` must match exactly once unless replace_all.",
             obj({"path": s("file path"), "old": s("exact existing text"), "new": s("replacement text"),
                  "replace_all": b("replace every occurrence")}, ["path", "old", "new"]),
             "write", edit_file, lambda a: a.get("path", "")),
        Tool("glob", "Find files by glob pattern (e.g. **/*.py), newest first.",
             obj({"pattern": s("glob pattern"), "path": s("directory to search (default cwd)")}, ["pattern"]),
             "read", glob_, lambda a: a.get("pattern", "")),
        Tool("grep", "Search file contents with ripgrep (regex).",
             obj({"pattern": s("regex"), "path": s("file or directory (default cwd)"),
                  "glob": s("only files matching this glob"), "ignore_case": b("case-insensitive"),
                  "files_only": b("list matching files only"), "context": i("lines of context")}, ["pattern"]),
             "read", grep, lambda a: a.get("pattern", "")),
    ]
