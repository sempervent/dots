"""Cheap local resource / Ollama snapshots (no sudo)."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from typing import Any


def memory_pressure_level() -> str | None:
    if shutil.which("memory_pressure") is None:
        return None
    try:
        proc = subprocess.run(
            ["memory_pressure"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        text = (proc.stdout or "") + "\n" + (proc.stderr or "")
        m = re.search(r"System-wide memory free percentage:\s*(\d+)", text)
        # Also "Pages free" style — prefer free percentage if present
        if m:
            pct = int(m.group(1))
            if pct >= 50:
                return "normal"
            if pct >= 20:
                return "warn"
            return "critical"
        if re.search(r"\bnormal\b", text, re.I):
            return "normal"
        if re.search(r"\bwarn", text, re.I):
            return "warn"
        if re.search(r"\bcritical\b", text, re.I):
            return "critical"
    except Exception:
        return None
    return None


def swap_used_pages() -> int | None:
    """Approximate swap used from vm_stat (pages)."""
    if shutil.which("vm_stat") is None:
        return None
    try:
        proc = subprocess.run(
            ["vm_stat"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        text = proc.stdout or ""
        # "Swapins:" / "Swapouts:" are cumulative; "Pages swapped out:" preferred
        m = re.search(r"Pages swapped out:\s*([\d.]+)", text)
        if m:
            return int(float(m.group(1).rstrip(".")))
        # Fallback: compressed pages as pressure proxy
        m2 = re.search(r"Pages occupied by compressor:\s*([\d.]+)", text)
        if m2:
            return int(float(m2.group(1).rstrip(".")))
    except Exception:
        return None
    return None


def ollama_ps_snapshot() -> str | None:
    """Compact JSON of `ollama ps` (model names only). Never poll continuously."""
    if shutil.which("ollama") is None:
        return None
    try:
        proc = subprocess.run(
            ["ollama", "ps"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if proc.returncode != 0:
            return json.dumps({"ok": False, "models": []})
        lines = [ln for ln in (proc.stdout or "").splitlines() if ln.strip()]
        models: list[dict[str, str]] = []
        # Skip header
        for ln in lines[1:]:
            parts = ln.split()
            if not parts:
                continue
            entry: dict[str, str] = {"model": parts[0]}
            if len(parts) >= 2:
                entry["id"] = parts[1]
            models.append(entry)
        return json.dumps({"ok": True, "models": models}, separators=(",", ":"))
    except Exception:
        return None


def drawthings_likely_active() -> bool | None:
    """Best-effort: Draw Things.app running (macOS)."""
    if os.uname().sysname != "Darwin":
        return None
    try:
        proc = subprocess.run(
            ["pgrep", "-qx", "Draw Things"],
            capture_output=True,
            timeout=2,
            check=False,
        )
        return proc.returncode == 0
    except Exception:
        return None


def snapshot(*, want_ollama: bool = True) -> dict[str, Any]:
    out: dict[str, Any] = {
        "memory_pressure": memory_pressure_level(),
        "swap_pages": swap_used_pages(),
        "drawthings_active": drawthings_likely_active(),
    }
    if want_ollama:
        out["ollama_models"] = ollama_ps_snapshot()
    return out
