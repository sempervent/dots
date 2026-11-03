"""Terminal provider selection — Herdr preferred, tmux fallback."""

from __future__ import annotations

import shutil
from typing import Any


def preferred_provider(*, herdr_ok: bool | None = None) -> str:
    if herdr_ok is None:
        herdr_ok = shutil.which("herdr") is not None
    return "herdr" if herdr_ok else "tmux"


def herdr_session_name(rig: str, *, prefix: str = "openrig") -> str:
    """Stable named Herdr session — avoid endless duplicates."""
    safe = "".join(c if c.isalnum() or c in "-_" else "-" for c in rig)
    if safe.startswith(f"{prefix}-"):
        return safe
    return f"{prefix}-{safe}"


def open_view_command(
    *,
    target: str = "saved:kernel",
    provider: str | None = None,
    window: bool = False,
) -> list[str]:
    """Current OpenRig CLI: rig terminal open <target> [--provider] [--window]."""
    prov = provider or preferred_provider()
    cmd = ["rig", "terminal", "open", target, "--provider", prov]
    if window:
        cmd.append("--window")
    return cmd


def terminal_status_report() -> dict[str, Any]:
    herdr = shutil.which("herdr") is not None
    return {
        "preferred": preferred_provider(herdr_ok=herdr),
        "fallback": "tmux",
        "herdr_installed": herdr,
        "tmux_installed": shutil.which("tmux") is not None,
    }
