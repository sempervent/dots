"""Record routing + execution events (never raises; never stores prompt/response bodies)."""

from __future__ import annotations

import hashlib
import json
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .config import load_config, privacy, telemetry_enabled
from .db import connect
from . import resources


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _safe(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except Exception:
        return None


def project_id_from_cwd(cwd: str | Path | None, *, store_full_paths: bool = False) -> str | None:
    if not cwd:
        return None
    try:
        p = Path(cwd).expanduser().resolve()
    except Exception:
        return None
    if store_full_paths:
        # Still hash — never store raw absolute path in project_id column
        digest = hashlib.sha256(str(p).encode()).hexdigest()[:16]
        return f"{p.name}:{digest}"
    digest = hashlib.sha256(str(p).encode()).hexdigest()[:16]
    return f"{p.name}:{digest}"


def classify_local_or_cloud(backend: str | None, model: str | None = None) -> str:
    b = (backend or "").lower()
    m = (model or "").lower()
    if b in {"codex", "cursor"}:
        return "cloud"
    if b in {"opencode", "hermes", "hermes_direct", "local", "ollama", "drawthings", "archify", "images"}:
        if m.startswith("ollama/") or "ollama" in m:
            return "local"
        if b in {"codex", "cursor"}:
            return "cloud"
        return "local"
    if "ollama" in m:
        return "local"
    return "unknown"


def record_route(
    *,
    category: str,
    destination: str,
    reason: str,
    user_override: bool = False,
    degraded: bool = False,
    escalation: str | None = None,
    available: list[str] | set[str] | None = None,
    note: str | None = None,
    session_id: str | None = None,
) -> str | None:
    """Insert a routing_events row. Returns event id or None."""
    if not telemetry_enabled():
        return None

    def _do() -> str | None:
        cfg = load_config()
        con = connect()
        if con is None:
            return None
        eid = str(uuid.uuid4())
        try:
            avail_json = None
            if available is not None:
                avail_json = json.dumps(sorted(list(available)), separators=(",", ":"))
            con.execute(
                """
                INSERT INTO routing_events(
                  id, timestamp, session_id, category, destination, reason,
                  user_override, degraded, escalation, available_json, note
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?)
                """,
                (
                    eid,
                    _now(),
                    session_id,
                    category,
                    destination,
                    reason,
                    1 if user_override else 0,
                    1 if degraded else 0,
                    escalation,
                    avail_json,
                    note,
                ),
            )
            _maybe_prune(con, cfg)
            return eid
        finally:
            con.close()

    return _safe(_do)


def start_execution(
    *,
    backend: str,
    task_kind: str | None = None,
    task_label: str | None = None,
    model: str | None = None,
    provider: str | None = None,
    agent: str | None = None,
    tool: str | None = None,
    cwd: str | None = None,
    route_category: str | None = None,
    route_destination: str | None = None,
    route_reason: str | None = None,
    user_override: bool = False,
    session_id: str | None = None,
    parent_id: str | None = None,
    local_or_cloud: str | None = None,
    metadata: dict[str, Any] | None = None,
    capture_resources: bool | None = None,
) -> str | None:
    """Begin an execution row (status=running). Returns execution id."""
    if not telemetry_enabled():
        return None

    def _do() -> str | None:
        cfg = load_config()
        priv = privacy(cfg)
        con = connect()
        if con is None:
            return None
        eid = str(uuid.uuid4())
        want_res = (
            capture_resources
            if capture_resources is not None
            else bool(cfg.get("capture_resource_usage", True))
        )
        want_ollama = bool(cfg.get("capture_ollama_state", True)) and backend in {
            "opencode",
            "hermes",
            "local",
            "drawthings",
            "ollama",
        }
        snap = resources.snapshot(want_ollama=want_ollama) if want_res else {}
        loc = local_or_cloud or classify_local_or_cloud(backend, model)
        # Strip any accidental text keys from metadata
        meta = dict(metadata or {})
        for bad in ("prompt", "response", "output", "stderr", "stdout", "env"):
            meta.pop(bad, None)
        try:
            con.execute(
                """
                INSERT INTO executions(
                  id, timestamp_start, session_id, parent_id,
                  task_kind, task_label, route_category, route_destination, route_reason,
                  user_override, backend, provider, model, local_or_cloud, agent, tool,
                  project_id, result_status, status,
                  memory_pressure_before, swap_pages_before, ollama_models_before,
                  drawthings_active, metadata_json
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                (
                    eid,
                    _now(),
                    session_id,
                    parent_id,
                    task_kind,
                    task_label,
                    route_category,
                    route_destination,
                    route_reason,
                    1 if user_override else 0,
                    backend,
                    provider,
                    model,
                    loc,
                    agent,
                    tool,
                    project_id_from_cwd(cwd, store_full_paths=bool(priv.get("store_full_paths"))),
                    "running",
                    "running",
                    snap.get("memory_pressure"),
                    snap.get("swap_pages"),
                    snap.get("ollama_models"),
                    1 if snap.get("drawthings_active") else (0 if snap.get("drawthings_active") is False else None),
                    json.dumps(meta, separators=(",", ":")) if meta else None,
                ),
            )
            return eid
        finally:
            con.close()

    return _safe(_do)


def finish_execution(
    execution_id: str | None,
    *,
    success: bool | None = None,
    result_status: str | None = None,
    exit_code: int | None = None,
    timed_out: bool = False,
    model: str | None = None,
    input_tokens: int | None = None,
    output_tokens: int | None = None,
    total_tokens: int | None = None,
    reported_cost_usd: float | None = None,
    estimated_cost_usd: float | None = None,
    escalated: bool = False,
    escalation_from: str | None = None,
    escalation_to: str | None = None,
    escalation_reason: str | None = None,
    metadata_update: dict[str, Any] | None = None,
    capture_resources: bool | None = None,
) -> bool:
    if not execution_id or not telemetry_enabled():
        return False

    def _do() -> bool:
        cfg = load_config()
        con = connect()
        if con is None:
            return False
        want_res = (
            capture_resources
            if capture_resources is not None
            else bool(cfg.get("capture_resource_usage", True))
        )
        snap = resources.snapshot(want_ollama=bool(cfg.get("capture_ollama_state", True))) if want_res else {}
        if result_status is None:
            if timed_out:
                result_status_v = "timeout"
            elif success is True:
                result_status_v = "success"
            elif success is False:
                result_status_v = "failure"
            else:
                result_status_v = "error"
        else:
            result_status_v = result_status
        success_i = None if success is None else (1 if success else 0)
        # duration
        row = con.execute(
            "SELECT timestamp_start, metadata_json FROM executions WHERE id=?",
            (execution_id,),
        ).fetchone()
        if not row:
            return False
        duration_ms = None
        try:
            start = datetime.fromisoformat(row["timestamp_start"].replace("Z", "+00:00"))
            duration_ms = int((datetime.now(timezone.utc) - start).total_seconds() * 1000)
        except Exception:
            pass
        meta = {}
        if row["metadata_json"]:
            try:
                meta = json.loads(row["metadata_json"])
            except Exception:
                meta = {}
        if metadata_update:
            for k, v in metadata_update.items():
                if k not in {"prompt", "response", "output", "stderr", "stdout", "env"}:
                    meta[k] = v
        capture_cost = bool(cfg.get("capture_cost", True))
        con.execute(
            """
            UPDATE executions SET
              timestamp_end=?, duration_ms=?, success=?, result_status=?, exit_code=?,
              timed_out=?, model=COALESCE(?, model),
              input_tokens=?, output_tokens=?, total_tokens=?,
              reported_cost_usd=?, estimated_cost_usd=?,
              escalated=?, escalation_from=?, escalation_to=?, escalation_reason=?,
              memory_pressure_after=?, swap_pages_after=?, ollama_models_after=?,
              drawthings_active=COALESCE(?, drawthings_active),
              metadata_json=?, status='completed'
            WHERE id=?
            """,
            (
                _now(),
                duration_ms,
                success_i,
                result_status_v,
                exit_code,
                1 if timed_out else 0,
                model,
                input_tokens if capture_cost else None,
                output_tokens if capture_cost else None,
                total_tokens if capture_cost else None,
                reported_cost_usd if capture_cost else None,
                estimated_cost_usd if capture_cost else None,
                1 if escalated else 0,
                escalation_from,
                escalation_to,
                escalation_reason,
                snap.get("memory_pressure"),
                snap.get("swap_pages"),
                snap.get("ollama_models"),
                1 if snap.get("drawthings_active") else (0 if snap.get("drawthings_active") is False else None),
                json.dumps(meta, separators=(",", ":")) if meta else None,
                execution_id,
            ),
        )
        _maybe_prune(con, cfg)
        con.close()
        return True

    return bool(_safe(_do))


def record_escalation(
    execution_id: str | None,
    *,
    from_backend: str,
    to_backend: str,
    reason: str,
) -> bool:
    """Mark escalation on an in-flight or completed execution (does not finish it)."""
    if not execution_id or not telemetry_enabled():
        return False

    def _do() -> bool:
        con = connect()
        if con is None:
            return False
        try:
            con.execute(
                """
                UPDATE executions SET
                  escalated=1,
                  escalation_from=?,
                  escalation_to=?,
                  escalation_reason=?
                WHERE id=?
                """,
                (from_backend, to_backend, reason, execution_id),
            )
            return True
        finally:
            con.close()

    return bool(_safe(_do))


def _maybe_prune(con, cfg: dict[str, Any]) -> None:
    days = int(cfg.get("retention_days") or 90)
    if days <= 0:
        return
    if (uuid.uuid4().int % 100) != 0:
        return
    from datetime import timedelta

    cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat(
        timespec="milliseconds"
    ).replace("+00:00", "Z")
    con.execute("DELETE FROM executions WHERE timestamp_start < ?", (cutoff,))
    con.execute("DELETE FROM routing_events WHERE timestamp < ?", (cutoff,))


def prune(days: int | None = None) -> dict[str, int]:
    cfg = load_config()
    d = int(days if days is not None else cfg.get("retention_days") or 90)

    def _do() -> dict[str, int]:
        from datetime import timedelta

        con = connect()
        if con is None:
            return {"executions": 0, "routing_events": 0}
        cutoff = (datetime.now(timezone.utc) - timedelta(days=d)).isoformat(
            timespec="milliseconds"
        ).replace("+00:00", "Z")
        try:
            cur1 = con.execute("DELETE FROM executions WHERE timestamp_start < ?", (cutoff,))
            cur2 = con.execute("DELETE FROM routing_events WHERE timestamp < ?", (cutoff,))
            return {"executions": cur1.rowcount, "routing_events": cur2.rowcount}
        finally:
            con.close()

    return _safe(_do) or {"executions": 0, "routing_events": 0}


def reset_database() -> bool:
    """Delete SQLite file(s). Opt-in destructive."""

    def _do() -> bool:
        from .config import db_path as _db

        path = _db()
        for p in (path, Path(str(path) + "-wal"), Path(str(path) + "-shm")):
            if p.is_file():
                p.unlink()
        return True

    return bool(_safe(_do))
