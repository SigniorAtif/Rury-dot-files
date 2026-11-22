"""The agent's headless desk: start/stop it, read its addresses, run things inside it, open the viewer."""
from __future__ import annotations

import asyncio
import json
import os
import shutil
import subprocess
import time

from . import paths

UNIT = "rury-agent-desk.service"
VIEWER_TITLE = "SigniorAtif Agent"


def read_env() -> dict[str, str]:
    try:
        lines = paths.DESK_ENV.read_text().splitlines()
    except OSError:
        return {}
    return dict(line.split("=", 1) for line in lines if "=" in line)


def child_env() -> dict[str, str]:
    """Environment for a command that should act on the desk, not on Atif's session."""
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("HYPRLAND_", "WAYLAND_", "SWAYSOCK", "I3SOCK", "DISPLAY", "DBUS_SESSION"))}
    env.update({k: v for k, v in read_env().items() if v})
    env["RURY_DESK"] = "1"
    return env


class Desk:
    def __init__(self, width: int = 1280, height: int = 800):
        self.width, self.height = width, height
        self.last_action = ""
        self.on_change = None   # callback(dict)

    async def running(self) -> bool:
        env = read_env()
        sock = env.get("SWAYSOCK", "")
        if not sock or not os.path.exists(sock):
            return False
        p = await asyncio.create_subprocess_exec("swaymsg", "-s", sock, "-t", "get_version",
                                                 stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
        return await p.wait() == 0

    async def start(self, wait_s: float = 20) -> None:
        if await self.running():
            return
        unit_ok = subprocess.run(["systemctl", "--user", "cat", UNIT], capture_output=True).returncode == 0
        if unit_ok:
            await (await asyncio.create_subprocess_exec("systemctl", "--user", "start", UNIT)).wait()
        else:
            subprocess.Popen([str(paths.PACKAGE_DIR / "desk-session")], start_new_session=True,
                             stdout=open(paths.LOGS / "desk.log", "ab"), stderr=subprocess.STDOUT)
        for _ in range(int(wait_s * 10)):
            if await self.running():
                for _ in range(50):   # the viewer needs wayvnc's socket, which comes up just after sway
                    if paths.DESK_VNC.exists():
                        break
                    await asyncio.sleep(0.1)
                self._changed()
                return
            await asyncio.sleep(0.1)
        raise RuntimeError("the agent desk did not start; see `journalctl --user -u rury-agent-desk`")

    async def stop(self) -> None:
        if subprocess.run(["systemctl", "--user", "is-active", "--quiet", UNIT]).returncode == 0:
            await (await asyncio.create_subprocess_exec("systemctl", "--user", "stop", UNIT)).wait()
        else:
            sock = read_env().get("SWAYSOCK")
            if sock:
                await (await asyncio.create_subprocess_exec("swaymsg", "-s", sock, "exit",
                                                            stdout=asyncio.subprocess.DEVNULL)).wait()
        self._changed(running=False)

    async def ensure(self) -> dict[str, str]:
        await self.start()
        return child_env()

    async def swaymsg(self, *args: str, msg_type: str = "") -> tuple[int, str]:
        env = await self.ensure()
        argv = ["swaymsg", "-s", env["SWAYSOCK"]]
        if msg_type:
            argv += ["-t", msg_type]
        argv += list(args)
        p = await asyncio.create_subprocess_exec(*argv, stdout=asyncio.subprocess.PIPE,
                                                 stderr=asyncio.subprocess.STDOUT, env=env)
        out, _ = await p.communicate()
        return p.returncode or 0, out.decode(errors="replace")

    async def windows(self) -> list[dict]:
        code, out = await self.swaymsg("-r", msg_type="get_tree")
        if code:
            return []
        wins: list[dict] = []

        def walk(n, ws=""):
            if n.get("type") == "workspace":
                ws = n.get("name", "")
            if n.get("type") in ("con", "floating_con") and n.get("pid"):
                r = n.get("rect", {})
                wins.append({"id": n["id"], "app": n.get("app_id") or (n.get("window_properties") or {}).get("class", ""),
                             "title": n.get("name") or "", "focused": n.get("focused", False), "workspace": ws,
                             "visible": n.get("visible", False),
                             "box": [self.norm_x(r.get("x", 0)), self.norm_y(r.get("y", 0)),
                                     self.norm_x(r.get("x", 0) + r.get("width", 0)),
                                     self.norm_y(r.get("y", 0) + r.get("height", 0))]})
            for c in n.get("nodes", []) + n.get("floating_nodes", []):
                walk(c, ws)

        try:
            walk(json.loads(out))
        except json.JSONDecodeError:
            return []
        return wins

    # coordinates: the model works in 0-1000 on both axes (what Gemma, Gemini and Qwen-VL point in)
    def px(self, x: float, y: float) -> tuple[int, int]:
        X = round(max(0.0, min(1000.0, float(x))) / 1000 * (self.width - 1))
        Y = round(max(0.0, min(1000.0, float(y))) / 1000 * (self.height - 1))
        return max(X, 1), max(Y, 1)   # sway's `cursor set` treats 0 as "leave unchanged"

    def norm_x(self, px: int) -> int:
        return round(px / max(self.width - 1, 1) * 1000)

    def norm_y(self, py: int) -> int:
        return round(py / max(self.height - 1, 1) * 1000)

    def _changed(self, action: str = "", running: bool = True) -> None:
        if action:
            self.last_action = action
        if not running:
            self.last_action = ""
        if self.on_change:
            self.on_change({"last_action": self.last_action, "running": running})

    def note(self, action: str) -> None:
        self._changed(action)


viewer_control = False   # the viewer we last launched sends Atif's mouse/keyboard to the desk


def open_viewer(control: bool | None = None, toggle: bool = True) -> None:
    """Show the desk on Atif's screen in special:agent (Super+Shift+/); toggles the workspace.

    control=None keeps whatever viewer is open (view-only when it has to start one); True/False
    replaces it with a controlling / view-only one.
    """
    global viewer_control
    clients = subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True).stdout
    try:
        mine = [c for c in json.loads(clients or "[]") if c.get("title", "").startswith(VIEWER_TITLE)]
    except json.JSONDecodeError:
        mine = []
    if control is not None and mine:
        for c in mine:
            try:
                os.kill(int(c["pid"]), 15)
            except (OSError, KeyError, ValueError):
                pass
        mine = []
    if not mine:
        if not shutil.which("vncviewer"):
            raise RuntimeError("vncviewer (tigervnc) is not installed")
        # the window title comes from the server's desktop name (wayvnc --name in sway.conf)
        # TigerVNC 1.16 options (it exits on unknown ones; MenuKey is gone, Ctrl+Alt+M opens the menu now).
        # No error dialogs: if the desk goes away the viewer just closes.
        args = ["vncviewer", f"-ViewOnly={0 if control else 1}", "-RemoteResize=0", "-Shared=1",
                "-AlertOnFatalError=0", "-ReconnectOnError=0", str(paths.DESK_VNC)]
        # its own transient unit, so restarting the daemon (whose cgroup systemd cleans out) keeps the viewer
        if shutil.which("systemd-run"):
            env = [f"--setenv={k}={os.environ[k]}" for k in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY")
                   if os.environ.get(k)]
            args = ["systemd-run", "--user", "--collect", "--quiet", f"--unit=rury-agent-viewer-{int(time.time() * 1000)}",
                    *env, "--", *args]
        log = open(paths.LOGS / "viewer.log", "ab")
        subprocess.Popen(args, start_new_session=True, stdout=log, stderr=subprocess.STDOUT)
        viewer_control = bool(control)
        if special_visible():
            return  # special:agent is already on screen; the new window lands there
    if toggle:
        subprocess.run(["hyprctl", "dispatch", 'hl.dsp.workspace.toggle_special("agent")'], capture_output=True)


def special_visible() -> bool:
    out = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, text=True).stdout
    try:
        return any((m.get("specialWorkspace") or {}).get("name") == "special:agent" for m in json.loads(out or "[]"))
    except json.JSONDecodeError:
        return False
