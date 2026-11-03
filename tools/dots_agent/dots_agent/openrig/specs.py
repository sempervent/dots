"""Render DOTS RigSpecs into a staging directory for OpenRig."""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

from dots_agent.config import dots_root
from dots_agent.openrig.roles import load_roles, openrig_config_root, role_names_for_template


TEMPLATES = ("dots-pair", "dots-triad", "dots-investigate")


def list_templates(repo_root: Path | None = None) -> list[str]:
    root = openrig_config_root(repo_root)
    out = []
    for name in TEMPLATES:
        if (root / "rigs" / f"{name}.yaml").is_file():
            out.append(name)
    return out


def render_team_bundle(
    template: str,
    *,
    project: Path,
    staging_root: Path,
    repo_root: Path | None = None,
) -> dict[str, Any]:
    """Copy agents + rig YAML into staging; return paths and plan metadata."""
    repo_root = repo_root or dots_root()
    cfg_root = openrig_config_root(repo_root)
    roles, defaults = load_roles(cfg_root / "roles.toml")
    if template not in defaults.templates and template not in TEMPLATES:
        raise ValueError(f"unknown team template: {template}")

    src_rig = cfg_root / "rigs" / f"{template}.yaml"
    if not src_rig.is_file():
        raise FileNotFoundError(src_rig)

    dest = staging_root / template
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)

    # Copy agent specs used by template
    agents_dest = dest / "agents"
    agents_dest.mkdir()
    for role in role_names_for_template(template, defaults):
        src = cfg_root / "agents" / role
        if not src.is_dir():
            raise FileNotFoundError(src)
        shutil.copytree(src, agents_dest / role)

    rig_dest = dest / "rig.yaml"
    shutil.copy2(src_rig, rig_dest)

    # Project pointer (not secrets)
    (dest / "project.json").write_text(
        json.dumps(
            {
                "template": template,
                "project": str(project.resolve()),
                "team_budget_usd": defaults.team_budget_usd,
                "max_review_rounds": defaults.max_review_rounds,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    seats = []
    for role_name in role_names_for_template(template, defaults):
        pol = roles[role_name]
        seats.append(
            {
                "role": role_name,
                "runtime": pol.runtime,
                "task_class": pol.task_class,
                "quality": pol.quality,
                "sandbox": pol.sandbox,
                "write": pol.write,
                "mcp": list(pol.mcp),
            }
        )

    return {
        "template": template,
        "staging": str(dest),
        "rig_yaml": str(rig_dest),
        "project": str(project.resolve()),
        "seats": seats,
        "team_budget_usd": defaults.team_budget_usd,
        "max_review_rounds": defaults.max_review_rounds,
        "terminal_preferred": defaults.terminal_preferred,
        "herdr_session": f"{defaults.herdr_session_prefix}-{template}",
    }


def dry_run_plan(bundle: dict[str, Any], *, local_model: str = "(none)") -> str:
    lines = [
        "DOTS Team Plan",
        "─" * 36,
        "",
        "Rig",
        f"  {bundle['template']}",
        "",
        "Project",
        f"  {bundle['project']}",
        "",
        "Seats",
    ]
    for s in bundle["seats"]:
        lines.append(f"  {s['role']}")
        lines.append(f"    runtime      {s['runtime']}")
        lines.append(f"    model        {local_model}")
        lines.append(f"    quality      {s['quality']}")
        lines.append(f"    sandbox      {s['sandbox']}")
        lines.append(f"    write        {'yes' if s['write'] else 'no (enforced)'}")
    lines.extend(
        [
            "",
            "Remote expert budget",
            f"  team           ${float(bundle['team_budget_usd']):.2f}",
            "",
            "Terminal",
            f"  provider       {bundle['terminal_preferred']}",
            f"  session        {bundle['herdr_session']}",
            "",
            "Review policy",
            f"  max rounds     {bundle['max_review_rounds']}",
            "",
            "No changes made." if bundle.get("_dry_run", True) else "",
        ]
    )
    return "\n".join(lines).rstrip() + "\n"
