"""Load authoritative TOML registries. Read-only."""

from __future__ import annotations

import os
import tomllib
from pathlib import Path
from typing import Any


def dots_root() -> Path:
    env = os.environ.get("DOTS_DIR", "").strip()
    if env:
        return Path(env).expanduser().resolve()
    return Path(__file__).resolve().parents[4]


def _load(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    with path.open("rb") as fh:
        data = tomllib.load(fh)
    return data if isinstance(data, dict) else {}


def skill_manifest(root: Path | None = None) -> dict[str, Any]:
    root = root or dots_root()
    return _load(root / "configs" / "skills" / "manifest.toml")


def mcp_registry(root: Path | None = None) -> dict[str, Any]:
    root = root or dots_root()
    return _load(root / "configs" / "agents" / "mcp-trust.toml")


def runtime_requirements(root: Path | None = None) -> dict[str, Any]:
    root = root or dots_root()
    return _load(root / "configs" / "runtime-requirements.toml")


def components_doc(root: Path | None = None) -> dict[str, Any]:
    root = root or dots_root()
    return _load(root / "configs" / "components.toml")


def node_default_major(root: Path | None = None) -> str:
    root = root or dots_root()
    data = _load(root / "configs" / "node" / "default.toml")
    return str(data.get("version") or "24").strip() or "24"


def skill_rows(root: Path | None = None) -> list[dict[str, Any]]:
    rows = skill_manifest(root).get("skills") or []
    return [r for r in rows if isinstance(r, dict) and r.get("name")]


def skill_sources(root: Path | None = None) -> dict[str, dict[str, Any]]:
    rows = skill_manifest(root).get("skill_sources") or []
    out: dict[str, dict[str, Any]] = {}
    for row in rows:
        if isinstance(row, dict) and row.get("id"):
            out[str(row["id"])] = row
    return out


def known_skill_ids(root: Path | None = None) -> set[str]:
    return {str(r["name"]) for r in skill_rows(root)}


def mcp_rows(root: Path | None = None) -> list[dict[str, Any]]:
    rows = mcp_registry(root).get("mcp_servers") or []
    return [r for r in rows if isinstance(r, dict) and r.get("id")]


def known_mcp_ids(root: Path | None = None) -> set[str]:
    return {str(r["id"]) for r in mcp_rows(root)}


def packs(root: Path | None = None) -> dict[str, dict[str, Any]]:
    raw = skill_manifest(root).get("packs") or {}
    return {str(k): v for k, v in raw.items() if isinstance(v, dict)}
