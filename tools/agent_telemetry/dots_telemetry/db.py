"""SQLite schema, migrations, connection helpers."""

from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Any

from .config import SCHEMA_VERSION, db_path, load_config

DDL_V1 = """
CREATE TABLE IF NOT EXISTS schema_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS executions (
  id TEXT PRIMARY KEY,
  timestamp_start TEXT NOT NULL,
  timestamp_end TEXT,
  duration_ms INTEGER,
  session_id TEXT,
  parent_id TEXT,
  task_kind TEXT,
  task_label TEXT,
  route_category TEXT,
  route_destination TEXT,
  route_reason TEXT,
  user_override INTEGER DEFAULT 0,
  degraded INTEGER DEFAULT 0,
  backend TEXT,
  provider TEXT,
  model TEXT,
  local_or_cloud TEXT,
  agent TEXT,
  tool TEXT,
  project_id TEXT,
  success INTEGER,
  result_status TEXT,
  exit_code INTEGER,
  timed_out INTEGER DEFAULT 0,
  escalated INTEGER DEFAULT 0,
  escalation_from TEXT,
  escalation_to TEXT,
  escalation_reason TEXT,
  input_tokens INTEGER,
  output_tokens INTEGER,
  total_tokens INTEGER,
  reported_cost_usd REAL,
  estimated_cost_usd REAL,
  memory_pressure_before TEXT,
  memory_pressure_after TEXT,
  swap_pages_before INTEGER,
  swap_pages_after INTEGER,
  ollama_models_before TEXT,
  ollama_models_after TEXT,
  drawthings_active INTEGER,
  metadata_json TEXT,
  status TEXT DEFAULT 'running'
);

CREATE TABLE IF NOT EXISTS routing_events (
  id TEXT PRIMARY KEY,
  timestamp TEXT NOT NULL,
  session_id TEXT,
  category TEXT,
  destination TEXT,
  reason TEXT,
  user_override INTEGER DEFAULT 0,
  degraded INTEGER DEFAULT 0,
  escalation TEXT,
  available_json TEXT,
  note TEXT
);

CREATE INDEX IF NOT EXISTS idx_exec_start ON executions(timestamp_start);
CREATE INDEX IF NOT EXISTS idx_exec_backend ON executions(backend);
CREATE INDEX IF NOT EXISTS idx_exec_status ON executions(result_status);
CREATE INDEX IF NOT EXISTS idx_route_ts ON routing_events(timestamp);
CREATE INDEX IF NOT EXISTS idx_route_dest ON routing_events(destination);
"""


def connect(path: Path | None = None) -> sqlite3.Connection | None:
    """Open DB with WAL + busy timeout. Returns None on failure."""
    try:
        cfg = load_config()
        db = path or db_path(cfg)
        db.parent.mkdir(parents=True, exist_ok=True)
        timeout_ms = int((cfg.get("sqlite") or {}).get("busy_timeout_ms") or 5000)
        con = sqlite3.connect(str(db), timeout=max(timeout_ms / 1000.0, 0.5), isolation_level=None)
        con.row_factory = sqlite3.Row
        if bool((cfg.get("sqlite") or {}).get("wal", True)):
            con.execute("PRAGMA journal_mode=WAL")
        con.execute(f"PRAGMA busy_timeout={timeout_ms}")
        con.execute("PRAGMA synchronous=NORMAL")
        _migrate(con)
        return con
    except Exception:
        return None


def _migrate(con: sqlite3.Connection) -> None:
    con.executescript(DDL_V1)
    row = con.execute("SELECT value FROM schema_meta WHERE key='schema_version'").fetchone()
    if row is None:
        con.execute(
            "INSERT INTO schema_meta(key, value) VALUES('schema_version', ?)",
            (str(SCHEMA_VERSION),),
        )
        return
    # Future: bump SCHEMA_VERSION and ALTER here without wiping data.
    current = int(row["value"])
    if current < SCHEMA_VERSION:
        con.execute(
            "UPDATE schema_meta SET value=? WHERE key='schema_version'",
            (str(SCHEMA_VERSION),),
        )


def doctor() -> dict[str, Any]:
    cfg = load_config()
    path = db_path(cfg)
    out: dict[str, Any] = {
        "enabled": bool(cfg.get("enabled", True)),
        "config": str(path),  # placeholder overwritten
        "db_path": str(path),
        "ok": False,
    }
    from .config import config_path, telemetry_enabled

    out["config"] = str(config_path())
    out["enabled_effective"] = telemetry_enabled(cfg)
    con = connect(path)
    if con is None:
        out["error"] = "cannot open sqlite database"
        return out
    try:
        ver = con.execute("SELECT value FROM schema_meta WHERE key='schema_version'").fetchone()
        mode = con.execute("PRAGMA journal_mode").fetchone()[0]
        out["schema_version"] = ver["value"] if ver else None
        out["journal_mode"] = mode
        out["writable"] = path.parent.is_dir() and os_access_writable(path.parent)
        out["ok"] = True
    finally:
        con.close()
    return out


def os_access_writable(p: Path) -> bool:
    import os

    return os.access(p, os.W_OK)
