"""Import helper for DOTS adapters — never raises."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any


def _ensure_path() -> None:
    root = Path(__file__).resolve().parent
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))


def load():
    try:
        _ensure_path()
        import dots_telemetry as t  # type: ignore

        return t
    except Exception:
        return None


def start(**kwargs: Any) -> str | None:
    mod = load()
    if not mod:
        return None
    try:
        return mod.start_execution(**kwargs)
    except Exception:
        return None


def finish(execution_id: str | None, **kwargs: Any) -> bool:
    mod = load()
    if not mod or not execution_id:
        return False
    try:
        return bool(mod.finish_execution(execution_id, **kwargs))
    except Exception:
        return False


def route(**kwargs: Any) -> str | None:
    mod = load()
    if not mod:
        return None
    try:
        return mod.record_route(**kwargs)
    except Exception:
        return None


def escalate(execution_id: str | None, **kwargs: Any) -> bool:
    mod = load()
    if not mod or not execution_id:
        return False
    try:
        return bool(mod.record_escalation(execution_id, **kwargs))
    except Exception:
        return False
