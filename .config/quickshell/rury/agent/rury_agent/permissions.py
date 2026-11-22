"""Who may run what.

Modes
  chat  no tools at all
  plan  read-only tools; anything that changes something is refused (the model should call exit_plan)
  ask   reads run freely; every call that changes something waits for approval
  auto  everything runs, except RISKY calls, which wait for approval
In every mode a risky call asks, and a HARD-DENIED one never runs (sudo and friends are handed to Atif
as a command to run himself).

Rules in permissions.toml (`allow = [...]`, `deny = [...]`) use Claude Code's shape:
  Bash(git commit:*)   any simple command starting with "git commit"
  Bash(make test)      exactly that command
  Write(~/notes/**)    file writes and edits under that glob
  mcp__playwright__*   tool names (fnmatch)
An allow rule clears an ordinary ask (that is what "Always allow" saves). No rule clears a risky call or a
hard deny: risky asks every time, as Atif asked.
"""
from __future__ import annotations

import fnmatch
import os
import re
import shlex
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

from . import paths

HOME = str(Path.home())


@dataclass
class Verdict:
    action: str                  # allow | ask | deny | block
    risky: bool = False
    reason: str = ""
    rule: str = ""               # what "Always allow" would save
    handoff: str = ""            # a command Atif can run himself (sudo)


# ---- paths ----------------------------------------------------------------------------------------

PROTECTED = [
    "~/.config", "~/dotfiles", "~/dotfiles-public", "~/.ssh", "~/.gnupg", "~/.local/share/keyrings",
    "~/.claude", "~/.claude.json", "~/.bashrc", "~/.bash_profile", "~/.profile", "~/.zshrc", "~/.gitconfig",
    "~/.pki", "~/.mozilla", "~/.local/bin", "~/.local/share/rury/llama",
    "/etc", "/usr", "/boot", "/var", "/opt", "/bin", "/sbin", "/lib", "/lib64", "/srv", "/root", "/mnt",
    "/proc", "/sys", "/dev",
]
# inside a protected tree but the agent's own
OWN = ["~/.config/rury/agent/memory"]
FREE_ROOTS = ["/tmp", "/dev/shm"]          # scratch-like: deleting there isn't risky
CATASTROPHIC = ["/", "~", "/home", "/home/*", "/usr", "/etc", "/boot", "/var", "/mnt", "/mnt/*", "/*", "~/*"]


def _x(p: str) -> str:
    return os.path.normpath(os.path.expanduser(p))


def resolve(p: str, cwd: str) -> str:
    p = p.replace("${HOME}", HOME).replace("$HOME", HOME)
    p = os.path.expanduser(p)
    if not os.path.isabs(p):
        p = os.path.join(cwd, p)
    return os.path.normpath(p)


def _under(p: str, root: str) -> bool:
    root = _x(root)
    return p == root or p.startswith(root.rstrip("/") + "/")


def write_rule(p: str) -> str:
    """The rule an "always allow" click saves for a write to p: its folder, unless that folder is so broad
    (home, /, or a protected root like ~/.config) that the rule would cover far more than Atif meant."""
    d = os.path.dirname(p) or "/"
    roots = {HOME, "/", os.path.dirname(HOME)} | {os.path.expanduser(r) for r in PROTECTED}
    if d in roots or HOME.startswith(d + "/"):
        return f"Write({p})"
    return f"Write({d}/**)"


def is_protected(p: str) -> bool:
    if any(_under(p, o) for o in OWN):
        return False
    return any(_under(p, r) for r in PROTECTED)


def is_scratch(p: str) -> bool:
    return _under(p, str(paths.SCRATCH)) or any(_under(p, r) for r in FREE_ROOTS)


def _glob_root(p: str) -> str:
    """The literal part of a path before its first glob character."""
    m = re.search(r"[*?\[]", p)
    if not m:
        return p
    return os.path.dirname(p[:m.start()]) or "/"


def is_catastrophic(arg: str, cwd: str) -> bool:
    a = arg.rstrip("/") or "/"
    if a in ("/", "~", "$HOME", "${HOME}", "/*", "~/*", "$HOME/*", "*") and a != "*":
        return True
    r = resolve(arg, cwd)
    if r in ("/", HOME, "/home"):
        return True
    if re.search(r"[*?]", arg) and _glob_root(r) in ("/", HOME, "/home"):
        return True
    return False


# ---- shell analysis -------------------------------------------------------------------------------

DENY_RX = [
    (re.compile(r"(^|[\s;&|(`$])(sudo|pkexec|doas)(\s|$)"), "needs root"),
    (re.compile(r"(^|[\s;&|(])su(\s+-\s*|\s+root\b|\s*$)"), "needs root"),
    (re.compile(r"\bmkfs(\.\w+)?\b"), "formats a filesystem"),
    (re.compile(r"\bdd\b[^;&|]*\bof=/dev/(sd|nvme|mmcblk|hd|vd|disk|mapper)"), "writes raw to a disk"),
    (re.compile(r">\s*/dev/(sd|nvme|mmcblk|hd|vd)\w*"), "writes raw to a disk"),
    (re.compile(r":\s*\(\s*\)\s*\{[^}]*:\s*\|\s*:"), "fork bomb"),
    (re.compile(r"\b(wipefs|blkdiscard)\b"), "wipes a disk"),
    (re.compile(r"\bchmod\s+(-\w+\s+)*-R\s+\S*\s+/\s*$|\bchown\s+(-\w+\s+)*-R\s+\S+\s+/\s*$"), "recursive permissions on /"),
]

# text that makes inline code (python -c, perl -e, node -e ...) risky
RISKY_CODE_RX = re.compile(
    r"rmtree|os\.remove|os\.unlink|\.unlink\(|os\.rmdir|shutil\.move|os\.rename|send2trash|"
    r"subprocess|os\.system|Popen|child_process|execSync|fs\.rm|fs\.unlink|rimraf|DROP\s+TABLE|DELETE\s+FROM|"
    r"truncate|requests\.(post|put|delete|patch)|httpx\.(post|put|delete|patch)",
    re.I)

WRAPPERS = {"nohup", "time", "nice", "ionice", "command", "builtin", "exec", "stdbuf", "unbuffer", "env",
            "setsid", "chronic", "caffeinate", "systemd-run", "flock"}
KEYWORDS = {"if", "then", "else", "elif", "fi", "do", "done", "while", "until", "{", "}", "!", "[[", "]]", "case", "esac"}
SHELLS = {"bash", "sh", "zsh", "fish", "dash"}
INTERPRETERS = {"python", "python3", "node", "perl", "ruby", "php", "lua", "deno", "bun"}

READONLY = {
    "ls", "ll", "la", "cat", "bat", "head", "tail", "less", "more", "wc", "file", "stat", "du", "df", "free",
    "uptime", "uname", "whoami", "id", "groups", "date", "cal", "pwd", "echo", "printf", "which", "type",
    "whereis", "rg", "grep", "egrep", "fgrep", "ag", "fd", "tree", "ps", "pgrep", "pidof", "top", "htop",
    "lsblk", "lsusb", "lspci", "lscpu", "lsmod", "sensors", "ip", "ss", "ping", "host", "dig", "nslookup",
    "jq", "yq", "sort", "uniq", "cut", "tr", "column", "fold", "fmt", "nl", "rev", "comm", "diff", "cmp",
    "md5sum", "sha256sum", "sha1sum", "b2sum", "basename", "dirname", "realpath", "readlink", "seq", "true",
    "false", "test", "[", "env", "printenv", "hostname", "hostnamectl", "timedatectl", "locale", "journalctl",
    "fastfetch", "neofetch", "tldr", "man", "help", "xxd", "hexdump", "od", "strings", "nproc", "vulkaninfo",
    "glxinfo", "wpctl", "pactl", "playerctl", "nmcli", "iwctl", "bluetoothctl", "obscura", "exiftool",
    "identify", "ffprobe", "mediainfo", "pdfinfo", "pdftotext", "awk", "sed", "find", "xargs", "tee",
    "curl", "wget", "git", "hyprctl", "systemctl", "pacman", "yay", "paru", "pip", "uv", "npm", "gh",
    "swaymsg", "grim", "loginctl", "busctl", "qs", "secret-tool", "flatpak", "docker", "podman",
}
# commands in READONLY whose read-only-ness depends on arguments are refined in _simple()

GIT_READ = {"status", "log", "diff", "show", "branch", "remote", "rev-parse", "ls-files", "ls-tree", "blame",
            "describe", "shortlog", "reflog", "config", "tag", "grep", "cat-file", "rev-list", "fetch",
            "worktree", "stash", "help", "version", "merge-base", "name-rev", "count-objects", "whatchanged"}
GIT_RISKY = {"push", "reset", "clean", "checkout", "restore", "rebase", "filter-branch", "filter-repo",
             "update-ref", "gc", "prune", "rm", "switch", "am", "cherry-pick", "revert", "merge", "pull"}
SYSTEMCTL_READ = {"status", "show", "cat", "list-units", "list-unit-files", "list-timers", "list-sockets",
                  "is-active", "is-enabled", "is-failed", "list-dependencies", "help"}
HYPRCTL_RISKY = {"dispatch", "keyword", "reload", "kill", "setcursor", "plugin", "output", "switchxkblayout",
                 "seterror", "notify", "dismissnotify", "eval"}
GH_RISKY = re.compile(r"\b(create|merge|close|delete|edit|comment|review|reopen|transfer|archive|rename|"
                      r"lock|unlock|ready|upload|set|remove|add|fork|sync|cancel|rerun|run)\b")


@dataclass
class ShellInfo:
    deny: str = ""
    risky: list[str] = field(default_factory=list)
    readonly: bool = True
    commands: list[list[str]] = field(default_factory=list)   # simple commands, as token lists
    writes: list[str] = field(default_factory=list)            # files it writes (resolved)

    def mark(self, why: str) -> None:
        self.readonly = False
        if why not in self.risky:
            self.risky.append(why)


_HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][\w-]*)\1")
_SUBST = re.compile(r"\$\(([^()]*)\)|`([^`]*)`|<\(([^()]*)\)|>\(([^()]*)\)")
SEPS = {";", "&&", "||", "|", "&", "|&", ";;", "(", ")", "\n"}
REDIR = {">", ">>", "&>", ">|", "&>>", ">&"}


def _strip_heredocs(cmd: str) -> str:
    lines = cmd.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        tags = [m.group(2) for m in _HEREDOC.finditer(line)]
        i += 1
        for tag in tags:
            while i < len(lines) and lines[i].strip() != tag:
                i += 1
            i += 1  # the terminator
    return "\n".join(out)


def analyze_shell(cmd: str, cwd: str, depth: int = 0) -> ShellInfo:
    info = ShellInfo()
    if depth > 4:
        info.mark("nested too deep to check")
        return info
    flat = " ".join(cmd.split())
    for rx, why in DENY_RX:
        if rx.search(flat):
            info.deny = why
            info.readonly = False
            return info

    body = _strip_heredocs(cmd.replace("\\\n", " "))
    # command substitutions are commands too
    for m in _SUBST.finditer(body):
        inner = next(g for g in m.groups() if g is not None)
        sub = analyze_shell(inner, cwd, depth + 1)
        _merge(info, sub)
        if info.deny:
            return info
    body = _SUBST.sub(" __SUBST__ ", body)

    for line in body.split("\n"):
        try:
            lex = shlex.shlex(line, posix=True, punctuation_chars=True)
            lex.whitespace_split = True
            lex.commenters = "#"
            toks = list(lex)
        except ValueError:
            info.mark("could not parse the command")
            continue
        cur: list[str] = []
        prev_sep = ""
        for t in toks + [";"]:
            if t in SEPS or (set(t) <= set(";&|()") and t):
                if cur:
                    _simple(cur, cwd, info, depth, pipe_from=prev_sep == "|")
                prev_sep = t
                cur = []
            else:
                cur.append(t)
        if info.deny:
            return info
    return info


def _merge(info: ShellInfo, sub: ShellInfo) -> None:
    if sub.deny:
        info.deny = sub.deny
    for r in sub.risky:
        info.mark(r)
    if not sub.readonly:
        info.readonly = False
    info.commands += sub.commands
    info.writes += sub.writes


def _simple(toks: list[str], cwd: str, info: ShellInfo, depth: int, pipe_from: bool = False) -> None:
    # redirections: pull them out, judge their targets
    args: list[str] = []
    i = 0
    while i < len(toks):
        t = toks[i]
        if t in REDIR or (t.endswith(">") and t.rstrip(">").isdigit()):
            target = toks[i + 1] if i + 1 < len(toks) else ""
            i += 2
            if t == ">&" or target.startswith("&") or target.isdigit():
                continue
            if target in ("/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty"):
                continue
            p = resolve(target, cwd)
            info.readonly = False
            info.writes.append(p)
            if is_protected(p):
                info.mark(f"writes {target}")
            continue
        if t in ("<", "<<", "<<<", "<&"):
            i += 2
            continue
        args.append(t)
        i += 1

    # env assignments, wrappers, shell keywords
    while args and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", args[0]) or args[0] in KEYWORDS):
        args = args[1:]
    while args and os.path.basename(args[0]) in WRAPPERS:
        w = os.path.basename(args[0])
        args = args[1:]
        while args and (args[0].startswith("-") or re.match(r"^[A-Za-z_]\w*=", args[0])
                        or (w in ("nice", "ionice", "flock") and args[0].isdigit())):
            args = args[1:]
    if args and os.path.basename(args[0]) == "timeout":
        args = args[1:]
        while args and (args[0].startswith("-") or re.match(r"^\d", args[0])):
            args = args[1:]
    if not args:
        return
    if args[0] == "for" or args[0] == "select" or args[0] == "function" or args[0].endswith("()"):
        return
    info.commands.append(args)
    base = os.path.basename(args[0])
    rest = args[1:]
    flags = [a for a in rest if a.startswith("-")]
    operands = [a for a in rest if not a.startswith("-")]

    def ro_unless(cond: bool, why: str) -> None:
        if cond:
            info.mark(why)

    def paths_outside_scratch(ps: list[str]) -> list[str]:
        outs = []
        for a in ps:
            if a == "__SUBST__" or "$" in a:
                outs.append(a)
                continue
            if not is_scratch(resolve(a, cwd)):
                outs.append(a)
        return outs

    recursive = any(re.match(r"^-[a-zA-Z]*[rR]", f) or f in ("--recursive",) for f in flags)

    if base in SHELLS:
        if "-c" in rest:
            j = rest.index("-c")
            if j + 1 < len(rest):
                _merge(info, analyze_shell(rest[j + 1], cwd, depth + 1))
                return
        if pipe_from and not operands:
            info.mark("pipes output into a shell")
        info.readonly = False  # runs a script file: can't see inside
        return
    if base == "eval":
        _merge(info, analyze_shell(" ".join(rest), cwd, depth + 1))
        return
    if base in INTERPRETERS or re.match(r"^python3?\.\d+$", base):
        info.readonly = False
        if pipe_from and (not operands or operands == ["-"]):
            info.mark(f"pipes output into {base}")
        code = " ".join(rest)
        if RISKY_CODE_RX.search(code) and any(f in ("-c", "-e", "-E", "--eval", "-r") for f in flags):
            info.mark(f"inline {base} code that deletes, runs commands or sends data")
        return
    if base == "xargs":
        k = 1
        while k < len(args) and args[k].startswith("-"):
            k += 1 + (1 if args[k] in ("-I", "-n", "-P", "-d", "-L", "-s") else 0)
        if k < len(args):
            _simple(args[k:] + ["__SUBST__"], cwd, info, depth)
        return

    if base in ("rm", "rmdir", "unlink", "shred", "srm"):
        info.readonly = False
        if base == "rm" and (recursive or any("f" in f for f in flags if not f.startswith("--"))):
            for a in operands:
                if is_catastrophic(a, cwd):
                    info.deny = "deletes / or your home"
                    return
        outs = paths_outside_scratch(operands)
        ro_unless(bool(outs) or not operands, f"deletes {' '.join(outs[:3]) or 'files'}")
        return
    if base in ("mv", "chmod", "chown", "chgrp", "truncate", "chattr"):
        info.readonly = False
        targets = operands[1:] if base in ("chmod", "chown", "chgrp") else operands
        outs = paths_outside_scratch(targets)
        if base == "mv" and outs:
            info.mark(f"moves {' '.join(outs[:3])}")
        elif outs:
            info.mark(f"{base} on {' '.join(outs[:3])}")
        return
    if base in ("cp", "ln", "install", "rsync"):
        info.readonly = False
        if base == "rsync" and any(f.startswith("--delete") or f == "--remove-source-files" for f in flags):
            info.mark("rsync that deletes")
        if operands:
            dest = resolve(operands[-1], cwd)
            info.writes.append(dest)
            if is_protected(dest):
                info.mark(f"{base} into {operands[-1]}")
            if base == "rsync" and ":" in operands[-1]:
                info.mark("rsync to a remote host")
        return
    if base == "dd":
        info.readonly = False
        for a in rest:
            if a.startswith("of="):
                p = resolve(a[3:], cwd)
                if not is_scratch(p):
                    info.mark(f"dd to {a[3:]}")
        return
    if base == "find":
        if any(f in ("-delete",) for f in rest):
            info.mark("find -delete")
        for k, a in enumerate(rest):
            if a in ("-exec", "-execdir", "-ok", "-okdir") and k + 1 < len(rest):
                end = next((m for m in range(k + 1, len(rest)) if rest[m] in (";", "+", "\\;")), len(rest))
                _simple([x for x in rest[k + 1:end] if x != "{}"] + ["__SUBST__"], cwd, info, depth)
        return
    if base in ("sed", "perl") and any(f.startswith("-i") or f == "--in-place" for f in flags):
        info.readonly = False
        for a in operands[1:]:
            p = resolve(a, cwd)
            info.writes.append(p)
            if is_protected(p):
                info.mark(f"edits {a} in place")
        return
    if base == "tee":
        info.readonly = False
        for a in operands:
            p = resolve(a, cwd)
            info.writes.append(p)
            if is_protected(p):
                info.mark(f"writes {a}")
        return
    if base == "awk" and re.search(r"system\s*\(|print\s*>|\|\s*\"", " ".join(rest)):
        info.mark("awk that runs commands or writes files")
        return
    if base == "git":
        sub = next((a for a in rest if not a.startswith("-")), "")
        if sub in GIT_RISKY:
            if sub == "checkout" and not ({"--", ".", "-f", "--force"} & set(rest)) and "-b" in rest:
                info.readonly = False
                return
            info.mark(f"git {sub}")
        elif sub == "branch" and {"-D", "-d", "--delete", "-M", "-m", "-f"} & set(rest):
            info.mark("git branch delete/rename")
        elif sub == "stash" and {"drop", "clear", "pop"} & set(rest):
            info.mark("git stash drop")
        elif sub == "tag" and {"-d", "--delete"} & set(rest):
            info.mark("git tag delete")
        elif sub == "push" or "--force" in rest:
            info.mark("git push")
        elif sub not in GIT_READ:
            info.readonly = False
        elif sub in ("config",) and not ({"--get", "--list", "-l", "--get-all"} & set(rest)):
            info.readonly = False
        elif sub in ("branch", "tag", "worktree", "stash", "remote") and len(operands) > 1:
            info.readonly = False
        return
    if base in ("kill", "pkill", "killall", "xkill"):
        info.mark(f"{base} stops processes")
        return
    if base == "systemctl":
        sub = next((a for a in rest if not a.startswith("-")), "")
        if sub and sub not in SYSTEMCTL_READ:
            info.mark(f"systemctl {sub}")
        return
    if base in ("shutdown", "reboot", "poweroff", "halt", "suspend", "hibernate"):
        info.mark(f"{base}")
        return
    if base == "loginctl":
        sub = next((a for a in rest if not a.startswith("-")), "")
        if sub.startswith(("terminate", "kill", "lock", "poweroff", "reboot", "suspend")):
            info.mark(f"loginctl {sub}")
        elif sub not in ("", "list-sessions", "show-session", "session-status", "show-user", "list-users",
                         "user-status"):
            info.readonly = False
        return
    if base == "hyprctl":
        sub = next((a for a in rest if not a.startswith("-")), "")
        if sub in HYPRCTL_RISKY:
            info.mark(f"hyprctl {sub} changes your session")
        return
    if base in ("pacman", "yay", "paru", "pamac"):
        if any(re.match(r"^-[A-Za-z]*[SRUD]", f) and not re.match(r"^-S[si]", f) for f in flags) or \
                any(f.startswith("--") and f[2:] in ("sync", "remove", "upgrade", "database") for f in flags):
            if not any(re.match(r"^-S[A-Za-z]*[si]", f) for f in flags):
                info.mark(f"{base} installs or removes packages")
                return
        if not flags and base in ("yay", "paru"):
            info.mark(f"{base} upgrades the system")
        return
    if base in ("pip", "pip3", "pipx", "uv", "npm", "pnpm", "yarn", "bun", "cargo", "go", "gem", "flatpak",
                "snap", "brew"):
        sub = next((a for a in rest if not a.startswith("-")), "")
        global_flag = any(f in ("-g", "--global", "--system", "--user", "--break-system-packages") for f in flags)
        if base in ("pip", "pip3") and sub in ("install", "uninstall", "remove"):
            info.mark(f"{base} {sub}")
        elif base == "uv" and sub == "pip" and len(operands) > 1 and operands[1] in ("install", "uninstall"):
            info.mark(f"uv pip {operands[1]}")
        elif base == "uv" and sub == "tool" and len(operands) > 1 and operands[1] in ("install", "uninstall"):
            info.mark(f"uv tool {operands[1]}")
        elif base in ("npm", "pnpm", "yarn", "bun") and global_flag and sub in ("install", "i", "add", "remove",
                                                                                    "uninstall", "rm"):
            info.mark(f"{base} global {sub}")
        elif base in ("cargo", "go", "gem", "pipx") and sub in ("install", "uninstall"):
            info.mark(f"{base} {sub}")
        elif base in ("flatpak", "snap", "brew") and sub in ("install", "uninstall", "remove", "update", "upgrade"):
            info.mark(f"{base} {sub}")
        elif sub not in ("list", "show", "search", "info", "view", "ls", "outdated", "--version", "help", "freeze",
                         "config", "why", "tree", "run"):
            info.readonly = False
        return
    if base in ("curl", "wget", "http", "xh"):
        joined = " ".join(rest)
        sends = re.search(r"(^|\s)(-X\s*(POST|PUT|DELETE|PATCH)|-d\b|--data\S*|-F\b|--form\S*|-T\b|"
                          r"--upload-file|--post-data|--post-file|--method=(POST|PUT|DELETE|PATCH))", joined)
        if sends:
            info.mark(f"{base} sends data")
        if base == "wget" or any(f in ("-o", "-O", "--output", "--remote-name", "-OJ") for f in flags):
            info.readonly = False
        return
    if base in ("ssh", "scp", "sftp", "mosh", "telnet", "nc", "ncat", "socat"):
        info.mark(f"{base} to another machine")
        return
    if base in ("crontab", "at", "batch"):
        info.mark(f"{base} schedules jobs")
        return
    if base in ("docker", "podman"):
        sub = next((a for a in rest if not a.startswith("-")), "")
        if sub in ("rm", "rmi", "prune", "kill", "stop", "system", "volume", "network", "image", "container",
                   "compose"):
            if sub in ("rm", "rmi", "prune", "kill", "stop") or re.search(r"\b(rm|prune|down|kill|stop)\b",
                                                                       " ".join(rest)):
                info.mark(f"{base} {sub}")
                return
        if sub not in ("ps", "images", "inspect", "logs", "version", "info", "stats", "top"):
            info.readonly = False
        return
    if base == "gh":
        if GH_RISKY.search(" ".join(rest[:3])) or re.search(r"-X\s*(POST|PUT|DELETE|PATCH)|--method\s+(POST|PUT|"
                                                              r"DELETE|PATCH)", " ".join(rest)):
            info.mark("gh changes something on GitHub")
        return
    if base in ("mount", "umount", "swapon", "swapoff", "fdisk", "parted", "gdisk", "sgdisk", "cryptsetup",
                "losetup", "mkswap", "useradd", "userdel", "usermod", "passwd", "chsh", "chpasswd", "visudo",
                "modprobe", "rmmod", "insmod", "sysctl", "grub-install", "mkinitcpio", "bootctl", "efibootmgr"):
        info.mark(f"{base} changes the system")
        return
    if base == "swaymsg" or base == "grim":
        info.readonly = False if base == "swaymsg" and rest and not rest[0].startswith("-t") else info.readonly
        return
    if base == "qs":
        if "ipc" in rest and "call" in rest:
            info.readonly = False
        return
    if base == "secret-tool":
        if rest and rest[0] in ("store", "clear"):
            info.mark(f"secret-tool {rest[0]}")
        return
    if base in ("trash-put", "trash", "gio") and (base != "gio" or (rest and rest[0] in ("trash", "remove", "rm"))):
        info.readonly = False
        if base == "gio" and rest and rest[0] in ("remove", "rm"):
            info.mark("gio remove")
        return
    if base in READONLY:
        return
    info.readonly = False


# ---- rules ---------------------------------------------------------------------------------------

def load_rules() -> tuple[list[str], list[str]]:
    try:
        d = tomllib.loads(paths.PERMISSIONS_TOML.read_text())
    except (OSError, tomllib.TOMLDecodeError):
        return [], []
    return list(d.get("allow", [])), list(d.get("deny", []))


def save_allow_rule(rule: str) -> None:
    allow, deny = load_rules()
    if rule in allow:
        return
    allow.append(rule)
    paths.PERMISSIONS_TOML.parent.mkdir(parents=True, exist_ok=True)
    def q(xs):
        return "[\n" + "".join(f"    {_toml_str(x)},\n" for x in xs) + "]"
    paths.PERMISSIONS_TOML.write_text(
        "# rury agent permission rules. allow clears an ordinary ask (risky ones always ask); deny refuses.\n"
        "# Bash(prefix:*)  Bash(exact command)  Write(~/glob/**)  tool_name_glob\n"
        f"allow = {q(allow)}\ndeny = {q(deny)}\n")


def _toml_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


_RULE = re.compile(r"^(\w+)\((.*)\)$")


def _cmd_matches(rule_body: str, simple: list[str]) -> bool:
    text = " ".join(simple)
    if rule_body.endswith(":*"):
        prefix = rule_body[:-2].strip()
        return text == prefix or text.startswith(prefix + " ")
    return text == rule_body.strip()


def rule_allows_shell(rules: list[str], info: ShellInfo) -> bool:
    bodies = [m.group(2) for r in rules if (m := _RULE.match(r)) and m.group(1) == "Bash"]
    if not bodies or not info.commands:
        return False
    return all(any(_cmd_matches(b, c) for b in bodies) for c in info.commands)


def rule_matches_path(rules: list[str], kinds: tuple[str, ...], path: str) -> bool:
    for r in rules:
        m = _RULE.match(r)
        if m and m.group(1) in kinds:
            pat = _x(m.group(2))
            if fnmatch.fnmatch(path, pat) or (pat.endswith("/**") and _under(path, pat[:-3])):
                return True
    return False


def rule_matches_tool(rules: list[str], name: str) -> bool:
    return any(not _RULE.match(r) and fnmatch.fnmatch(name, r) for r in rules)


def suggest_shell_rule(info: ShellInfo) -> str:
    for c in info.commands:
        if len(c) >= 2 and not c[1].startswith("-"):
            return f"Bash({c[0]} {c[1]}:*)"
        if c:
            return f"Bash({c[0]}:*)"
    return ""


# ---- the gate ------------------------------------------------------------------------------------

READ_KINDS = {"read", "meta"}
MCP_READ = re.compile(r"(^|_)(get|list|read|search|fetch|find|query|snapshot|show|describe|status|info|"
                      r"take_screenshot|screenshot|console|network_requests|tabs)(_|$)", re.I)
# risky even on the agent's own desk: these run code on this machine or send Atif's files somewhere
MCP_HOST_RISKY = re.compile(r"(unsafe|run_code|evaluate|file_upload|(^|_)exec(ute)?(_|$)|shell|terminal)", re.I)
MCP_RISKY = re.compile(r"(^|_)(delete|remove|drop|destroy|send|post|publish|purchase|pay|buy|transfer|"
                       r"kill|terminate|truncate|wipe|reset|merge|deploy|install|uninstall|execute|exec|"
                       r"run_code|evaluate)(_|$)", re.I)


@dataclass
class Gate:
    mode: str
    cwd: str
    allow: list[str] = field(default_factory=list)
    deny: list[str] = field(default_factory=list)
    session_allow: list[str] = field(default_factory=list)
    desk_servers: list[str] = field(default_factory=list)

    @property
    def rules(self) -> list[str]:
        return self.allow + self.session_allow

    def check(self, name: str, kind: str, args: dict) -> Verdict:
        mode = self.mode
        if mode == "chat":
            return Verdict("block", reason="chat mode has no tools")
        if rule_matches_tool(self.deny, name):
            return Verdict("deny", reason="denied by a rule in permissions.toml")

        if kind in READ_KINDS:
            return Verdict("allow")

        # Risky actions ask in every mode and no saved rule skips that, so their cards never offer
        # "always allow" (rule=""): one click must not turn into a standing permission to delete or push.
        if kind == "risky":  # tools that always ask (schedule, ...)
            if mode == "plan":
                return Verdict("block", reason="plan mode is read-only; put it in the plan and call exit_plan")
            return Verdict("ask", risky=True, reason=f"{name} always asks")

        if kind == "desk":
            if mode == "plan":
                return Verdict("block", reason="plan mode only looks at the desk; call exit_plan first")
            return Verdict("allow")

        if kind == "write":
            p = resolve(str(args.get("path", "")), self.cwd)
            if rule_matches_path(self.deny, ("Write", "Edit"), p):
                return Verdict("deny", reason="denied by a rule in permissions.toml")
            if mode == "plan":
                return Verdict("block", reason="plan mode is read-only; put the change in the plan and call exit_plan")
            if is_scratch(p):
                return Verdict("allow")
            if is_protected(p):
                return Verdict("ask", risky=True, reason=f"writes inside {os.path.dirname(p)}")
            if rule_matches_path(self.rules, ("Write", "Edit"), p):
                return Verdict("allow")
            if mode == "ask":
                return Verdict("ask", reason=f"writes {p}", rule=write_rule(p))
            return Verdict("allow")

        if kind == "exec":
            cmd = str(args.get("command", ""))
            info = analyze_shell(cmd, str(args.get("cwd") or self.cwd))
            if info.deny:
                handoff = cmd if info.deny == "needs root" else ""
                return Verdict("deny", reason=info.deny, handoff=handoff)
            denied = [m.group(2) for r in self.deny if (m := _RULE.match(r)) and m.group(1) == "Bash"]
            if any(_cmd_matches(b, c) for b in denied for c in info.commands):
                return Verdict("deny", reason="denied by a rule in permissions.toml")
            if mode == "plan":
                if info.readonly and not info.risky:
                    return Verdict("allow")
                return Verdict("block", reason="plan mode runs read-only commands only; call exit_plan with the plan")
            if info.risky:
                return Verdict("ask", risky=True, reason="; ".join(info.risky))
            if rule_allows_shell(self.rules, info):
                return Verdict("allow")
            if mode == "ask" and not info.readonly:
                return Verdict("ask", reason="runs a command that may change things", rule=suggest_shell_rule(info))
            return Verdict("allow")

        if kind == "mcp":
            server = name.split("__")[1] if name.count("__") >= 2 else ""
            short = name.split("__")[-1]
            looks_read = bool(MCP_READ.search(short))
            if mode == "plan":
                return Verdict("allow") if looks_read else Verdict(
                    "block", reason="plan mode only uses read-only tools; call exit_plan with the plan")
            if MCP_HOST_RISKY.search(short):
                return Verdict("ask", risky=True, reason=f"{short} runs code on this computer or uploads files")
            if MCP_RISKY.search(short) and server not in self.desk_servers:
                return Verdict("ask", risky=True, reason=f"{short} may delete, send or run things")
            if server in self.desk_servers or looks_read or rule_matches_tool(self.rules, name):
                return Verdict("allow")
            if mode == "ask":
                return Verdict("ask", reason=f"MCP tool {short}", rule=name)
            return Verdict("allow")

        # unknown kind: be careful
        if mode == "plan":
            return Verdict("block", reason="plan mode is read-only")
        return Verdict("ask", reason=f"{name}", rule=name)
