"""Thin wrappers around OpenRig queue/messages — OpenRig remains authoritative."""

from __future__ import annotations

import json
import shutil
import subprocess
from typing import Any


def _rig(*args: str, timeout: float = 30.0) -> tuple[int, str]:
    if not shutil.which("rig"):
        return 127, "rig not installed"
    try:
        proc = subprocess.run(
            ["rig", *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return proc.returncode, ((proc.stdout or "") + (proc.stderr or "")).strip()
    except subprocess.TimeoutExpired:
        return 124, "timeout"


def list_tasks(*, destination: str | None = None, json_mode: bool = False) -> dict[str, Any]:
    args = ["queue", "list"]
    if destination:
        args.extend(["--destination", destination])
    if json_mode:
        args.append("--json")
    code, out = _rig(*args)
    return {"ok": code == 0, "exit": code, "output": out}


def create_task(*, destination: str, text: str) -> dict[str, Any]:
    # Prefer send to lead; queue create when available
    code, out = _rig("queue", "create", "--destination", destination, text)
    if code == 127 or "unknown" in out.lower():
        code, out = _rig("send", destination, text)
    return {"ok": code == 0, "exit": code, "output": out}


def list_messages(*, limit: int = 20) -> dict[str, Any]:
    code, out = _rig("stream", "--limit", str(limit))
    if code != 0:
        code, out = _rig("ps")
    return {"ok": code == 0, "exit": code, "output": out}


def restore_check(target: str | None = None) -> dict[str, Any]:
    args = ["restore-check"]
    if target:
        args.append(target)
    code, out = _rig(*args)
    # Classify coarsely from exit/output
    state = "unknown"
    low = out.lower()
    if code == 0 and ("ok" in low or "recoverable" in low or out):
        state = "recoverable"
    if "degraded" in low:
        state = "degraded"
    if "missing" in low or "blocked" in low:
        state = "blocked"
    if code == 127:
        state = "unavailable"
    return {"ok": code == 0, "exit": code, "state": state, "output": out}


def parse_queue_table(output: str) -> list[dict[str, str]]:
    """Best-effort parse of `rig queue list` text for DOTS display."""
    rows: list[dict[str, str]] = []
    for line in output.splitlines():
        line = line.strip()
        if not line or line.lower().startswith("task"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        # Heuristic: last token state, second-to-last owner-ish
        state = parts[-1]
        owner = parts[-2] if len(parts) >= 3 else "—"
        task = " ".join(parts[:-2]) if len(parts) > 2 else parts[0]
        rows.append({"task": task, "owner": owner, "state": state})
    return rows
