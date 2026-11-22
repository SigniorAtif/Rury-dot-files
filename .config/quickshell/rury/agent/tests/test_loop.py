"""The loop end to end against a scripted fake model (httpx MockTransport serving SSE)."""
import asyncio
import json

import httpx
import pytest

from rury_agent import paths
from rury_agent.models import ModelSpec
from rury_agent.services import Services


def sse(chunks: list[dict]) -> bytes:
    return b"".join(b"data: " + json.dumps(c).encode() + b"\n\n" for c in chunks) + b"data: [DONE]\n\n"


def text_reply(text: str) -> list[dict]:
    return [{"choices": [{"delta": {"content": text}}]},
            {"choices": [{"delta": {}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 50, "completion_tokens": 5}}]


def tool_reply(name: str, args: dict) -> list[dict]:
    return [{"choices": [{"delta": {"tool_calls": [{"index": 0, "id": "c1",
                                                     "function": {"name": name, "arguments": json.dumps(args)}}]}}]},
            {"choices": [{"delta": {}, "finish_reason": "tool_calls"}], "usage": {"prompt_tokens": 60,
                                                                                    "completion_tokens": 9}}]


class Script:
    def __init__(self, replies):
        self.replies = list(replies)
        self.requests = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(json.loads(request.content))
        body = sse(self.replies.pop(0)) if self.replies else sse(text_reply("(out of script)"))
        return httpx.Response(200, content=body, headers={"content-type": "text/event-stream"})


async def make(script, mode="auto"):
    sv = Services()
    sv.http = httpx.AsyncClient(transport=httpx.MockTransport(script))
    sv.registry.models = {"fake": ModelSpec(id="fake", name="Fake", base_url="http://fake/v1", model="fake",
                                            tools="native", ctx=1000)}
    sv.registry.default = "fake"
    agent = sv.new_session(mode=mode, model="fake", cwd=str(paths.SCRATCH))
    q = sv.subscribe()
    return sv, agent, q


async def drain(q, until="done", answer=None, agent=None, timeout=10):
    evs = []
    async def go():
        while True:
            ev = await q.get()
            evs.append(ev)
            if answer and ev["ev"] in ("approval", "question", "plan"):
                agent.answer(ev["rid"], answer(ev))
            if ev["ev"] == until:
                return
    await asyncio.wait_for(go(), timeout)
    return evs


async def test_tool_then_answer():
    target = paths.SCRATCH / "hello.txt"
    script = Script([tool_reply("write_file", {"path": str(target), "content": "hi"}), text_reply("Done.")])
    sv, agent, q = await make(script)
    await agent.send("make a file")
    await drain(q)
    assert target.read_text() == "hi"
    items = sv.store.items(agent.sid)
    assert [i["type"] for i in items] == ["user", "assistant", "tool", "assistant"]
    assert items[2]["status"] == "ok" and items[3]["text"] == "Done."
    # the second request carried the tool result back to the model
    second = script.requests[1]["messages"]
    assert second[-1]["role"] == "tool" and "created" in second[-1]["content"]
    await sv.close()


async def test_risky_waits_for_approval_and_deny_reaches_model():
    script = Script([tool_reply("bash", {"command": "rm ~/precious.txt"}), text_reply("Okay, I won't.")])
    sv, agent, q = await make(script, mode="auto")
    await agent.send("delete it")
    evs = await drain(q, answer=lambda ev: {"decision": "deny", "note": "keep it"}, agent=agent)
    appr = next(e for e in evs if e["ev"] == "approval")
    assert appr["risky"] and "deletes" in appr["reason"]
    tool = [i for i in sv.store.items(agent.sid) if i["type"] == "tool"][0]
    assert tool["status"] == "denied" and "keep it" in tool["output"]
    await sv.close()


async def test_sudo_refused_with_handoff():
    script = Script([tool_reply("bash", {"command": "sudo pacman -Syu"}), text_reply("Run it yourself.")])
    sv, agent, q = await make(script, mode="auto")
    await agent.send("update")
    evs = await drain(q)
    assert not any(e["ev"] == "approval" for e in evs)
    tool = [i for i in sv.store.items(agent.sid) if i["type"] == "tool"][0]
    assert tool["status"] == "denied" and "`sudo pacman -Syu`" in tool["output"]
    await sv.close()


async def test_plan_mode_then_approve_switches_to_auto():
    target = paths.SCRATCH / "after-plan.txt"
    script = Script([tool_reply("write_file", {"path": str(target), "content": "x"}),
                     tool_reply("exit_plan", {"plan": "1. write the file"}),
                     tool_reply("write_file", {"path": str(target), "content": "x"}),
                     text_reply("Written.")])
    sv, agent, q = await make(script, mode="plan")
    await agent.send("write a file")
    await drain(q, answer=lambda ev: {"decision": "auto"}, agent=agent)
    tools = [i for i in sv.store.items(agent.sid) if i["type"] == "tool"]
    assert tools[0]["status"] == "unknown" or tools[0]["status"] == "error"   # write_file isn't offered in plan
    assert tools[1]["name"] == "exit_plan" and tools[1]["meta"]["approved"] == "auto"
    assert tools[2]["status"] == "ok" and target.exists()
    assert sv.store.get(agent.sid)["mode"] == "auto"
    # plan mode offered no write tools to the model
    offered = {t["function"]["name"] for t in script.requests[0]["tools"]}
    assert "write_file" not in offered and "exit_plan" in offered and "read_file" in offered
    await sv.close()


async def test_chat_mode_sends_no_tools():
    script = Script([text_reply("Hello!")])
    sv, agent, q = await make(script, mode="chat")
    await agent.send("hi")
    await drain(q)
    assert "tools" not in script.requests[0]
    await sv.close()


async def test_stop_cancels_a_running_command():
    script = Script([tool_reply("bash", {"command": "sleep 30"}), text_reply("never")])
    sv, agent, q = await make(script, mode="auto")
    await agent.send("wait")
    async def stop_when_running():
        while True:
            ev = await q.get()
            if ev["ev"] == "status" and ev["state"] == "tool":
                await asyncio.sleep(0.2)
                await agent.stop()
                return
    await asyncio.wait_for(stop_when_running(), 10)
    items = sv.store.items(agent.sid)
    assert any(i["type"] == "tool" and i["status"] == "cancelled" for i in items)
    assert items[-1]["type"] == "notice" and items[-1]["text"] == "Stopped."
    await sv.close()


async def test_queued_message_joins_next_step():
    script = Script([tool_reply("bash", {"command": "sleep 0.5; echo ok"}), text_reply("first"),
                     text_reply("second")])
    sv, agent, q = await make(script, mode="auto")
    await agent.send("one")
    await asyncio.sleep(0.2)
    await agent.send("two")
    await drain(q)
    users = [i["text"] for i in sv.store.items(agent.sid) if i["type"] == "user"]
    assert users == ["one", "two"]
    await sv.close()


async def test_compaction_when_context_fills():
    big = [{"choices": [{"delta": {"tool_calls": [{"index": 0, "id": "c1", "function": {
        "name": "bash", "arguments": json.dumps({"command": "echo hi"})}}]}}]},
        {"choices": [{"delta": {}, "finish_reason": "tool_calls"}], "usage": {"prompt_tokens": 900,
                                                                                "completion_tokens": 9}}]
    script = Script([big, text_reply("summary of things"), text_reply("all done")])
    sv, agent, q = await make(script, mode="auto")
    await agent.send("go")
    await drain(q)
    types = [i["type"] for i in sv.store.items(agent.sid)]
    assert "summary" in types
    last_req = script.requests[-1]["messages"]
    assert "Summary of our conversation" in last_req[1]["content"]
    await sv.close()


async def test_runaway_repetition_is_cut_off():
    loop_chunks = [{"choices": [{"delta": {"content": "I will check the files now and report back. "}}]}] * 200
    script = Script([loop_chunks])
    sv, agent, q = await make(script, mode="auto")
    await agent.send("go")
    await drain(q)
    items = sv.store.items(agent.sid)
    assert items[-1]["type"] == "notice" and "repeating" in items[-1]["text"]
    assert len(items[-2]["text"]) < 3000
    await sv.close()
