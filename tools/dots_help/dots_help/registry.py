"""Load authoritative DOTS registries (TOML) without mutating the machine."""

from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Any


def load_toml(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    with path.open("rb") as fh:
        return tomllib.load(fh)


def dots_root() -> Path:
    """Resolve repository root from DOTS_DIR or package location."""
    import os

    env = os.environ.get("DOTS_DIR", "").strip()
    if env:
        p = Path(env).expanduser()
        if (p / "configs" / "components.toml").is_file():
            return p
    # tools/dots_help/src/dots_help → parents[3] = repo root
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / "configs" / "components.toml").is_file():
            return parent
    return here.parents[3]


class Registry:
    def __init__(self, root: Path | None = None) -> None:
        self.root = root or dots_root()
        self.components = load_toml(self.root / "configs" / "components.toml")
        self.groups = load_toml(self.root / "configs" / "packages" / "groups.toml")
        self.lsp = load_toml(self.root / "configs" / "lsp" / "servers.toml")
        self.models = load_toml(self.root / "configs" / "models.toml")
        self.skills = load_toml(self.root / "configs" / "skills" / "manifest.toml")
        self.commands = load_toml(self.root / "configs" / "help" / "commands.toml")
        self.topics = load_toml(self.root / "configs" / "help" / "topics.toml")

    def version(self) -> str:
        vf = self.root / "VERSION"
        if vf.is_file():
            return vf.read_text(encoding="utf-8").strip() or "unknown"
        return "unknown"

    def component_rows(self) -> list[dict[str, Any]]:
        return list(self.components.get("components") or [])

    def supergroup_rows(self) -> list[dict[str, Any]]:
        """Return [[supergroups]] rows (list form in components.toml)."""
        raw = self.components.get("supergroups") or []
        if isinstance(raw, list):
            return [r for r in raw if isinstance(r, dict)]
        if isinstance(raw, dict):
            rows: list[dict[str, Any]] = []
            for sid, meta in raw.items():
                if isinstance(meta, dict):
                    rows.append({"id": sid, **meta})
                elif isinstance(meta, list):
                    rows.append({"id": sid, "members": meta})
            return rows
        return []

    def supergroups(self) -> dict[str, Any]:
        """Map id → metadata (compat). Prefer supergroup_rows()."""
        out: dict[str, Any] = {}
        for row in self.supergroup_rows():
            sid = str(row.get("id") or "")
            if sid:
                out[sid] = row
        return out

    def package_groups(self) -> list[dict[str, Any]]:
        return list(self.groups.get("groups") or [])

    def lsp_servers(self) -> list[dict[str, Any]]:
        return list(self.lsp.get("servers") or [])

    def command_rows(self) -> list[dict[str, Any]]:
        return list(self.commands.get("commands") or [])

    def topic_rows(self) -> list[dict[str, Any]]:
        rows = list(self.topics.get("topics") or [])
        return sorted(rows, key=lambda r: int(r.get("order") or 999))
