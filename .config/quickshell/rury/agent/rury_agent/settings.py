"""Small knobs from settings.toml, with defaults that work out of the box."""
from __future__ import annotations

import tomllib
from dataclasses import dataclass, field

from . import paths


@dataclass
class Settings:
    default_mode: str = "ask"            # chat | plan | ask | auto
    max_steps: int = 40                  # tool rounds per user message
    tool_output_chars: int = 6000        # what the model sees of one tool result; the rest goes to a file
    max_tokens: int = 2048               # per model reply
    compact_at: float = 0.75             # fraction of the context window that triggers a summary
    llama_idle_stop: int = 600           # seconds without a request before llama-server is stopped
    desk_width: int = 1280
    desk_height: int = 800
    desk_mcp_servers: list[str] = field(default_factory=lambda: ["playwright"])  # treated like desk input
    bash_timeout: int = 120


def load() -> Settings:
    s = Settings()
    try:
        data = tomllib.loads(paths.SETTINGS_TOML.read_text())
    except (OSError, tomllib.TOMLDecodeError):
        return s
    for k, v in data.items():
        if hasattr(s, k):
            setattr(s, k, v)
    return s
