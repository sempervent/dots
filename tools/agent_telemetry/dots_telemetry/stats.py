"""Read-only aggregation for agent-stats."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from typing import Any

from .config import telemetry_enabled
from .db import connect


def _cutoff(days: int | None) -> str | None:
    if days is None:
        return None
    return (datetime.now(timezone.utc) - timedelta(days=days)).isoformat(
        timespec="milliseconds"
    ).replace("+00:00", "Z")


def stats_summary(
    *,
    days: int | None = None,
    backend: str | None = None,
    failures_only: bool = False,
    escalations_only: bool = False,
) -> dict[str, Any]:
    empty = {
        "enabled": telemetry_enabled(),
        "executions": 0,
        "success_rate": None,
        "local_pct": None,
        "cloud_pct": None,
        "backends": {},
        "routes": {},
        "overrides": 0,
        "escalations": 0,
        "opencode_to_codex": 0,
        "degraded_routes": 0,
        "failures": 0,
        "timeouts": 0,
    }
    if not telemetry_enabled() and connect() is None:
        return empty

    def _do() -> dict[str, Any]:
        con = connect()
        if con is None:
            return empty
        try:
            where = ["status='completed' OR result_status IS NOT NULL"]
            params: list[Any] = []
            cut = _cutoff(days)
            if cut:
                where.append("timestamp_start >= ?")
                params.append(cut)
            if backend:
                where.append("backend = ?")
                params.append(backend)
            if failures_only:
                where.append("success = 0")
            if escalations_only:
                where.append("escalated = 1")
            clause = " AND ".join(where)
            rows = con.execute(
                f"SELECT * FROM executions WHERE {clause}",
                params,
            ).fetchall()
            total = len(rows)
            ok = sum(1 for r in rows if r["success"] == 1)
            local = sum(1 for r in rows if r["local_or_cloud"] == "local")
            cloud = sum(1 for r in rows if r["local_or_cloud"] == "cloud")
            backends: dict[str, int] = {}
            for r in rows:
                b = r["backend"] or "unknown"
                backends[b] = backends.get(b, 0) + 1
            esc = sum(1 for r in rows if r["escalated"] == 1)
            oc = sum(
                1
                for r in rows
                if r["escalated"] == 1
                and (r["escalation_from"] or "") == "opencode"
                and (r["escalation_to"] or "") == "codex"
            )
            fails = sum(1 for r in rows if r["success"] == 0)
            timeouts = sum(1 for r in rows if r["timed_out"] == 1 or r["result_status"] == "timeout")

            # routing
            rwhere = []
            rparams: list[Any] = []
            if cut:
                rwhere.append("timestamp >= ?")
                rparams.append(cut)
            rclause = (" WHERE " + " AND ".join(rwhere)) if rwhere else ""
            routes = con.execute(
                f"SELECT destination, COUNT(*) AS n FROM routing_events{rclause} GROUP BY destination",
                rparams,
            ).fetchall()
            route_map = {r["destination"]: r["n"] for r in routes}

            def _route_count(extra: str) -> int:
                parts = list(rwhere) + [extra]
                clause = " WHERE " + " AND ".join(parts)
                return con.execute(
                    f"SELECT COUNT(*) AS n FROM routing_events{clause}",
                    rparams,
                ).fetchone()["n"]

            overrides = _route_count("user_override=1")
            degraded = _route_count("degraded=1")

            # resource averages (memory pressure as categorical counts)
            pressure: dict[str, int] = {}
            for r in rows:
                p = r["memory_pressure_after"] or r["memory_pressure_before"]
                if p:
                    pressure[p] = pressure.get(p, 0) + 1

            return {
                "enabled": True,
                "window_days": days,
                "executions": total,
                "success_rate": round(100.0 * ok / total, 1) if total else None,
                "local_pct": round(100.0 * local / total, 1) if total else None,
                "cloud_pct": round(100.0 * cloud / total, 1) if total else None,
                "backends": dict(sorted(backends.items(), key=lambda kv: (-kv[1], kv[0]))),
                "routes": dict(sorted(route_map.items(), key=lambda kv: (-kv[1], kv[0]))),
                "overrides": overrides,
                "escalations": esc,
                "opencode_to_codex": oc,
                "degraded_routes": degraded,
                "failures": fails,
                "timeouts": timeouts,
                "memory_pressure": pressure,
            }
        finally:
            con.close()

    try:
        return _do()
    except Exception:
        return empty


def recent(limit: int = 20) -> list[dict[str, Any]]:
    con = connect()
    if con is None:
        return []
    try:
        rows = con.execute(
            """
            SELECT id, timestamp_start, backend, model, result_status, success,
                   duration_ms, local_or_cloud, escalated, task_kind, project_id
            FROM executions
            ORDER BY timestamp_start DESC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        con.close()


def format_human(summary: dict[str, Any]) -> str:
    lines = []
    lines.append("DOTS agent telemetry (local only)")
    if summary.get("window_days"):
        lines.append(f"window: last {summary['window_days']} day(s)")
    lines.append(f"executions: {summary.get('executions', 0)}")
    sr = summary.get("success_rate")
    lines.append(f"success rate: {sr}%" if sr is not None else "success rate: n/a")
    lp, cp = summary.get("local_pct"), summary.get("cloud_pct")
    lines.append(
        f"local: {lp if lp is not None else 'n/a'}%   cloud: {cp if cp is not None else 'n/a'}%"
    )
    lines.append("")
    lines.append("backend:")
    backends = summary.get("backends") or {}
    if not backends:
        lines.append("  (none)")
    else:
        width = max(len(k) for k in backends)
        for k, v in backends.items():
            lines.append(f"  {k.ljust(width)}  {v}")
    lines.append("")
    lines.append("routes:")
    routes = summary.get("routes") or {}
    if not routes:
        lines.append("  (none)")
    else:
        width = max(len(k) for k in routes)
        for k, v in routes.items():
            lines.append(f"  {k.ljust(width)}  {v}")
    lines.append("")
    lines.append(f"explicit overrides: {summary.get('overrides', 0)}")
    lines.append(f"escalations: {summary.get('escalations', 0)}")
    lines.append(f"OpenCode → Codex: {summary.get('opencode_to_codex', 0)}")
    lines.append(f"degraded routes: {summary.get('degraded_routes', 0)}")
    lines.append(f"failures: {summary.get('failures', 0)}  timeouts: {summary.get('timeouts', 0)}")
    mp = summary.get("memory_pressure") or {}
    if mp:
        lines.append("memory pressure (completed): " + ", ".join(f"{k}={v}" for k, v in mp.items()))
    return "\n".join(lines)
