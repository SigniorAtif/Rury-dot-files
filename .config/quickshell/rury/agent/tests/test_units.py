import asyncio

import pytest

from rury_agent import automations, llm, models, skills
from rury_agent.sessions import Store
from rury_agent.tools import Ctx, files


def ctx(tmp_path):
    async def emit(ev, p):
        pass

    async def ask(q, o):
        return ""
    return Ctx(session_id="t", cwd=str(tmp_path), mode="auto", emit=emit, ask_user=ask)


async def test_edit_file_exact_once(tmp_path):
    f = tmp_path / "a.txt"
    f.write_text("one\ntwo\ntwo\n")
    c = ctx(tmp_path)
    r = await files.edit_file({"path": str(f), "old": "two", "new": "2"}, c)
    assert not r.ok and "2 times" in r.text
    r = await files.edit_file({"path": str(f), "old": "one", "new": "1"}, c)
    assert r.ok and f.read_text() == "1\ntwo\ntwo\n" and "-one" in r.meta["diff"]
    r = await files.edit_file({"path": str(f), "old": "two", "new": "2", "replace_all": True}, c)
    assert r.ok and f.read_text() == "1\n2\n2\n"
    r = await files.edit_file({"path": str(f), "old": "nope", "new": "x"}, c)
    assert not r.ok


async def test_read_file_numbers_and_pages(tmp_path):
    f = tmp_path / "b.txt"
    f.write_text("\n".join(f"line {i}" for i in range(1, 11)))
    r = await files.read_file({"path": "b.txt", "offset": 3, "limit": 2}, ctx(tmp_path))
    assert "    3\tline 3" in r.text and "    4\tline 4" in r.text and "offset=5" in r.text


def test_think_splitter_across_chunks():
    sp = llm.ThinkSplitter()
    out = []
    for chunk in ["hel", "lo <thi", "nk>pondering</th", "ink> world"]:
        out += sp.feed(chunk)
    text = "".join(t for k, t in out if k == "text")
    think = "".join(t for k, t in out if k == "thinking")
    assert text == "hello  world" and think == "pondering"


def test_partial_field_streams_escapes():
    pf = llm.PartialField("reply")
    buf = '{"thought": "x", "reply": "a\\nb'
    assert pf.take(buf) == "a\nb"
    assert pf.take(buf + ' \\"q\\""}') == ' "q"'
    assert pf.done


def test_recover_text_calls():
    calls, rest = llm.recover_text_calls('Sure.\n<tool_call>{"name": "bash", "arguments": {"command": "ls"}}'
                                         '</tool_call>', {"bash"})
    assert calls[0].name == "bash" and calls[0].args == {"command": "ls"} and rest == "Sure."
    calls, _ = llm.recover_text_calls('```json\n{"tool": "bash", "args": {"command": "pwd"}}\n```', {"bash"})
    assert calls[0].args == {"command": "pwd"}
    calls, rest = llm.recover_text_calls('{"name": "nope", "arguments": {}}', {"bash"})
    assert calls == []


def test_store_roundtrip(tmp_path):
    st = Store(tmp_path / "s.db")
    s = st.create(mode="ask", model="m", cwd="/")
    st.add(s["id"], "user", {"text": "hi", "images": []})
    iid = st.add(s["id"], "tool", {"name": "bash", "status": "running"})
    st.set(iid, {"name": "bash", "status": "ok"})
    items = st.items(s["id"])
    assert [i["type"] for i in items] == ["user", "tool"] and items[1]["status"] == "ok"
    assert st.list()[0]["turns"] == 1
    a = st.add_automation(name="x", schedule="every 5m", prompt="p", mode="auto", model="m", enabled=1)
    st.update_automation(a["id"], enabled=0)
    assert st.automations()[0]["enabled"] == 0


def test_schedules():
    assert automations.next_run("every 30m", 0) == 1800
    assert automations.next_run("every 2h", 100) == 7300
    assert automations.next_run("0 9 * * *", 0) > 0
    assert automations.next_run("at 2001-01-01 00:00") is None
    with pytest.raises(ValueError):
        automations.next_run("sometimes")
    with pytest.raises(ValueError):
        automations.next_run("every 10s")


def test_gguf_discovery_pairs_mmproj(tmp_path):
    d = tmp_path / "models"
    d.mkdir(exist_ok=True)
    for n in ("Gemma-4-12B-OBLITERATED-Q4_K_M.gguf", "mmproj-gemma-4-12B-it-Q8_0.gguf",
              "Qwen3.6-35B-A3B-IQ3_XXS.gguf", "mmproj-Qwen3.6-35B-A3B-BF16.gguf", "gpt-oss-20b-MXFP4.gguf"):
        (d / n).write_bytes(b"")
    found = {m.name: m for m in models.discover_ggufs(d)}
    assert found["Gemma 4 12B OBLITERATED"].mmproj.endswith("mmproj-gemma-4-12B-it-Q8_0.gguf")
    assert "Qwen3.6" in found["Qwen3.6 35B A3B"].mmproj
    assert found["gpt oss 20b"].mmproj == "" and not found["gpt oss 20b"].vision


def test_skill_frontmatter(tmp_path):
    d = tmp_path / "sk/web"
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text("---\nname: web\ndescription: >\n  Read pages\n  and search.\n---\n\n# Body\nx\n")
    sk = skills.load(tmp_path / "sk")
    assert sk[0].name == "web" and sk[0].description == "Read pages and search." and sk[0].body() == "# Body\nx"


def test_looping_detector():
    assert llm.looping("abc def ghi. " * 60)
    assert not llm.looping("".join(f"line {i} says something new\n" for i in range(200)))


def test_mcp_search_prefers_everyday_actions_on_ties():
    from rury_agent.mcp_hub import Hub, McpTool
    hub = Hub()
    names = ["browser_close", "browser_resize", "browser_console_messages", "browser_handle_dialog",
             "browser_evaluate", "browser_file_upload", "browser_drop", "browser_navigate", "browser_snapshot",
             "browser_click", "browser_type"]
    hub.all_tools = lambda: [McpTool("playwright", n, "", {}) for n in names]
    got = [t.name for t in hub.search("browser", limit=4)]
    assert got == ["browser_navigate", "browser_snapshot", "browser_click", "browser_type"]
    assert [t.name for t in hub.search("browser_drop")] == ["browser_drop"]
