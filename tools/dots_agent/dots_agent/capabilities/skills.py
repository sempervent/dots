"""Skill provenance, Agent Skills validation, and non-executing review."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
from pathlib import Path
from typing import Any

from dots_agent.capabilities.load import dots_root, skill_rows, skill_sources

NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
_FRONTMATTER = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
_UNSAFE = (
    (re.compile(r"curl\b[^|\n]*\|\s*(?:sh|bash)\b", re.I), "curl piped to a shell"),
    (re.compile(r"\bos\.system\s*\("), "os.system call"),
    (re.compile(r"\beval\s*\("), "eval call"),
    (re.compile(r"base64\s+(?:-d|--decode)"), "base64 decode of a payload"),
    (re.compile(r"\bsubprocess\.(?:run|call|Popen|check_output)\s*\("), "subprocess execution"),
)

SECRET_MARKERS = ("SUPER_SECRET_TEST",)


def skill_dirs(name: str, home: Path | None = None) -> list[Path]:
    home = home or Path.home()
    return [
        home / ".agents" / "skills" / name,
        home / ".hermes" / "skills" / name,
    ]


def installed_skill_dir(name: str, home: Path | None = None) -> Path | None:
    for path in skill_dirs(name, home):
        if (path / "SKILL.md").is_file():
            return path
    return None


def content_hash(root: Path) -> str:
    digest = hashlib.sha256()
    files = [p for p in root.rglob("*") if p.is_file() and ".git" not in p.parts]
    for path in sorted(files):
        rel = path.relative_to(root).as_posix()
        digest.update(rel.encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def parse_frontmatter(text: str) -> tuple[dict[str, str], list[str]]:
    errors: list[str] = []
    match = _FRONTMATTER.match(text)
    if not match:
        return {}, ["SKILL.md is missing YAML frontmatter"]
    fields: dict[str, str] = {}
    for line in match.group(1).splitlines():
        if not line.strip() or line.lstrip().startswith("#") or line[0] in " \t":
            continue
        if ":" not in line:
            errors.append(f"invalid frontmatter line: {line}")
            continue
        key, value = line.split(":", 1)
        fields[key.strip()] = value.strip().strip("\"'")
    return fields, errors


def validate_skill_dir(root: Path) -> list[str]:
    """Structural Agent Skills checks. Does not execute scripts."""
    errors, _warnings = validate_skill_report(root)
    return errors


def validate_skill_report(root: Path) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    skill_md = root / "SKILL.md"
    if not skill_md.is_file():
        return ["missing SKILL.md"], []
    text = skill_md.read_text(encoding="utf-8", errors="replace")
    fields, parse_errors = parse_frontmatter(text)
    errors.extend(parse_errors)
    name = fields.get("name", "")
    description = fields.get("description", "")
    if not name:
        errors.append("frontmatter name is missing")
    elif len(name) > 64 or not NAME_RE.match(name):
        errors.append(f"name {name!r} does not match Agent Skills naming constraints")
    elif name != root.name:
        errors.append(f"name {name!r} does not match directory {root.name!r}")
    if "description" not in fields:
        errors.append("frontmatter description is missing")
    elif description not in {">", "|", ">-", "|-", ""} and len(description) > 1024:
        errors.append("description exceeds 1024 characters")
    for path in root.rglob("*"):
        if not path.is_symlink():
            continue
        target = path.resolve()
        try:
            target.relative_to(root.resolve())
        except ValueError:
            errors.append(f"symlink escapes skill root: {path.relative_to(root)}")
    for rel in _relative_refs(text):
        finding = _path_escape(root, rel)
        if finding == "error":
            errors.append(f"relative reference escapes skill root: {rel}")
        elif finding == "warn":
            warnings.append(f"relative reference leaves this skill for a sibling: {rel}")
    return errors, warnings


def _path_escape(root: Path, rel: str) -> str | None:
    candidate = (root / rel).resolve()
    try:
        candidate.relative_to(root.resolve())
        return None
    except ValueError:
        pass
    store = root.parent.resolve()
    try:
        candidate.relative_to(store)
        return "warn"
    except ValueError:
        return "error"


def _relative_refs(text: str) -> list[str]:
    refs = re.findall(r"\[[^\]]*\]\(([^)]+)\)", text)
    out: list[str] = []
    for ref in refs:
        target = ref.split()[0].strip("<>")
        if "://" in target or target.startswith("#") or target.startswith("mailto:"):
            continue
        out.append(target)
    return out


def static_review(root: Path) -> list[str]:
    """Scan text. Never imports or executes skill scripts."""
    findings: list[str] = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in {".md", ".py", ".sh", ".js", ".cjs", ".mjs", ".ts", ".txt"}:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        rel = path.relative_to(root).as_posix()
        for pattern, label in _UNSAFE:
            if pattern.search(text):
                findings.append(f"{rel}: {label}")
    return findings


def state_path(home: Path | None = None) -> Path:
    home = home or Path.home()
    return home / ".config" / "dots" / "skills" / "state.json"


def load_state(home: Path | None = None) -> dict[str, Any]:
    path = state_path(home)
    if not path.is_file():
        return {"skills": {}}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"skills": {}}
    if not isinstance(data, dict):
        return {"skills": {}}
    data.setdefault("skills", {})
    return data


def save_state(data: dict[str, Any], home: Path | None = None) -> None:
    path = state_path(home)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def record_install(name: str, root: Path, *, ref: str | None, home: Path | None = None) -> str:
    digest = content_hash(root)
    data = load_state(home)
    data["skills"][name] = {
        "hash": digest,
        "ref": ref,
        "path": str(root),
        "review": "clean" if not static_review(root) else "findings",
    }
    save_state(data, home)
    return digest


def source_for(row: dict[str, Any], root: Path | None = None) -> dict[str, Any]:
    sources = skill_sources(root)
    source_id = str(row.get("source_id") or "")
    if source_id and source_id in sources:
        return sources[source_id]
    return {
        "id": row.get("source") or "",
        "repo": row.get("source") or "",
        "ref": row.get("ref") or "",
    }


def manifest_errors(root: Path | None = None) -> list[str]:
    errors: list[str] = []
    rows = skill_rows(root)
    seen: set[str] = set()
    sources = skill_sources(root)
    for row in rows:
        name = str(row.get("name") or "")
        if name in seen:
            errors.append(f"duplicate skill name: {name}")
        seen.add(name)
        if row.get("enabled") and not (row.get("source") or row.get("source_id")):
            errors.append(f"{name}: missing source")
        source_id = str(row.get("source_id") or "")
        if source_id and source_id not in sources:
            errors.append(f"{name}: unknown source_id {source_id}")
        if source_id and not str(sources.get(source_id, {}).get("ref") or ""):
            errors.append(f"{name}: source {source_id} has no reviewed ref")
    return errors


def audit_skill(name: str, *, home: Path | None = None, root: Path | None = None) -> dict[str, Any]:
    row = next((r for r in skill_rows(root) if r.get("name") == name), None)
    errors: list[str] = []
    warnings: list[str] = []
    if row is None:
        return {"name": name, "errors": [f"unknown skill: {name}"], "warnings": []}
    src = source_for(row, root)
    if row.get("source_id") and str(src.get("ref") or "") in {"", "main", "master"}:
        warnings.append("source ref is not pinned")
    installed = installed_skill_dir(name, home)
    structure: list[str] = []
    structure_warnings: list[str] = []
    review: list[str] = []
    digest = None
    if installed is not None:
        structure, structure_warnings = validate_skill_report(installed)
        review = static_review(installed)
        digest = content_hash(installed)
        recorded = (load_state(home).get("skills") or {}).get(name) or {}
        if recorded.get("hash") and recorded.get("hash") != digest:
            warnings.append("content hash drift")
        if recorded.get("ref") and src.get("ref") and recorded.get("ref") != src.get("ref"):
            warnings.append("source ref drift")
    errors.extend(structure)
    warnings.extend(structure_warnings)
    if review:
        warnings.extend(review)
    return {
        "name": name,
        "errors": errors,
        "warnings": warnings,
        "installed": installed is not None,
        "hash": digest,
        "ref": src.get("ref") or None,
        "review": "findings" if review else "clean",
    }


def update_plan(name: str, candidate: Path, *, home: Path | None = None, root: Path | None = None) -> dict[str, Any]:
    """Compare the installed skill with a staged candidate. Does not delete or execute."""
    current = installed_skill_dir(name, home)
    errors = validate_skill_dir(candidate)
    review = static_review(candidate)
    current_hash = content_hash(current) if current else None
    candidate_hash = content_hash(candidate) if candidate.is_dir() else None
    changed: list[str] = []
    if current and candidate.is_dir():
        current_files = {p.relative_to(current).as_posix() for p in current.rglob("*") if p.is_file()}
        candidate_files = {p.relative_to(candidate).as_posix() for p in candidate.rglob("*") if p.is_file()}
        changed = sorted(current_files.symmetric_difference(candidate_files))
        for rel in sorted(current_files & candidate_files):
            if (current / rel).read_bytes() != (candidate / rel).read_bytes():
                changed.append(rel)
    src = source_for(next((r for r in skill_rows(root) if r.get("name") == name), {}), root)
    return {
        "name": name,
        "current_ref": (load_state(home).get("skills") or {}).get(name, {}).get("ref"),
        "current_hash": current_hash,
        "candidate_ref": src.get("ref"),
        "candidate_hash": candidate_hash,
        "changed": sorted(set(changed)),
        "errors": errors,
        "review": review,
        "apply": False,
    }


def apply_update(name: str, candidate: Path, *, home: Path | None = None, root: Path | None = None) -> dict[str, Any]:
    plan = update_plan(name, candidate, home=home, root=root)
    if plan["errors"] or plan["review"]:
        plan["applied"] = False
        plan["reason"] = "candidate failed validation or static review"
        return plan
    home = home or Path.home()
    dest = home / ".agents" / "skills" / name
    staging = dest.with_name(dest.name + ".staging")
    if staging.exists():
        shutil.rmtree(staging)
    shutil.copytree(candidate, staging)
    if dest.exists():
        backup = dest.with_name(dest.name + ".backup")
        if backup.exists():
            shutil.rmtree(backup)
        dest.rename(backup)
    staging.rename(dest)
    src = source_for(next((r for r in skill_rows(root) if r.get("name") == name), {}), root)
    record_install(name, dest, ref=str(src.get("ref") or "") or None, home=home)
    plan["applied"] = True
    plan["path"] = str(dest)
    return plan


def skills_for_groups(groups: set[str], root: Path | None = None) -> list[str]:
    names: list[str] = []
    for row in skill_rows(root):
        if row.get("enabled") and str(row.get("group") or "") in groups:
            name = str(row["name"])
            if name not in names:
                names.append(name)
    return names


def pack_groups(pack_ids: set[str], root: Path | None = None) -> set[str]:
    from dots_agent.capabilities.load import packs

    groups: set[str] = set()
    for pack_id in pack_ids:
        row = packs(root).get(pack_id) or {}
        for group in row.get("groups") or []:
            groups.add(str(group))
    return groups


def effective_skills(
    *,
    pack_ids: set[str],
    include: list[str],
    exclude: list[str],
    root: Path | None = None,
) -> dict[str, list[str]]:
    """Pack membership plus explicit include, minus exclude. Each name once."""
    provenance: dict[str, list[str]] = {}
    for name in skills_for_groups(pack_groups(pack_ids, root), root):
        provenance.setdefault(name, []).append(f"pack:{_pack_for_skill(name, pack_ids, root)}")
    for name in include:
        provenance.setdefault(name, [])
        if "explicit-skill" not in provenance[name]:
            provenance[name].append("explicit-skill")
    for name in exclude:
        provenance.pop(name, None)
    return provenance


def _pack_for_skill(name: str, pack_ids: set[str], root: Path | None) -> str:
    row = next((r for r in skill_rows(root) if r.get("name") == name), {})
    group = str(row.get("group") or "")
    from dots_agent.capabilities.load import packs

    for pack_id in pack_ids:
        groups = [str(g) for g in (packs(root).get(pack_id) or {}).get("groups") or []]
        if group in groups:
            return pack_id
    return "unknown"


def assert_no_secrets(text: str) -> None:
    for marker in SECRET_MARKERS:
        if marker in text:
            raise AssertionError("secret value leaked")
    if os.environ.get("OPENROUTER_API_KEY") and os.environ["OPENROUTER_API_KEY"] in text:
        raise AssertionError("secret value leaked")
    if os.environ.get("GITHUB_TOKEN") and os.environ["GITHUB_TOKEN"] in text:
        raise AssertionError("secret value leaked")
