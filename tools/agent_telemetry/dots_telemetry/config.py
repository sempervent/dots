"""Telemetry configuration + paths."""

from __future__ import annotations

import os
import tomllib
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1


def dots_root() -> Path:
    env = os.environ.get("DOTS_DIR")
    if env:
        return Path(env).expanduser()
    return Path(__file__).resolve().parents[3]


def xdg_config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")).expanduser()


def xdg_data_home() -> Path:
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")).expanduser()


def config_path() -> Path:
    override = os.environ.get("DOTS_TELEMETRY_CONFIG")
    if override:
        return Path(override).expanduser()
    live = xdg_config_home() / "dots" / "agents" / "telemetry.toml"
    if live.is_file():
        return live
    return dots_root() / "configs" / "agents" / "telemetry.toml"


def load_config() -> dict[str, Any]:
    path = config_path()
    if not path.is_file():
        return {
            "enabled": True,
            "storage": "sqlite",
            "capture_text": False,
            "capture_resource_usage": True,
            "capture_cost": True,
            "capture_ollama_state": True,
            "retention_days": 90,
            "privacy": {
                "store_prompts": False,
                "store_responses": False,
                "store_full_paths": False,
            },
            "sqlite": {
                "path": "dots/telemetry/agents.sqlite3",
                "busy_timeout_ms": 5000,
                "wal": True,
            },
        }
    with path.open("rb") as fh:
        return tomllib.load(fh)


def telemetry_enabled(cfg: dict[str, Any] | None = None) -> bool:
    env = os.environ.get("DOTS_TELEMETRY", "").strip().lower()
    if env in {"0", "false", "no", "off"}:
        return False
    if env in {"1", "true", "yes", "on"}:
        return True
    cfg = cfg if cfg is not None else load_config()
    return bool(cfg.get("enabled", True))


def db_path(cfg: dict[str, Any] | None = None) -> Path:
    override = os.environ.get("DOTS_TELEMETRY_DB")
    if override:
        return Path(override).expanduser()
    cfg = cfg if cfg is not None else load_config()
    rel = ((cfg.get("sqlite") or {}).get("path") or "dots/telemetry/agents.sqlite3").strip()
    p = Path(rel).expanduser()
    if p.is_absolute():
        return p
    return xdg_data_home() / p


def privacy(cfg: dict[str, Any] | None = None) -> dict[str, Any]:
    cfg = cfg if cfg is not None else load_config()
    return dict(cfg.get("privacy") or {})
