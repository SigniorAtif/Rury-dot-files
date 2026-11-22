"""Plug-and-play model registry.

A model is anything that speaks the OpenAI chat API. Two kinds:
  llama.cpp  a GGUF on disk; the agent starts llama-server for it on demand and stops it when idle
  openai     an endpoint that is already running (Ollama, LM Studio, a cloud API)

Entries come from models.toml plus auto-discovery: every *.gguf under MODELS_DIR (with a matching
mmproj-*.gguf for vision), Ollama's tags on :11434 and LM Studio's models on :1234 when those are up.
Keys are read from the rury keyring (the same entries the old chat's /key command writes), so
`key = "keyring:openrouter"` in models.toml finds `apiKeys.openrouter`.
"""
from __future__ import annotations

import asyncio
import os
import re
import signal
import subprocess
import time
import tomllib
from dataclasses import dataclass, field, asdict
from pathlib import Path

import httpx

from . import paths

LLAMA_PORT = int(os.environ.get("RURY_LLAMA_PORT", "8766"))


@dataclass
class ModelSpec:
    id: str
    name: str
    kind: str = "openai"               # llama.cpp | openai
    base_url: str = ""
    model: str = ""                    # the model field sent to the API
    gguf: str = ""
    mmproj: str = ""
    ctx: int = 32768
    vision: bool = False
    tools: str = "auto"                # native | json | auto
    key: str = ""                      # "", "env:NAME", "keyring:NAME" or a literal (discouraged)
    extra_args: list[str] = field(default_factory=list)   # extra llama-server flags
    params: dict = field(default_factory=dict)            # extra request fields (temperature, top_p, ...)
    source: str = "config"             # config | gguf | ollama | lmstudio

    def public(self) -> dict:
        d = asdict(self)
        d.pop("key", None)
        d["has_key"] = bool(self.key)
        return d


def _pretty(stem: str) -> str:
    s = re.sub(r"[-_.](Q\d\w*|IQ\d\w*|MXFP4\w*|F16|BF16|i1)$", "", stem, flags=re.I)
    return s.replace("_", " ").replace("-", " ")


_QUANT = re.compile(r"^(q\d.*|iq\d.*|k|m|s|l|xs|xxs|0|1|i1|f16|bf16|f32|mxfp4.*|gguf|mmproj|it|instruct)$")


def _tokens(stem: str) -> set[str]:
    return {t for t in re.findall(r"[a-z0-9]+", stem.lower()) if not _QUANT.match(t)}


def discover_ggufs(root: Path | None = None) -> list[ModelSpec]:
    root = root or paths.MODELS_DIR
    if not root.is_dir():
        return []
    out = []
    files = sorted(p for p in root.rglob("*.gguf") if not p.name.lower().startswith("mmproj"))
    for f in files:
        # the mmproj in the same folder that shares the most name tokens (family, size) with the model;
        # at least two shared tokens, so a Gemma projector never gets paired with a Qwen model
        mm, best = "", 1
        mine = _tokens(f.stem)
        for c in sorted(f.parent.glob("mmproj*.gguf")):
            shared = len(mine & _tokens(c.stem))
            if shared > best:
                best, mm = shared, str(c)
        mid = "gguf:" + re.sub(r"[^a-z0-9]+", "-", f.stem.lower()).strip("-")
        out.append(ModelSpec(id=mid, name=_pretty(f.stem), kind="llama.cpp", gguf=str(f), mmproj=mm,
                             vision=bool(mm), source="gguf"))
    return out


async def _probe_json(url: str) -> dict | None:
    try:
        async with httpx.AsyncClient(timeout=1.5) as c:
            r = await c.get(url)
            if r.status_code == 200:
                return r.json()
    except (httpx.HTTPError, ValueError):
        pass
    return None


async def discover_servers() -> list[ModelSpec]:
    out: list[ModelSpec] = []
    tags = await _probe_json("http://127.0.0.1:11434/api/tags")
    for m in (tags or {}).get("models", []):
        name = m.get("name", "")
        out.append(ModelSpec(id=f"ollama:{name}", name=f"{name} (Ollama)", base_url="http://127.0.0.1:11434/v1",
                             model=name, source="ollama", ctx=8192))
    lms = await _probe_json("http://127.0.0.1:1234/v1/models")
    for m in (lms or {}).get("data", []):
        mid = m.get("id", "")
        out.append(ModelSpec(id=f"lmstudio:{mid}", name=f"{mid} (LM Studio)", base_url="http://127.0.0.1:1234/v1",
                             model=mid, source="lmstudio"))
    return out


def load_config_models() -> tuple[list[ModelSpec], str]:
    try:
        data = tomllib.loads(paths.MODELS_TOML.read_text())
    except OSError:
        return [], ""
    default = data.get("default", "")
    out = []
    for mid, d in (data.get("models") or {}).items():
        d = dict(d)
        d.setdefault("name", mid)
        known = {k: v for k, v in d.items() if k in ModelSpec.__dataclass_fields__}
        spec = ModelSpec(id=mid, **{k: v for k, v in known.items() if k != "id"})
        if spec.kind == "llama.cpp" and spec.gguf:
            spec.gguf = str(Path(spec.gguf).expanduser())
            spec.mmproj = str(Path(spec.mmproj).expanduser()) if spec.mmproj else ""
            spec.vision = spec.vision or bool(spec.mmproj)
        out.append(spec)
    return out, default


class Registry:
    def __init__(self):
        self.models: dict[str, ModelSpec] = {}
        self.default: str = ""

    async def refresh(self) -> None:
        cfg, default = load_config_models()
        found = discover_ggufs() + await discover_servers()
        models: dict[str, ModelSpec] = {}
        cfg_ggufs = {m.gguf for m in cfg if m.gguf}
        for m in found:
            if m.gguf and m.gguf in cfg_ggufs:
                continue  # models.toml describes this file already
            models[m.id] = m
        for m in cfg:
            models[m.id] = m
        self.models = models
        self.default = default if default in models else next(iter(models), "")

    def get(self, mid: str | None) -> ModelSpec:
        mid = mid or self.default
        if mid not in self.models:
            raise KeyError(f"unknown model {mid!r}; known: {', '.join(self.models) or 'none'}")
        return self.models[mid]

    def listing(self) -> list[dict]:
        return [m.public() | {"default": m.id == self.default} for m in self.models.values()]


def resolve_key(spec: ModelSpec) -> str:
    k = spec.key
    if not k:
        return ""
    if k.startswith("env:"):
        return os.environ.get(k[4:], "")
    if k.startswith("keyring:"):
        name = k[8:]
        for attrs in (["application", "rury", "key", f"apiKeys.{name}"], ["application", "rury", "name", name]):
            try:
                r = subprocess.run(["secret-tool", "lookup", *attrs], capture_output=True, text=True, timeout=5)
                if r.returncode == 0 and r.stdout.strip():
                    return r.stdout.strip()
            except (OSError, subprocess.TimeoutExpired):
                pass
        return ""
    return k


def _die_with_parent() -> None:
    """In the child before exec: get SIGTERM when the agent process dies, so a crash never leaves a 7 GB
    llama-server behind."""
    import ctypes
    try:
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
    except OSError:
        pass


class LlamaServer:
    """One llama-server at a time. ensure(spec) starts it (or swaps the model) and returns its base URL."""

    def __init__(self, idle_stop: int = 600):
        self.proc: subprocess.Popen | None = None
        self.spec: ModelSpec | None = None
        self.last_used = 0.0
        self.idle_stop = idle_stop
        self.lock = asyncio.Lock()
        self.state = "off"  # off | starting | on
        self.on_state = None  # callback(state, model_id)

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{LLAMA_PORT}/v1"

    def _set(self, state: str) -> None:
        self.state = state
        if self.on_state:
            self.on_state(state, self.spec.id if self.spec else "")

    async def healthy(self) -> bool:
        d = await _probe_json(f"http://127.0.0.1:{LLAMA_PORT}/health")
        return bool(d and d.get("status") == "ok")

    async def ensure(self, spec: ModelSpec, wait_s: float = 300) -> str:
        async with self.lock:
            self.last_used = time.time()
            if self.proc and self.proc.poll() is None and self.spec and self.spec.gguf == spec.gguf:
                if await self.healthy():
                    return self.base_url
            else:
                await self._stop()
                self._launch(spec)
            t0 = time.time()
            while time.time() - t0 < wait_s:
                if self.proc and self.proc.poll() is not None:
                    self._set("off")
                    raise RuntimeError(f"llama-server exited ({self.proc.returncode}); see {paths.LOGS / 'llama-server.log'}")
                if await self.healthy():
                    self._set("on")
                    self.last_used = time.time()
                    return self.base_url
                await asyncio.sleep(0.5)
            await self._stop()
            raise RuntimeError("llama-server did not become ready in time")

    def _launch(self, spec: ModelSpec) -> None:
        if not paths.LLAMA_SERVER.exists():
            raise RuntimeError(f"llama-server not found at {paths.LLAMA_SERVER}")
        if not Path(spec.gguf).exists():
            raise RuntimeError(f"model file missing: {spec.gguf} (is D: mounted?)")
        paths.LOGS.mkdir(parents=True, exist_ok=True)
        log = open(paths.LOGS / "llama-server.log", "ab")
        cmd = [str(paths.LLAMA_SERVER), "-m", spec.gguf, "-ngl", "99", "-c", str(spec.ctx), "--jinja",
               "--host", "127.0.0.1", "--port", str(LLAMA_PORT), "-np", "1", "--cache-reuse", "256",
               "--no-webui"]
        if spec.mmproj:
            cmd += ["--mmproj", spec.mmproj]
        cmd += list(spec.extra_args)
        llama_dir = str(paths.LLAMA_SERVER.parent)
        env = dict(os.environ, LD_LIBRARY_PATH=f"{llama_dir}:{os.environ.get('LD_LIBRARY_PATH', '')}")
        self.proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
                                     env=env, cwd=llama_dir, preexec_fn=_die_with_parent)
        self.spec = spec
        self._set("starting")

    async def _stop(self) -> None:
        p, self.proc = self.proc, None
        if p and p.poll() is None:
            try:
                os.killpg(p.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            for _ in range(50):
                if p.poll() is not None:
                    break
                await asyncio.sleep(0.1)
            if p.poll() is None:
                try:
                    os.killpg(p.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        if self.state != "off":
            self._set("off")

    async def stop(self) -> None:
        async with self.lock:
            await self._stop()

    async def reap_idle(self, busy: bool) -> None:
        if self.proc and not busy and time.time() - self.last_used > self.idle_stop:
            await self.stop()

    def touch(self) -> None:
        self.last_used = time.time()
