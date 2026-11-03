"""Load OpenRig role policy from configs/agents/openrig/roles.toml."""

from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from dots_agent.config import dots_root


@dataclass(frozen=True)
class RolePolicy:
    name: str
    task_class: str
    quality: str
    runtime: str
    sandbox: str
    mcp: tuple[str, ...]
    write: bool
    coordination: bool


@dataclass(frozen=True)
class TeamDefaults:
    default_template: str
    team_budget_usd: float
    max_review_rounds: int
    terminal_preferred: str
    terminal_fallback: str
    herdr_session_prefix: str
    templates: dict[str, tuple[str, ...]]


def openrig_config_root(repo_root: Path | None = None) -> Path:
    return (repo_root or dots_root()) / "configs" / "agents" / "openrig"


def load_roles(path: Path | None = None) -> tuple[dict[str, RolePolicy], TeamDefaults]:
    path = path or (openrig_config_root() / "roles.toml")
    with path.open("rb") as fh:
        data = tomllib.load(fh)
    roles: dict[str, RolePolicy] = {}
    for name, row in (data.get("roles") or {}).items():
        if not isinstance(row, dict):
            continue
        roles[name] = RolePolicy(
            name=name,
            task_class=str(row.get("task_class") or "general"),
            quality=str(row.get("quality") or "capable"),
            runtime=str(row.get("runtime") or "pi"),
            sandbox=str(row.get("sandbox") or "read_only"),
            mcp=tuple(str(x) for x in (row.get("mcp") or [])),
            write=bool(row.get("write")),
            coordination=bool(row.get("coordination")),
        )
    team = data.get("team") or {}
    templates_raw = team.get("templates") or {}
    templates = {
        str(k): tuple(str(x) for x in (v or []))
        for k, v in templates_raw.items()
        if isinstance(v, list)
    }
    defaults = TeamDefaults(
        default_template=str(team.get("default_template") or "dots-triad"),
        team_budget_usd=float(team.get("team_budget_usd") or 3.0),
        max_review_rounds=int(team.get("max_review_rounds") or 2),
        terminal_preferred=str(team.get("terminal_provider_preferred") or "herdr"),
        terminal_fallback=str(team.get("terminal_provider_fallback") or "tmux"),
        herdr_session_prefix=str(team.get("herdr_session_prefix") or "dots"),
        templates=templates,
    )
    return roles, defaults


def role_names_for_template(template: str, defaults: TeamDefaults | None = None) -> tuple[str, ...]:
    if defaults is None:
        _, defaults = load_roles()
    return defaults.templates.get(template, ())
