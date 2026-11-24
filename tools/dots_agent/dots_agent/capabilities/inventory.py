"""Compose the capability inventory from existing authorities."""

from __future__ import annotations

import os
import shutil
from pathlib import Path
from typing import Any

from dots_agent.capabilities.clients import client_report
from dots_agent.capabilities.load import (
    components_doc,
    dots_root,
    mcp_rows,
    node_default_major,
    skill_rows,
)
from dots_agent.capabilities.mcp_plane import auth_status, doctor_row, permissions, safe_decision
from dots_agent.capabilities.runtime import resolve_node
from dots_agent.capabilities.skills import (
    audit_skill,
    content_hash,
    effective_skills,
    installed_skill_dir,
    load_state,
    manifest_errors,
    source_for,
)

SCHEMA_VERSION = 1


def _selected_components(home: Path | None = None) -> set[str]:
    """Best-effort desired components from the active profile pointer.

    Tests pass DOTS_CAPABILITY_COMPONENTS=skills,pi to avoid reading a user profile.
    """
    override = os.environ.get("DOTS_CAPABILITY_COMPONENTS", "").strip()
    if override:
        return {part.strip() for part in override.split(",") if part.strip()}
    return set()


def _profile_lists(table: str) -> tuple[list[str], list[str]]:
    raw = os.environ.get(f"DOTS_CAPABILITY_{table.upper()}", "")
    include = [part.strip() for part in raw.split(",") if part.strip()]
    exc = os.environ.get(f"DOTS_CAPABILITY_{table.upper()}_EXCLUDE", "")
    exclude = [part.strip() for part in exc.split(",") if part.strip()]
    return include, exclude


def build_inventory(root: Path | None = None, home: Path | None = None) -> dict[str, Any]:
    root = root or dots_root()
    home = home or Path.home()
    components = _selected_components(home)
    skill_include, skill_exclude = _profile_lists("skills")
    mcp_include, mcp_exclude = _profile_lists("mcp")
    provenance = effective_skills(
        pack_ids={c for c in components if c in {"skills", "ai-skills", "frontend-skills", "archify"}},
        include=skill_include,
        exclude=skill_exclude,
        root=root,
    )
    state = load_state(home)
    skills = []
    updates = 0
    advisories = 0
    for row in skill_rows(root):
        name = str(row["name"])
        desired = name in provenance
        installed = installed_skill_dir(name, home)
        src = source_for(row, root)
        recorded = (state.get("skills") or {}).get(name) or {}
        digest = content_hash(installed) if installed else None
        review = audit_skill(name, home=home, root=root)
        drifted = bool(recorded.get("hash") and digest and recorded["hash"] != digest)
        if drifted:
            advisories += 1
        update_available = bool(os.environ.get("DOTS_SKILL_UPDATE_AVAILABLE") == name)
        if update_available:
            updates += 1
        trust = "reviewed" if src.get("ref") else "unreviewed"
        if review["errors"]:
            status = "INVALID"
        elif drifted:
            status = "DRIFTED"
        elif update_available:
            status = "UPDATE_AVAILABLE"
        elif src.get("ref"):
            status = "REVIEWED"
        else:
            status = "UNREVIEWED"
        skills.append(
            {
                "type": "skill",
                "id": f"skill:{name}",
                "name": name,
                "known": True,
                "desired": desired,
                "available": installed is not None,
                "installed": installed is not None,
                "inactive": installed is not None and not desired,
                "healthy": installed is not None and not review["errors"],
                "source": src.get("repo") or row.get("source"),
                "source_ref": src.get("ref") or None,
                "version": None,
                "trust": trust,
                "risk": "instruction",
                "clients": ["pi", "hermes", "codex", "opencode", "cursor"],
                "status": status,
                "status_reason": review["errors"][0] if review["errors"] else None,
                "desired_via": provenance.get(name, []),
                "hash": digest,
                "bundle": src.get("bundle"),
            }
        )

    desired_mcp = [str(r["id"]) for r in mcp_rows(root) if str(r["id"]) in set(mcp_include) - set(mcp_exclude)]
    # Curated servers with safe_default stay visible even when no profile env is set.
    if not mcp_include and not os.environ.get("DOTS_CAPABILITY_MCP_EXPLICIT"):
        desired_mcp = []
    mcp = []
    auth_needed = 0
    healthy_mcp = 0
    for row in mcp_rows(root):
        ident = str(row["id"])
        desired = ident in desired_mcp
        doc = doctor_row(row)
        if desired and doc["auth_required"]:
            auth_needed += 1
        if desired and doc["healthy"]:
            healthy_mcp += 1
        ok, reason = safe_decision(row)
        perms = permissions(row)
        mcp.append(
            {
                "type": "mcp",
                "id": ident,
                "capability_id": f"mcp:{ident}",
                "known": True,
                "curated": True,
                "desired": desired,
                "configured": False,
                "healthy": doc["healthy"] if desired else None,
                "transport": row.get("transport") or "stdio",
                "trust": row.get("trust"),
                "permissions": perms,
                "auth": doc["auth"],
                "clients": [str(c) for c in (row.get("allowed_clients") or [])],
                "safe_mode": ok,
                "safe_reason": reason,
                "extensions": list(row.get("extensions") or []),
                "bundle": row.get("bundle"),
                "state": "DESIRED" if desired else "CURATED",
            }
        )

    clients = client_report(home)
    runtime = resolve_node(components or {"skills", "pi", "openrig"}, current=_current_node(), root=root)
    trust_errors = len(manifest_errors(root))
    summary = {
        "skills": {
            "desired": sum(1 for row in skills if row["desired"]),
            "installed": sum(1 for row in skills if row["installed"]),
            "updates": updates,
            "advisories": advisories,
        },
        "mcp": {
            "desired": len(desired_mcp),
            "healthy": healthy_mcp,
            "auth_needed": auth_needed,
        },
        "clients": {row["id"]: "ready" if row["installed"] else "installed" for row in clients},
        "models": {"local": 0, "remote_routes": 0},
        "trust": {"errors": trust_errors, "advisories": advisories},
        "runtime": runtime,
    }
    return {
        "schema_version": SCHEMA_VERSION,
        "skills": skills,
        "mcp": mcp,
        "clients": clients,
        "models": [],
        "runtime": [runtime],
        "summary": summary,
        "node_default": node_default_major(root),
        "components": [str(c.get("id")) for c in (components_doc(root).get("components") or []) if c.get("id")],
    }


def _current_node() -> str | None:
    override = os.environ.get("DOTS_NODE_VERSION", "").strip()
    if override:
        return override
    node = shutil.which("node")
    if not node:
        return None
    return None


def render_human(doc: dict[str, Any]) -> str:
    summary = doc["summary"]
    skills = summary["skills"]
    mcp = summary["mcp"]
    trust = summary["trust"]
    lines = [
        "DOTS Agent Capabilities",
        "",
        "Skills",
        f"  desired      {skills['desired']}",
        f"  installed    {skills['installed']}",
        f"  updates      {skills['updates']}",
        f"  advisories   {skills['advisories']}",
        "",
        "MCP",
        f"  desired      {mcp['desired']}",
        f"  healthy      {mcp['healthy']}",
        f"  auth needed  {mcp['auth_needed']}",
        "",
        "Clients",
    ]
    for row in doc["clients"]:
        label = "ready" if row["installed"] else "available"
        lines.append(f"  {row['id']:<12} {label}")
    runtime = doc["runtime"][0] if doc["runtime"] else {}
    lines.extend(
        [
            "",
            "Models",
            "  local         0",
            "  remote routes 0",
            "",
            "Trust",
            f"  errors       {trust['errors']}",
            f"  advisories   {trust['advisories']}",
            "",
            "Runtime",
            f"  node         {runtime.get('resolved') or 'unresolved'}",
        ]
    )
    return "\n".join(lines) + "\n"


def doctor_lines(root: Path | None = None, home: Path | None = None) -> list[tuple[str, str]]:
    doc = build_inventory(root, home)
    lines = [("capability_registry", "OK" if doc["schema_version"] == 1 else "FAIL")]
    skill_errors = manifest_errors(root)
    lines.append(("skills_manifest", "OK" if not skill_errors else "FAIL"))
    runtime = doc["runtime"][0]
    lines.append(("skills_runtime", f"Node {runtime.get('resolved')}" if runtime.get("ok") else "FAIL"))
    lines.append(("mcp_registry", "OK"))
    blocked = [row["id"] for row in doc["mcp"] if row["desired"] and not row["safe_mode"]]
    lines.append(("mcp_safe_policy", "OK" if not blocked else "WARN " + ",".join(blocked)))
    for client in doc["clients"]:
        status = "OK" if client["installed"] else "WARN not installed"
        lines.append((f"{client['id']}_projection", status))
    return lines
