"""The agent loop for one session: model -> tool calls -> permission gate -> run -> results -> model, until the
model answers without calling a tool. Streams everything it does as events."""
from __future__ import annotations

import asyncio
import json
import os
import time
import uuid

from . import llm, paths, prompt
from .permissions import Gate, load_rules, save_allow_rule
from .tools import Ctx, Result, Tool

MAX_TOOL_CHARS_FALLBACK = 6000


def to_messages(items: list[dict], tool_mode: str, vision: bool, image_url) -> list[dict]:
    """Transcript items -> chat messages. Starts at the last summary."""
    start = max((k for k, it in enumerate(items) if it["type"] == "summary"), default=-1)
    msgs: list[dict] = []
    if start >= 0:
        msgs.append({"role": "user", "content": "Summary of our conversation so far (older turns were compacted):\n"
                                                + items[start]["text"]})
        msgs.append({"role": "assistant", "content": "Understood. Continuing from there."})
    pending_images: list[str] = []

    def flush_images():
        if pending_images and vision:
            parts = [{"type": "text", "text": "[images returned by the tools above]"}]
            parts += [{"type": "image_url", "image_url": {"url": image_url(p)}} for p in pending_images
                      if os.path.exists(p)]
            msgs.append({"role": "user", "content": parts})
        pending_images.clear()

    for it in items[start + 1:]:
        t = it["type"]
        if t == "user":
            flush_images()
            imgs = [p for p in it.get("images", []) if os.path.exists(p)] if vision else []
            if imgs:
                parts = [{"type": "text", "text": it.get("text", "")}]
                parts += [{"type": "image_url", "image_url": {"url": image_url(p)}} for p in imgs]
                msgs.append({"role": "user", "content": parts})
            else:
                msgs.append({"role": "user", "content": it.get("text", "")})
        elif t == "assistant":
            flush_images()
            if tool_mode == "json" and it.get("raw"):
                msgs.append({"role": "assistant", "content": it["raw"]})
                continue
            m: dict = {"role": "assistant", "content": it.get("text") or ""}
            calls = it.get("calls") or []
            if calls and tool_mode != "json":
                m["tool_calls"] = [{"id": c["id"], "type": "function",
                                    "function": {"name": c["name"], "arguments": json.dumps(c.get("args", {}))}}
                                   for c in calls]
            if m["content"] or calls:
                msgs.append(m)
        elif t == "tool":
            out = it.get("output", "")
            if tool_mode == "json":
                msgs.append({"role": "user", "content": f"Result of {it['name']}:\n{out}"})
            else:
                msgs.append({"role": "tool", "tool_call_id": it["call_id"], "content": out})
            pending_images.extend(it.get("images", []))
    flush_images()
    if tool_mode == "json":
        msgs = _merge_same_role(msgs)
    return msgs


def _merge_same_role(msgs: list[dict]) -> list[dict]:
    out: list[dict] = []
    for m in msgs:
        if out and out[-1]["role"] == m["role"] == "user":
            a, b = out[-1]["content"], m["content"]
            if isinstance(a, str) and isinstance(b, str):
                out[-1]["content"] = a + "\n\n" + b
            else:
                pa = a if isinstance(a, list) else [{"type": "text", "text": a}]
                pb = b if isinstance(b, list) else [{"type": "text", "text": b}]
                out[-1]["content"] = pa + pb
        else:
            out.append(dict(m))
    return out


class Stopped(Exception):
    pass


class Agent:
    def __init__(self, services, session: dict):
        self.sv = services
        self.sid = session["id"]
        self.task: asyncio.Task | None = None
        self.queue: list[tuple[str, list[str]]] = []
        self.pending: dict[str, asyncio.Future] = {}
        self.pending_info: dict[str, dict] = {}
        self.session_allow: list[str] = []
        self.status = "idle"
        self.status_detail = ""
        self.started = 0.0
        self.bad_calls = 0
        self.tool_mode_override = ""
        self.ctx = Ctx(session_id=self.sid, cwd=session.get("cwd") or str(paths.HOME), mode=session["mode"],
                       emit=self._emit_ctx, ask_user=self._ask_user, services=services)

    # ---- session fields ----
    @property
    def session(self) -> dict:
        return self.sv.store.get(self.sid)

    @property
    def mode(self) -> str:
        return self.session["mode"]

    async def set_mode(self, mode: str) -> None:
        if mode not in ("chat", "plan", "ask", "auto"):
            raise ValueError(f"unknown mode {mode}")
        self.sv.store.update(self.sid, mode=mode)
        self.ctx.mode = mode
        await self.emit("session", {"session": self.public()})

    def public(self) -> dict:
        s = self.session
        return {**s, "status": self.status, "detail": self.status_detail, "running": self.running,
                "queued": len(self.queue), "cwd_now": self.ctx.cwd, "todos": self.ctx.state.get("todos", []),
                "pending": list(self.pending_info.values())}

    @property
    def running(self) -> bool:
        return bool(self.task and not self.task.done())

    # ---- events ----
    async def emit(self, ev: str, payload: dict | None = None) -> None:
        await self.sv.broadcast({"ev": ev, "sid": self.sid, **(payload or {})})

    async def _emit_ctx(self, ev: str, payload: dict) -> None:
        await self.emit(ev, payload)

    async def set_status(self, state: str, detail: str = "") -> None:
        self.status, self.status_detail = state, detail
        await self.emit("status", {"state": state, "detail": detail, "since": self.started})

    async def add_item(self, type_: str, data: dict) -> dict:
        iid = self.sv.store.add(self.sid, type_, data)
        item = {"id": iid, "type": type_, **data}
        await self.emit("item", {"item": item})
        return item

    async def update_item(self, item: dict) -> None:
        data = {k: v for k, v in item.items() if k not in ("id", "type")}
        self.sv.store.set(item["id"], data)
        await self.emit("item_update", {"item": item})

    # ---- input ----
    async def send(self, text: str, images: list[str] | None = None) -> None:
        images = images or []
        if self.running:
            self.queue.append((text, images))
            await self.emit("queued", {"count": len(self.queue)})
            return
        self.task = asyncio.create_task(self._run(text, images))

    async def stop(self) -> None:
        self.queue.clear()
        for rid, fut in list(self.pending.items()):
            if not fut.done():
                fut.cancel()
        for p in list(self.ctx.procs):
            from .tools import kill_group
            kill_group(p)
        if self.running:
            self.task.cancel()
            try:
                await self.task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass

    def answer(self, rid: str, answer: dict) -> bool:
        fut = self.pending.get(rid)
        if fut and not fut.done():
            fut.set_result(answer)
            return True
        return False

    async def _wait(self, kind: str, payload: dict) -> dict:
        rid = uuid.uuid4().hex[:10]
        fut = asyncio.get_running_loop().create_future()
        self.pending[rid] = fut
        info = {"rid": rid, "kind": kind, **payload}
        self.pending_info[rid] = info
        prev = self.status
        await self.set_status("waiting", kind)
        await self.emit(kind, info)
        self.sv.maybe_notify(self, info)
        try:
            return await fut
        finally:
            self.pending.pop(rid, None)
            self.pending_info.pop(rid, None)
            await self.emit("resolved", {"rid": rid})
            await self.set_status(prev if prev != "waiting" else "working")

    async def _ask_user(self, question: str, options: list[str]) -> str:
        ans = await self._wait("question", {"question": question, "options": options})
        return str(ans.get("answer", ""))

    # ---- tools for this step ----
    def toolset(self, spec) -> list[Tool]:
        mode = self.mode
        if mode == "chat":
            return []
        out = []
        for t in self.sv.core_tools:
            if mode not in t.modes:
                continue
            if mode == "plan" and t.kind not in ("read", "meta", "exec"):
                continue
            if not spec.vision and t.name in ("desk_screenshot", "desk_zoom"):
                continue
            out.append(t)
        for full in self.ctx.state.get("loaded_tools", []):
            mt = self.sv.mcp.find(full)
            if mt:
                out.append(self.sv.mcp_tool(mt))
        return out

    # ---- the loop ----
    async def _run(self, text: str, images: list[str]) -> None:
        self.started = time.time()
        try:
            await self.sv.refresh_session_env()
            await self._turn(text, images)
            while self.queue:
                t, im = self.queue.pop(0)
                await self._turn(t, im)
        except asyncio.CancelledError:
            await self.add_item("notice", {"text": "Stopped.", "level": "info"})
        except Exception as e:  # noqa: BLE001 - surfaced to the UI, the daemon keeps running
            await self.add_item("notice", {"text": f"{type(e).__name__}: {e}", "level": "error"})
            await self.emit("error", {"text": str(e)})
        finally:
            await self.set_status("idle")
            await self.emit("done", {"elapsed": time.time() - self.started})
            self.sv.store.update(self.sid)

    async def _turn(self, text: str, images: list[str]) -> None:
        s = self.session
        if not s["title"]:
            self.sv.store.update(self.sid, title=text.strip().split("\n")[0][:70] or "New session")
            await self.emit("session", {"session": self.public()})
        await self.add_item("user", {"text": text, "images": images})
        steps = 0
        while True:
            steps += 1
            if steps > self.sv.settings.max_steps:
                await self.add_item("notice", {"text": f"Stopped after {steps - 1} steps (max_steps).",
                                               "level": "warn"})
                return
            # messages typed while the model was working join the conversation at the next step
            if steps > 1 and self.queue:
                t, im = self.queue.pop(0)
                await self.add_item("user", {"text": t, "images": im})
                await self.emit("queued", {"count": len(self.queue)})
            calls = await self._step()
            if not calls:
                return

    async def _step(self) -> list:
        spec = self.sv.registry.get(self.session["model"])
        self.ctx.vision = spec.vision
        base_url = await self.sv.endpoint(spec, self)
        tools = self.toolset(spec)
        tool_mode = self.tool_mode_override or spec.tools
        if tool_mode == "auto":
            tool_mode = "native"
        schemas = [t.schema() for t in tools]
        sysprompt = prompt.build(
            mode=self.mode, cwd=self.session["cwd"], skills_index=self.sv.skills_index(),
            mcp_names=[t.full for t in self.sv.mcp.all_tools()] if tools else [],
            tool_prompt=llm.json_tools_prompt(schemas) if tool_mode == "json" and tools else "")
        items = self.sv.store.items(self.sid)
        msgs = [{"role": "system", "content": sysprompt}] + to_messages(items, tool_mode, spec.vision,
                                                                         self.sv.store.image_url)
        params = dict(spec.params)
        if spec.kind == "llama.cpp":
            params.setdefault("chat_template_kwargs", {})["enable_thinking"] = bool(self.session["think"])
            # No DRY sampling here: it penalises re-typing anything already in context, which mangles the paths
            # and commands an agent has to copy exactly. Runaway repetition is caught by llm.looping() instead.

        item = await self.add_item("assistant", {"text": "", "thinking": "", "calls": [], "model": spec.id})
        await self.set_status("thinking", spec.name)

        async def on_delta(kind: str, chunk: str):
            await self.emit("delta", {"item_id": item["id"], "kind": kind, "text": chunk})

        async with self.sv.llm_lock(base_url):
            self.sv.touch_model(spec)
            turn = await llm.complete(self.sv.http, base_url=base_url, model=spec.model or spec.id,
                                      key=self.sv.key_for(spec), messages=msgs,
                                      tools=schemas or None, tool_mode=tool_mode, emit=on_delta, params=params,
                                      max_tokens=self.sv.settings.max_tokens)
            self.sv.touch_model(spec)
        item.update(text=turn.text, thinking=turn.thinking, raw=turn.raw,
                    calls=[{"id": c.id, "name": c.name, "args": c.args} for c in turn.calls],
                    usage={"prompt": turn.prompt_tokens, "completion": turn.completion_tokens,
                           "tps": round(turn.gen_tps, 1), "prompt_ms": round(turn.prompt_ms)})
        await self.update_item(item)
        await self.emit("usage", {"prompt_tokens": turn.prompt_tokens, "completion_tokens": turn.completion_tokens,
                                  "ctx": spec.ctx, "tps": round(turn.gen_tps, 1),
                                  "elapsed": round(time.time() - self.started, 1)})

        if turn.finish == "loop":
            await self.add_item("notice", {"text": "The model got stuck repeating itself, so I cut it off. "
                                                   "Try again, rephrase, or turn thinking off/on.", "level": "warn"})
            return []
        if turn.finish == "length" and not turn.calls:
            await self.add_item("notice", {"text": "The reply hit the token limit.", "level": "warn"})

        for call in turn.calls:
            await self._run_call(call, tools)

        if turn.prompt_tokens and turn.prompt_tokens > spec.ctx * self.sv.settings.compact_at and turn.calls:
            await self.compact(spec, base_url)
        return turn.calls

    async def _run_call(self, call: llm.ToolCall, tools: list[Tool]) -> None:
        tool = next((t for t in tools if t.name == call.name), None)
        base = {"call_id": call.id, "name": call.name, "args": call.args, "summary": "", "status": "running",
                "output": "", "meta": {}, "images": []}
        if tool:
            base["summary"] = tool.describe(call.args)
            base["kind"] = tool.kind
        item = await self.add_item("tool", base)

        async def finish(status: str, output: str, meta: dict | None = None, images: list[str] | None = None):
            item.update(status=status, output=output, meta=meta or {}, images=images or [])
            await self.update_item(item)

        if not tool:
            names = ", ".join(t.name for t in tools)
            return await finish("error", f"unknown tool {call.name!r}. Available: {names}")
        if call.error:
            self.bad_calls += 1
            if self.bad_calls >= 2 and not self.tool_mode_override and self.sv.registry.get(
                    self.session["model"]).tools == "auto":
                self.tool_mode_override = "json"
                await self.add_item("notice", {"text": "The model keeps writing broken tool calls; switching it "
                                                       "to structured (JSON) tool calls for this session.",
                                               "level": "info"})
            return await finish("error", f"{call.error}. Send the arguments as one JSON object.")

        if call.name == "exit_plan":
            return await self._exit_plan(call, finish)

        allow, deny = load_rules()
        gate = Gate(mode=self.mode, cwd=self.ctx.cwd, allow=allow, deny=deny, session_allow=self.session_allow,
                    desk_servers=self.sv.settings.desk_mcp_servers)
        v = gate.check(call.name, tool.kind, call.args)
        if v.action == "deny":
            msg = f"refused: {v.reason}."
            if v.handoff:
                msg += f" Tell Atif to run it himself: `{v.handoff}`"
            return await finish("denied", msg, {"reason": v.reason, "handoff": v.handoff})
        if v.action == "block":
            return await finish("blocked", f"not run: {v.reason}")
        if v.action == "ask":
            ans = await self._wait("approval", {"call_id": call.id, "item_id": item["id"], "tool": call.name,
                                                "summary": base["summary"], "args": call.args, "risky": v.risky,
                                                "reason": v.reason, "rule": v.rule})
            decision = ans.get("decision", "deny")
            if decision == "session" and v.rule:
                self.session_allow.append(v.rule)
            elif decision == "save" and v.rule:
                save_allow_rule(v.rule)
            if decision not in ("allow", "session", "save"):
                note = str(ans.get("note", "")).strip()
                return await finish("denied", "Atif denied this." + (f" He said: {note}" if note else
                                                                   " Don't retry it; adjust or ask him."))
        item["status"] = "running"
        await self.set_status("tool", f"{call.name} {base['summary']}"[:120])
        try:
            res: Result = await tool.run(call.args, self.ctx)
        except asyncio.CancelledError:
            await finish("cancelled", "stopped by Atif")
            raise
        except Exception as e:  # noqa: BLE001 - a tool error goes back to the model
            res = Result(f"error: {type(e).__name__}: {e}", ok=False)
        limit = self.sv.settings.tool_output_chars or MAX_TOOL_CHARS_FALLBACK
        out = res.text if len(res.text) <= limit * 2 else res.text[:limit * 2] + "\n[cut]"
        imgs = [self.sv.store.save_image(u) for u in res.images]
        await finish("ok" if res.ok else "error", out, res.meta, imgs)
        await self.set_status("thinking")

    async def _exit_plan(self, call: llm.ToolCall, finish) -> None:
        if self.mode != "plan":
            return await finish("error", "exit_plan is only for plan mode")
        plan = str(call.args.get("plan", ""))
        ans = await self._wait("plan", {"call_id": call.id, "plan": plan})
        decision = ans.get("decision", "keep")
        if decision in ("auto", "ask"):
            await self.set_mode(decision)
            await finish("ok", f"Atif approved the plan. You are now in {decision.upper()} mode: carry it out step "
                               "by step, keeping the todo list current.", {"plan": plan, "approved": decision})
        else:
            note = str(ans.get("note", "")).strip()
            await finish("ok", "Atif wants changes to the plan" + (f": {note}" if note else ".") +
                         " Stay in plan mode and call exit_plan again with the revised plan.",
                         {"plan": plan, "approved": ""})

    async def compact(self, spec=None, base_url: str = "") -> None:
        spec = spec or self.sv.registry.get(self.session["model"])
        base_url = base_url or await self.sv.endpoint(spec, self)
        await self.set_status("thinking", "compacting the conversation")
        items = self.sv.store.items(self.sid)
        msgs = to_messages(items, "json", False, self.sv.store.image_url)
        msgs.append({"role": "user", "content": (
            "Summarize this conversation so the work can continue from the summary alone: Atif's requests, "
            "decisions, what was done (files, commands), what was found, the current state, and the next steps. "
            "Be specific (paths, names, numbers). Plain text, under 400 words.")})
        async with self.sv.llm_lock(base_url):
            turn = await llm.complete(self.sv.http, base_url=base_url, model=spec.model or spec.id,
                                      key=self.sv.key_for(spec),
                                      messages=[{"role": "system", "content": "You write handover summaries."}]
                                      + msgs, tools=None, tool_mode="native", params=dict(spec.params),
                                      max_tokens=900)
        await self.add_item("summary", {"text": turn.text.strip()})
        await self.add_item("notice", {"text": "Compacted the conversation to save context.", "level": "info"})
