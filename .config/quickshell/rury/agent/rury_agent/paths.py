"""Where the agent keeps things. Every root can be moved with an env var (tests point them at a tmp dir)."""
from __future__ import annotations

import os
from pathlib import Path

HOME = Path.home()


def _env_path(name: str, default: Path) -> Path:
    v = os.environ.get(name)
    return Path(v).expanduser() if v else default


# user-editable: AGENT.md, models.toml, mcp.json, permissions.toml, skills/, memory/, desk/
CONFIG = _env_path("RURY_AGENT_CONFIG", HOME / ".config/rury/agent")
# sessions.db, logs, full tool outputs
STATE = _env_path("RURY_AGENT_STATE", HOME / ".local/state/rury/agent")
# venv, scratch dir, the desk's browser profiles
DATA = _env_path("RURY_AGENT_DATA", HOME / ".local/share/rury/agent")
# sockets and the desk's env file
RUN = _env_path("RURY_AGENT_RUN", Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "rury")

SOCKET = RUN / "agent.sock"
DESK_ENV = RUN / "desk.env"
DESK_VNC = RUN / "desk-vnc.sock"

AGENT_MD = CONFIG / "AGENT.md"
MODELS_TOML = CONFIG / "models.toml"
MCP_JSON = CONFIG / "mcp.json"
PERMISSIONS_TOML = CONFIG / "permissions.toml"
SETTINGS_TOML = CONFIG / "settings.toml"
SKILLS = CONFIG / "skills"
MEMORY = CONFIG / "memory"
DESK_SWAY_CONF = CONFIG / "desk/sway.conf"

SESSIONS_DB = STATE / "sessions.db"
OUTPUTS = STATE / "outputs"
LOGS = STATE / "logs"

SCRATCH = DATA / "work"

LLAMA_SERVER = _env_path("RURY_LLAMA_SERVER", HOME / ".local/share/rury/llama/llama-server")
MODELS_DIR = _env_path("RURY_MODELS_DIR", Path("/mnt/d/rury/models"))

PACKAGE_DIR = Path(__file__).resolve().parent.parent  # .../quickshell/rury/agent
LAUNCHER = PACKAGE_DIR / "agent"


def ensure_dirs() -> None:
    for d in (CONFIG, SKILLS, MEMORY, STATE, OUTPUTS, LOGS, DATA, SCRATCH, RUN):
        d.mkdir(parents=True, exist_ok=True)
