import os
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))


@pytest.fixture(autouse=True)
def isolated(tmp_path, monkeypatch):
    """Every test gets its own config/state/data/run dirs: never the live ones."""
    from rury_agent import paths
    for name, sub in (("CONFIG", "config"), ("STATE", "state"), ("DATA", "data"), ("RUN", "run")):
        monkeypatch.setattr(paths, name, tmp_path / sub)
    monkeypatch.setattr(paths, "SOCKET", tmp_path / "run/agent.sock")
    monkeypatch.setattr(paths, "DESK_ENV", tmp_path / "run/desk.env")
    monkeypatch.setattr(paths, "AGENT_MD", tmp_path / "config/AGENT.md")
    monkeypatch.setattr(paths, "MODELS_TOML", tmp_path / "config/models.toml")
    monkeypatch.setattr(paths, "MCP_JSON", tmp_path / "config/mcp.json")
    monkeypatch.setattr(paths, "PERMISSIONS_TOML", tmp_path / "config/permissions.toml")
    monkeypatch.setattr(paths, "SETTINGS_TOML", tmp_path / "config/settings.toml")
    monkeypatch.setattr(paths, "SKILLS", tmp_path / "config/skills")
    monkeypatch.setattr(paths, "MEMORY", tmp_path / "config/memory")
    monkeypatch.setattr(paths, "SESSIONS_DB", tmp_path / "state/sessions.db")
    monkeypatch.setattr(paths, "OUTPUTS", tmp_path / "state/outputs")
    monkeypatch.setattr(paths, "LOGS", tmp_path / "state/logs")
    monkeypatch.setattr(paths, "SCRATCH", tmp_path / "data/work")
    monkeypatch.setattr(paths, "MODELS_DIR", tmp_path / "models")
    paths.ensure_dirs()
    yield tmp_path
