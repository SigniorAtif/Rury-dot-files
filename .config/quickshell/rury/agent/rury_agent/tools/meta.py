"""Tools about the work itself: todo list, asking Atif, plans, skills, MCP tool search, memory, schedules."""
from __future__ import annotations

import re
import time

from .. import automations, paths
from . import Ctx, Result, Tool, obj, run_proc, s


async def todo_write(args: dict, ctx: Ctx) -> Result:
    todos = []
    for t in args.get("todos") or []:
        if isinstance(t, dict) and t.get("content"):
            st = t.get("status", "pending")
            todos.append({"content": str(t["content"])[:200],
                          "status": st if st in ("pending", "in_progress", "completed") else "pending"})
    ctx.state["todos"] = todos
    await ctx.emit("todo", {"todos": todos})
    done = sum(t["status"] == "completed" for t in todos)
    return Result(f"todo list saved ({done}/{len(todos)} done)", meta={"todos": todos})


async def ask_user(args: dict, ctx: Ctx) -> Result:
    q = str(args.get("question", "")).strip()
    opts = [str(o) for o in (args.get("options") or []) if str(o).strip()][:6]
    answer = await ctx.ask_user(q, opts)
    return Result(f"Atif answered: {answer}" if answer else "Atif dismissed the question without answering")


async def exit_plan(args: dict, ctx: Ctx) -> Result:
    # the loop intercepts this call: it shows the plan card and switches mode on approval
    return Result("plan submitted")


async def skill(args: dict, ctx: Ctx) -> Result:
    name = str(args.get("name", "")).strip()
    sk = next((k for k in ctx.services.skills() if k.name == name), None)
    if not sk:
        names = ", ".join(k.name for k in ctx.services.skills()) or "none"
        return Result(f"no skill named {name!r}; available: {names}", ok=False)
    return Result(f"# skill: {sk.name}\n(base folder: {sk.path.parent})\n\n{sk.body()}")


async def tool_search(args: dict, ctx: Ctx) -> Result:
    hub = ctx.services.mcp
    await hub.ensure_listed()
    q = str(args.get("query", "")).strip()
    found = hub.search(q)
    if not found:
        names = ", ".join(t.full for t in hub.all_tools()[:40]) or "no MCP tools configured"
        return Result(f"nothing matched {q!r}. Known tools: {names}", ok=False)
    loaded = ctx.state.setdefault("loaded_tools", [])
    for t in found:
        if t.full not in loaded:
            loaded.append(t.full)
    lines = [f"- {t.full}: {t.description[:200]}" for t in found]
    servers = {t.server for t in found}
    rest = [t.full for t in hub.all_tools() if t.server in servers and t.full not in loaded]
    more = ("\nNot loaded yet (tool_search with an exact name, or a word like 'drag', loads more): " +
            ", ".join(rest)) if rest else ""
    return Result("loaded these tools; you can call them now:\n" + "\n".join(lines) + more)


async def remember(args: dict, ctx: Ctx) -> Result:
    name = re.sub(r"[^a-z0-9-]+", "-", str(args.get("name", "")).lower()).strip("-")[:60]
    if not name:
        return Result("name is required", ok=False)
    content = str(args.get("content", "")).strip()
    paths.MEMORY.mkdir(parents=True, exist_ok=True)
    f = paths.MEMORY / f"{name}.md"
    desc = str(args.get("description", "")).strip() or content.split("\n")[0][:100]
    f.write_text(f"---\nname: {name}\ndescription: {desc}\n---\n\n{content}\n")
    idx = paths.MEMORY / "MEMORY.md"
    lines = idx.read_text().splitlines() if idx.exists() else []
    lines = [ln for ln in lines if f"({name}.md)" not in ln] + [f"- [{name}]({name}.md) — {desc}"]
    idx.write_text("\n".join(lines) + "\n")
    return Result(f"remembered {name}")


async def schedule(args: dict, ctx: Ctx) -> Result:
    sched = str(args.get("schedule", "")).strip()
    try:
        nxt = automations.next_run(sched)
    except ValueError as e:
        return Result(str(e), ok=False)
    mode = args.get("mode") or "auto"
    a = ctx.services.store.add_automation(name=str(args.get("name", "automation"))[:80], schedule=sched,
                                          prompt=str(args.get("prompt", "")), mode=mode,
                                          model=ctx.services.current_model_id(ctx.session_id), enabled=1,
                                          next_run=nxt)
    await ctx.emit("automations", {"automations": ctx.services.store.automations()})
    return Result(f"scheduled {a['name']} ({sched}); {automations.describe(sched)}; id {a['id']}")


async def notify(args: dict, ctx: Ctx) -> Result:
    code, out = await run_proc(["notify-send", "-a", "SigniorAtif Agent", "-i", "smart_toy",
                                str(args.get("title", "Agent")), str(args.get("body", ""))], ctx, timeout=10)
    return Result("notified" if code == 0 else out.strip(), ok=code == 0)


TODO_SCHEMA = {"type": "array", "items": obj({"content": s("the step"),
                                               "status": s("pending, in_progress or completed")},
                                              ["content", "status"])}


def tools() -> list[Tool]:
    return [
        Tool("todo_write", "Keep a short checklist for multi-step work (Atif sees it live). Send the whole list "
             "each time; one item in_progress at a time.",
             obj({"todos": TODO_SCHEMA}, ["todos"]), "meta", todo_write,
             lambda a: f"{sum(t.get('status') == 'completed' for t in a.get('todos', []))}/{len(a.get('todos', []))}"),
        Tool("ask_user", "Ask Atif a question and wait for the answer. Use before anything irreversible outside "
             "this computer (buying, sending, posting) and when the request is ambiguous.",
             obj({"question": s("the question"), "options": {"type": "array", "items": {"type": "string"},
                                                              "description": "suggested answers"}}, ["question"]),
             "meta", ask_user, lambda a: a.get("question", "")[:100]),
        Tool("exit_plan", "Plan mode only: present the finished plan for Atif to approve.",
             obj({"plan": s("the plan, in markdown")}, ["plan"]), "meta", exit_plan, lambda a: "plan",
             modes=("plan",)),
        Tool("skill", "Load a skill's instructions by name (see the skill list).",
             obj({"name": s("skill name")}, ["name"]), "meta", skill, lambda a: a.get("name", "")),
        Tool("tool_search", "Load extra tools (MCP servers, e.g. the browser) by keyword or exact name, so you "
             "can call them.", obj({"query": s("keywords or an exact mcp__server__tool name")}, ["query"]),
             "meta", tool_search, lambda a: a.get("query", "")),
        Tool("remember", "Save a fact for future sessions (Atif's preferences, project facts). One fact per name.",
             obj({"name": s("short-kebab-name"), "content": s("the fact"),
                  "description": s("one-line summary")}, ["name", "content"]), "meta", remember,
             lambda a: a.get("name", "")),
        Tool("schedule", "Create an automation: a prompt that runs on a schedule ('every 30m', a cron line, or "
             "'at 2026-11-23 09:00'). Always asks Atif.",
             obj({"name": s("short name"), "schedule": s("when"), "prompt": s("what to do each time"),
                  "mode": s("auto or ask (default auto)")}, ["name", "schedule", "prompt"]),
             "risky", schedule, lambda a: f"{a.get('name', '')} · {a.get('schedule', '')}"),
        Tool("notify", "Show Atif a desktop notification.",
             obj({"title": s("title"), "body": s("text")}, ["title"]), "meta", notify, lambda a: a.get("title", "")),
    ]
