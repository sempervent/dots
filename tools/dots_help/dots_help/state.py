"""Quick local machine state for dots-help (no brew outdated / network)."""

from __future__ import annotations

import os
import platform
import shutil
import socket
from dataclasses import dataclass, field
from pathlib import Path

from .registry import Registry


def _read_kv_file(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # support KEY=VAL and shell : "${KEY:=val}"
        if line.startswith(": "):
            continue
        if "=" in line:
            k, _, v = line.partition("=")
            k = k.strip().removeprefix("export ").strip()
            v = v.strip().strip("'").strip('"')
            if k:
                out[k] = v
    return out


@dataclass
class MachineState:
    version: str = "unknown"
    host: str = ""
    os_name: str = ""
    arch: str = ""
    shell: str = ""
    profile: str = ""
    profile_file: str = ""
    multiplexer: str = ""
    package_groups: str = ""
    active_components: list[str] = field(default_factory=list)
    backup_latest: str = ""
    backup_count: int = 0
    legacy_old_dots: bool = False
    fzf: bool = False
    fd: bool = False
    fzf_tab: bool = False
    textual_ok: bool = True
    home: Path = field(default_factory=lambda: Path.home())
    dots_root: Path = field(default_factory=Path)

    def mark(self, ok: bool) -> str:
        return "✓" if ok else "×"


def gather_state(reg: Registry | None = None) -> MachineState:
    reg = reg or Registry()
    home = Path(os.environ.get("HOME", str(Path.home()))).expanduser()
    st = MachineState(
        version=reg.version(),
        host=socket.gethostname().split(".")[0],
        os_name=platform.system(),
        arch=platform.machine(),
        shell=os.environ.get("DOTS_SHELL")
        or Path(os.environ.get("SHELL", "")).name
        or "unknown",
        home=home,
        dots_root=reg.root,
    )

    active = home / ".config" / "dots" / "active-profile"
    runtime = home / ".config" / "dots" / "runtime.env"
    kv = _read_kv_file(active)
    kv.update(_read_kv_file(runtime))
    # Prefer already-exported env (status/check shells) over file defaults
    st.profile = os.environ.get("DOTS_PROFILE") or kv.get("DOTS_PROFILE") or kv.get("DOTS_ACTIVE_PROFILE") or ""
    st.profile_file = kv.get("DOTS_PROFILE_FILE") or kv.get("DOTS_ACTIVE_PROFILE_FILE") or ""
    st.multiplexer = os.environ.get("DOTS_MULTIPLEXER") or kv.get("DOTS_MULTIPLEXER") or ""
    st.package_groups = os.environ.get("DOTS_PACKAGE_GROUPS") or kv.get("DOTS_PACKAGE_GROUPS") or ""
    comps = os.environ.get("DOTS_ACTIVE_COMPONENTS") or kv.get("DOTS_ACTIVE_COMPONENTS") or kv.get("DOTS_LAST_WITH_INFO") or ""
    st.active_components = [c for c in comps.replace(",", " ").split() if c]

    backups = home / ".local" / "state" / "dots" / "backups"
    if backups.is_dir():
        snaps = sorted([p for p in backups.iterdir() if p.is_dir()], key=lambda p: p.name)
        st.backup_count = len(snaps)
        if snaps:
            st.backup_latest = snaps[-1].name
    legacy = home / ".old_dots"
    st.legacy_old_dots = legacy.is_dir() and any(legacy.iterdir())

    st.fzf = shutil.which("fzf") is not None
    st.fd = shutil.which("fd") is not None or shutil.which("fdfind") is not None
    zsh_custom = Path(
        os.environ.get(
            "ZSH_CUSTOM",
            str(Path(os.environ.get("ZSH", str(home / ".oh-my-zsh"))) / "custom"),
        )
    )
    st.fzf_tab = (zsh_custom / "plugins" / "fzf-tab" / "fzf-tab.plugin.zsh").is_file()

    return st


def component_selected(st: MachineState, component_id: str) -> bool:
    return component_id in st.active_components


def platform_ok(platforms: list[str] | None, os_name: str) -> bool:
    if not platforms:
        return True
    key = "darwin" if os_name == "Darwin" else "linux" if os_name == "Linux" else os_name.lower()
    return key in [p.lower() for p in platforms]
