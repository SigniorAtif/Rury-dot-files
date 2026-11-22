"""Scheduled prompts. A schedule is one of:
  every 30m | every 2h | every 1d     an interval
  0 9 * * 1-5                          a cron line (local time)
  at 2026-11-23 09:00                  once
Each run is its own background session; the result arrives as a notification and in the session list.
"""
from __future__ import annotations

import re
import time
from datetime import datetime

from croniter import croniter

UNITS = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800}


def next_run(schedule: str, after: float | None = None) -> float | None:
    after = after if after is not None else time.time()
    sch = schedule.strip()
    m = re.fullmatch(r"every\s+(\d+)\s*([smhdw])\w*", sch, re.I)
    if m:
        step = int(m.group(1)) * UNITS[m.group(2).lower()]
        if step < 60:
            raise ValueError("the shortest interval is 1 minute")
        return after + step
    m = re.fullmatch(r"at\s+(.+)", sch, re.I)
    if m:
        t = datetime.fromisoformat(m.group(1).strip()).timestamp()
        return t if t > after else None
    if croniter.is_valid(sch):
        return croniter(sch, datetime.fromtimestamp(after)).get_next(float)
    raise ValueError(f"can't read schedule {schedule!r}: use 'every 30m', a cron line, or 'at YYYY-MM-DD HH:MM'")


def describe(schedule: str) -> str:
    n = next_run(schedule)
    return f"next run {datetime.fromtimestamp(n):%a %d %b %H:%M}" if n else "no future run"
