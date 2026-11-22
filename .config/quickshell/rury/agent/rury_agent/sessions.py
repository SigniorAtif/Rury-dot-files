"""Sessions and their transcript items, plus automations, in one SQLite file.

A transcript is a list of items, each one of:
  user       {text, images: [paths]}
  assistant  {text, thinking, calls: [{id, name, args}], raw, model, usage}
  tool       {call_id, name, args, summary, status, output, meta, images: [paths]}
  summary    {text}            (a compaction: the model sees this instead of everything before it)
  notice     {text, level}     (UI only)
"""
from __future__ import annotations

import base64
import json
import os
import shutil
import sqlite3
import time
import uuid
from pathlib import Path

from . import paths

SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY, title TEXT NOT NULL DEFAULT '', created REAL, updated REAL,
    mode TEXT, model TEXT, cwd TEXT, kind TEXT NOT NULL DEFAULT 'chat', think INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS items (
    id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL, type TEXT NOT NULL,
    data TEXT NOT NULL, created REAL
);
CREATE INDEX IF NOT EXISTS items_session ON items(session_id, id);
CREATE TABLE IF NOT EXISTS automations (
    id TEXT PRIMARY KEY, name TEXT, schedule TEXT, prompt TEXT, mode TEXT, model TEXT,
    enabled INTEGER NOT NULL DEFAULT 1, last_run REAL, next_run REAL, last_session TEXT, created REAL
);
"""


class Store:
    def __init__(self, path: Path | None = None):
        self.path = path or paths.SESSIONS_DB
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(self.path, check_same_thread=False, isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript(SCHEMA)
        self.images = self.path.parent / "images"

    # ---- sessions ----
    def create(self, *, mode: str, model: str, cwd: str, kind: str = "chat", title: str = "") -> dict:
        sid = uuid.uuid4().hex[:12]
        now = time.time()
        self.db.execute("INSERT INTO sessions (id, title, created, updated, mode, model, cwd, kind) "
                        "VALUES (?,?,?,?,?,?,?,?)", (sid, title, now, now, mode, model, cwd, kind))
        return self.get(sid)

    def get(self, sid: str) -> dict | None:
        r = self.db.execute("SELECT * FROM sessions WHERE id=?", (sid,)).fetchone()
        return dict(r) if r else None

    def update(self, sid: str, **fields) -> None:
        if not fields:
            return
        fields["updated"] = time.time()
        cols = ", ".join(f"{k}=?" for k in fields)
        self.db.execute(f"UPDATE sessions SET {cols} WHERE id=?", (*fields.values(), sid))

    def list(self, limit: int = 50, kind: str | None = None) -> list[dict]:
        q = "SELECT s.*, (SELECT COUNT(*) FROM items i WHERE i.session_id=s.id AND i.type='user') AS turns " \
            "FROM sessions s WHERE archived=0"
        args: list = []
        if kind:
            q += " AND kind=?"
            args.append(kind)
        q += " ORDER BY updated DESC LIMIT ?"
        args.append(limit)
        return [dict(r) for r in self.db.execute(q, args)]

    def archive(self, sid: str) -> None:
        self.db.execute("UPDATE sessions SET archived=1 WHERE id=?", (sid,))

    # ---- items ----
    def add(self, sid: str, type_: str, data: dict) -> int:
        cur = self.db.execute("INSERT INTO items (session_id, type, data, created) VALUES (?,?,?,?)",
                              (sid, type_, json.dumps(data), time.time()))
        self.db.execute("UPDATE sessions SET updated=? WHERE id=?", (time.time(), sid))
        return cur.lastrowid

    def set(self, item_id: int, data: dict) -> None:
        self.db.execute("UPDATE items SET data=? WHERE id=?", (json.dumps(data), item_id))

    def items(self, sid: str) -> list[dict]:
        return [{"id": r["id"], "type": r["type"], **json.loads(r["data"])}
                for r in self.db.execute("SELECT * FROM items WHERE session_id=? ORDER BY id", (sid,))]

    # ---- images (kept as files; the transcript stores paths) ----
    def save_image(self, data_url: str) -> str:
        self.images.mkdir(parents=True, exist_ok=True)
        head, _, b64 = data_url.partition(",")
        ext = "png" if "png" in head else "jpg"
        p = self.images / f"{uuid.uuid4().hex[:16]}.{ext}"
        p.write_bytes(base64.b64decode(b64))
        return str(p)

    def keep_image(self, path: str) -> str:
        """Copy a pasted image (often in a temp dir that gets wiped) next to the session images."""
        src = Path(os.path.expanduser(path))
        if not src.is_file():
            return path
        self.images.mkdir(parents=True, exist_ok=True)
        ext = src.suffix.lower() if src.suffix.lower() in (".png", ".jpg", ".jpeg", ".webp", ".gif") else ".png"
        dst = self.images / f"{uuid.uuid4().hex[:16]}{ext}"
        shutil.copyfile(src, dst)
        return str(dst)

    @staticmethod
    def image_url(path: str) -> str:
        p = Path(path)
        mime = {".png": "image/png", ".webp": "image/webp", ".gif": "image/gif"}.get(p.suffix.lower(), "image/jpeg")
        return f"data:{mime};base64," + base64.b64encode(p.read_bytes()).decode()

    # ---- automations ----
    def automations(self) -> list[dict]:
        return [dict(r) for r in self.db.execute("SELECT * FROM automations ORDER BY created")]

    def add_automation(self, **a) -> dict:
        a.setdefault("id", uuid.uuid4().hex[:8])
        a.setdefault("created", time.time())
        cols = ", ".join(a)
        self.db.execute(f"INSERT INTO automations ({cols}) VALUES ({','.join('?' * len(a))})", tuple(a.values()))
        return dict(self.db.execute("SELECT * FROM automations WHERE id=?", (a["id"],)).fetchone())

    def update_automation(self, aid: str, **fields) -> None:
        cols = ", ".join(f"{k}=?" for k in fields)
        self.db.execute(f"UPDATE automations SET {cols} WHERE id=?", (*fields.values(), aid))

    def delete_automation(self, aid: str) -> None:
        self.db.execute("DELETE FROM automations WHERE id=?", (aid,))
