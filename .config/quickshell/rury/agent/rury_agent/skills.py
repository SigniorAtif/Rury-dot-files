"""Skills: folders with a SKILL.md (same frontmatter as Claude Code skills). Only name + description go in the
system prompt; the body loads when the model calls skill(name)."""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from . import paths


@dataclass
class Skill:
    name: str
    description: str
    path: Path

    def body(self) -> str:
        text = self.path.read_text(errors="replace")
        return re.sub(r"\A---\n.*?\n---\n", "", text, flags=re.S).strip()


def _frontmatter(text: str) -> dict[str, str]:
    m = re.match(r"\A---\n(.*?)\n---\n", text, re.S)
    if not m:
        return {}
    out: dict[str, str] = {}
    key = None
    for line in m.group(1).splitlines():
        km = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if km:
            key, val = km.group(1), km.group(2).strip()
            out[key] = "" if val in (">", "|", ">-", "|-") else val.strip("'\"")
        elif key and line.startswith((" ", "\t")):
            out[key] = (out[key] + " " + line.strip()).strip()
    return out


def load(root: Path | None = None) -> list[Skill]:
    root = root or paths.SKILLS
    out = []
    for f in sorted(root.glob("*/SKILL.md")):
        try:
            fm = _frontmatter(f.read_text(errors="replace"))
        except OSError:
            continue
        name = fm.get("name") or f.parent.name
        out.append(Skill(name, fm.get("description", "")[:400], f))
    return out


def index(skills: list[Skill]) -> str:
    if not skills:
        return ""
    return "\n".join(f"- {s.name}: {s.description}" for s in skills)
