"""Streaming chat against any OpenAI-compatible endpoint, with two ways to call tools.

native  the endpoint's own `tools` support (llama-server --jinja, Ollama, cloud APIs)
json    the reply is forced into {"thought", "tool", "args", "reply"} by a JSON schema (llama-server turns
        it into a grammar), one tool per turn. Slower to read but small local models rarely get it wrong.

In native mode a model that writes its call as text instead (```json {...}```, <tool_call>{...}</tool_call>)
still gets its call run: `recover_text_calls` picks it out of the content.
"""
from __future__ import annotations

import json
import re
import time
import uuid
from dataclasses import dataclass, field
from typing import Awaitable, Callable

import httpx

Emit = Callable[[str, str], Awaitable[None] | None]  # (kind: "text" | "thinking", chunk)


@dataclass
class ToolCall:
    id: str
    name: str
    args: dict
    raw: str = ""
    error: str = ""            # set when the arguments weren't valid JSON


@dataclass
class Turn:
    text: str = ""
    thinking: str = ""
    calls: list[ToolCall] = field(default_factory=list)
    finish: str = ""
    prompt_tokens: int = 0
    completion_tokens: int = 0
    prompt_ms: float = 0.0
    gen_tps: float = 0.0
    raw: str = ""              # json mode: the whole JSON reply, kept for the transcript


def new_id() -> str:
    return "call_" + uuid.uuid4().hex[:12]


async def _emit(cb: Emit | None, kind: str, chunk: str) -> None:
    if cb and chunk:
        r = cb(kind, chunk)
        if r is not None:
            await r


class ThinkSplitter:
    """Routes <think>...</think> inside streamed content to the thinking channel."""

    def __init__(self):
        self.inside = False
        self.buf = ""

    def feed(self, s: str) -> list[tuple[str, str]]:
        self.buf += s
        out: list[tuple[str, str]] = []
        while self.buf:
            tag = "</think>" if self.inside else "<think>"
            i = self.buf.find(tag)
            if i >= 0:
                if i:
                    out.append(("thinking" if self.inside else "text", self.buf[:i]))
                self.buf = self.buf[i + len(tag):]
                self.inside = not self.inside
                continue
            # keep a possible partial tag at the end for the next chunk
            keep = 0
            for k in range(min(len(tag) - 1, len(self.buf)), 0, -1):
                if tag.startswith(self.buf[-k:]):
                    keep = k
                    break
            emit, self.buf = (self.buf[:-keep], self.buf[-keep:]) if keep else (self.buf, "")
            if emit:
                out.append(("thinking" if self.inside else "text", emit))
            break
        return out


def looping(text: str, window: int = 160, repeats: int = 3) -> bool:
    """True when the end of the text is the same passage over and over (a small model stuck in a loop)."""
    if len(text) < window * (repeats + 1):
        return False
    tail = text[-window:]
    return text.count(tail) >= repeats


class Looping(Exception):
    pass


def _parse_args(s: str) -> tuple[dict, str]:
    s = (s or "").strip()
    if not s:
        return {}, ""
    try:
        v = json.loads(s)
        return (v if isinstance(v, dict) else {"value": v}), ""
    except json.JSONDecodeError as e:
        return {}, f"arguments were not valid JSON ({e.msg})"


_FENCE = re.compile(r"```(?:json|tool_call)?\s*(\{.*?\})\s*```", re.S)
_TAGGED = re.compile(r"<tool_call>\s*(\{.*?\})\s*</tool_call>", re.S)


def recover_text_calls(text: str, names: set[str]) -> tuple[list[ToolCall], str]:
    """Tool calls a model wrote as text. Returns (calls, text with those blocks removed)."""
    calls: list[ToolCall] = []
    spans = []
    for rx in (_TAGGED, _FENCE):
        for m in rx.finditer(text):
            try:
                obj = json.loads(m.group(1))
            except json.JSONDecodeError:
                continue
            if not isinstance(obj, dict):
                continue
            name = obj.get("name") or obj.get("tool") or obj.get("function")
            args = obj.get("arguments", obj.get("args", obj.get("parameters", {})))
            if isinstance(args, str):
                args, _ = _parse_args(args)
            if name in names and isinstance(args, dict):
                calls.append(ToolCall(new_id(), name, args, m.group(1)))
                spans.append(m.span())
        if calls:
            break
    if not calls:
        # a bare JSON object as the whole reply
        t = text.strip()
        if t.startswith("{") and t.endswith("}"):
            try:
                obj = json.loads(t)
                name = obj.get("name") or obj.get("tool")
                args = obj.get("arguments", obj.get("args", {}))
                if name in names and isinstance(args, dict):
                    return [ToolCall(new_id(), name, args, t)], ""
            except (json.JSONDecodeError, AttributeError):
                pass
        return [], text
    for a, b in reversed(spans):
        text = text[:a] + text[b:]
    return calls, text.strip()


# ---- json mode ----------------------------------------------------------------------------------

def json_schema(tool_names: list[str]) -> dict:
    return {
        "type": "object",
        "properties": {
            "thought": {"type": "string"},
            "tool": {"type": "string", "enum": [*tool_names, "none"]},
            "args": {"type": "object"},
            "reply": {"type": "string"},
        },
        "required": ["thought", "tool", "args", "reply"],
    }


def json_tools_prompt(tools: list[dict]) -> str:
    lines = ["# How to act",
             "Answer with ONE JSON object: {\"thought\": short reasoning, \"tool\": a tool name or \"none\", "
             "\"args\": the tool's arguments ({} for none), \"reply\": your message to the user (\"\" while you still "
             "need tools)}. One tool per answer; you get its result back, then answer again. Use tool \"none\" "
             "with a reply when you are done.", "", "# Tools"]
    for t in tools:
        f = t["function"]
        props = f.get("parameters", {}).get("properties", {})
        req = set(f.get("parameters", {}).get("required", []))
        args = ", ".join(f"{k}{'' if k in req else '?'}: {v.get('type', 'any')}" for k, v in props.items())
        lines.append(f"- {f['name']}({args}): {f.get('description', '')}")
    return "\n".join(lines)


class PartialField:
    """Streams the value of one string field out of a JSON object that is still being written."""

    def __init__(self, key: str):
        self.key = key
        self.pos = 0       # how much of the value has been emitted (decoded chars)
        self.done = False

    def take(self, buf: str) -> str:
        if self.done:
            return ""
        m = re.search(r'"%s"\s*:\s*"' % re.escape(self.key), buf)
        if not m:
            return ""
        i, out, esc = m.end(), [], False
        while i < len(buf):
            ch = buf[i]
            if esc:
                if ch == "u":
                    if i + 4 >= len(buf):
                        break
                    try:
                        out.append(chr(int(buf[i + 1:i + 5], 16)))
                    except ValueError:
                        pass
                    i += 5
                    esc = False
                    continue
                out.append({"n": "\n", "t": "\t", "r": "", "b": "", "f": ""}.get(ch, ch))
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                self.done = True
                break
            else:
                out.append(ch)
            i += 1
        s = "".join(out)
        new, self.pos = s[self.pos:], len(s)
        return new


# ---- the request ---------------------------------------------------------------------------------

async def complete(client: httpx.AsyncClient, *, base_url: str, model: str, key: str, messages: list[dict],
                   tools: list[dict] | None, tool_mode: str, emit: Emit | None = None,
                   params: dict | None = None, max_tokens: int = 4096) -> Turn:
    body: dict = {"model": model or "local", "messages": messages, "stream": True,
                  "stream_options": {"include_usage": True}, "max_tokens": max_tokens,
                  "cache_prompt": True}
    body.update(params or {})
    names = [t["function"]["name"] for t in tools or []]
    if tools and tool_mode in ("native", "auto"):
        body["tools"] = tools
    elif tools and tool_mode == "json":
        body["response_format"] = {"type": "json_schema", "json_schema": {"name": "step", "schema": json_schema(names)}}
    headers = {"Content-Type": "application/json"}
    if key:
        headers["Authorization"] = f"Bearer {key}"

    turn = Turn()
    acc: dict[int, dict] = {}
    split = ThinkSplitter()
    jbuf = ""
    jthought, jreply = PartialField("thought"), PartialField("reply")
    first_token = None
    checked = 0

    async with client.stream("POST", base_url.rstrip("/") + "/chat/completions", json=body, headers=headers,
                             timeout=httpx.Timeout(connect=10, read=600, write=60, pool=10)) as r:
        if r.status_code != 200:
            detail = (await r.aread()).decode(errors="replace")[:800]
            raise RuntimeError(f"model endpoint returned {r.status_code}: {detail}")
        async for line in r.aiter_lines():
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                chunk = json.loads(data)
            except json.JSONDecodeError:
                continue
            if chunk.get("error"):
                raise RuntimeError(f"model error: {chunk['error']}")
            if u := chunk.get("usage"):
                turn.prompt_tokens = u.get("prompt_tokens", turn.prompt_tokens)
                turn.completion_tokens = u.get("completion_tokens", turn.completion_tokens)
            if tm := chunk.get("timings"):
                turn.prompt_ms = tm.get("prompt_ms", turn.prompt_ms)
                turn.gen_tps = tm.get("predicted_per_second", turn.gen_tps)
            for ch in chunk.get("choices") or []:
                d = ch.get("delta") or {}
                if ch.get("finish_reason"):
                    turn.finish = ch["finish_reason"]
                if first_token is None and (d.get("content") or d.get("reasoning_content") or d.get("tool_calls")):
                    first_token = time.time()
                if rc := d.get("reasoning_content"):
                    turn.thinking += rc
                    await _emit(emit, "thinking", rc)
                if c := d.get("content"):
                    if tool_mode == "json" and tools:
                        jbuf += c
                        if s := jthought.take(jbuf):
                            turn.thinking += s
                            await _emit(emit, "thinking", s)
                        if s := jreply.take(jbuf):
                            turn.text += s
                            await _emit(emit, "text", s)
                    else:
                        for kind, piece in split.feed(c):
                            if kind == "thinking":
                                turn.thinking += piece
                            else:
                                turn.text += piece
                            await _emit(emit, kind, piece)
                for tc in d.get("tool_calls") or []:
                    slot = acc.setdefault(tc.get("index", len(acc)), {"id": "", "name": "", "args": ""})
                    if tc.get("id"):
                        slot["id"] = tc["id"]
                    f = tc.get("function") or {}
                    if f.get("name"):
                        slot["name"] += f["name"]
                    if f.get("arguments"):
                        slot["args"] += f["arguments"] if isinstance(f["arguments"], str) else json.dumps(f["arguments"])
            # every ~256 new chars, check whether the model is repeating itself; closing the stream stops it
            total = len(turn.text) + len(turn.thinking) + len(jbuf)
            if total - checked >= 256:
                checked = total
                if looping(turn.thinking) or looping(turn.text + jbuf):
                    turn.finish = "loop"
                    break

    if not turn.gen_tps and turn.completion_tokens and first_token:
        turn.gen_tps = turn.completion_tokens / max(time.time() - first_token, 1e-3)

    if tool_mode == "json" and tools:
        turn.raw = jbuf
        try:
            obj = json.loads(jbuf)
        except json.JSONDecodeError:
            obj = None
        if isinstance(obj, dict):
            turn.thinking = obj.get("thought", turn.thinking) or turn.thinking
            turn.text = obj.get("reply", turn.text) or ""
            name = obj.get("tool", "none")
            if name and name != "none":
                args = obj.get("args") if isinstance(obj.get("args"), dict) else {}
                turn.calls.append(ToolCall(new_id(), name, args, json.dumps(args)))
        else:
            turn.text = turn.text or jbuf
        return turn

    for i in sorted(acc):
        slot = acc[i]
        args, err = _parse_args(slot["args"])
        turn.calls.append(ToolCall(slot["id"] or new_id(), slot["name"], args, slot["args"], err))
    if not turn.calls and tools and tool_mode in ("native", "auto"):
        calls, rest = recover_text_calls(turn.text, set(names))
        if calls:
            turn.calls, turn.text = calls, rest
    return turn
