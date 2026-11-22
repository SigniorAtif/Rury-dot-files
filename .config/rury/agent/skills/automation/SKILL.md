---
name: automation
description: Set up recurring or one-off scheduled tasks (reminders, checks, cleanups, reports) with the schedule tool.
---

# Automations

`schedule(name, schedule, prompt, mode)` stores a prompt that the agent runs on its own later, in a new
background session. Atif gets a notification with the result and can see the session in the sidebar.

- `schedule`: `every 30m`, `every 6h`, `every 1d`, a cron line (`0 9 * * 1-5` = 9:00 on weekdays), or
  `at 2026-11-23 18:00` (once).
- `prompt`: write it for a reader with no context: what to check or do, where, and what to report. Example:
  "Check ~/Downloads for files older than 30 days and list them with sizes. Don't delete anything."
- `mode`: `auto` (default) still asks before risky steps; `ask` asks before every change.

Prefer read-and-report automations. Anything that deletes or sends needs Atif's approval each run.
Creating an automation always asks Atif first.
