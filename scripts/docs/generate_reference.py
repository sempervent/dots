#!/usr/bin/env python3
"""Generate docs/reference/generated/* and docs/maintainers/* copies from repo sources.

Usage:
  python3 scripts/docs/generate_reference.py           # write outputs
  python3 scripts/docs/generate_reference.py --check   # exit 1 on drift

Does not invent CLI flags: help text is captured from scripts' usage strings
when available, otherwise from documented Usage: blocks in source.
Never embeds secrets or machine-local state.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GEN_DIR = ROOT / "docs" / "reference" / "generated"
MAINT_DIR = ROOT / "docs" / "maintainers"

HEADER_TMPL = """\
<!--
GENERATED — DO NOT EDIT.
Source: {source}
Generator: scripts/docs/generate_reference.py
-->
"""


def load_toml(path: Path) -> dict:
    with path.open("rb") as f:
        return tomllib.load(f)


def write_or_check(path: Path, body: str, *, check: bool) -> bool:
    """Return True if OK (written or matched). False on check drift."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if check:
        if not path.is_file():
            print(f"MISSING: {path.relative_to(ROOT)}", file=sys.stderr)
            return False
        existing = path.read_text(encoding="utf-8")
        if existing != body:
            print(f"DRIFT: {path.relative_to(ROOT)}", file=sys.stderr)
            return False
        return True
    path.write_text(body, encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)}")
    return True


def gen_header(source: str) -> str:
    return HEADER_TMPL.format(source=source)


def md_table(headers: list[str], rows: list[list[str]]) -> str:
    esc = lambda s: str(s).replace("|", "\\|").replace("\n", " ")
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(esc(c) for c in row) + " |")
    return "\n".join(lines) + "\n"


def generate_components(check: bool) -> bool:
    src = "configs/components.toml"
    data = load_toml(ROOT / src)
    rows = []
    for c in data.get("components") or []:
        rows.append(
            [
                c.get("id", ""),
                c.get("label", ""),
                c.get("category", ""),
                ", ".join(c.get("platforms") or []),
                c.get("brewfile", "") or "—",
                "yes" if c.get("omit_from_all") else "no",
                c.get("description", "") or "",
            ]
        )
    body = (
        gen_header(src)
        + "\n# Components (generated)\n\n"
        + "Authoritative registry: `configs/components.toml`.\n\n"
        + md_table(
            [
                "id",
                "label",
                "category",
                "platforms",
                "brewfile",
                "omit_from_all",
                "description",
            ],
            rows,
        )
    )
    return write_or_check(GEN_DIR / "components.md", body, check=check)


def generate_supergroups(check: bool) -> bool:
    src = "configs/components.toml"
    data = load_toml(ROOT / src)
    rows = []
    for g in data.get("supergroups") or []:
        rows.append(
            [
                g.get("id", ""),
                g.get("label", ""),
                ", ".join(g.get("members") or []),
                g.get("description", "") or "",
            ]
        )
    body = (
        gen_header(src)
        + "\n# Supergroups (generated)\n\n"
        + "Supergroups expand to member component ids before install.\n\n"
        + md_table(["id", "label", "members", "description"], rows)
    )
    return write_or_check(GEN_DIR / "supergroups.md", body, check=check)


def generate_package_groups(check: bool) -> bool:
    src = "configs/packages/groups.toml"
    data = load_toml(ROOT / src)
    parts = [
        gen_header(src),
        "\n# Package groups (generated)\n\n",
        "Logical groups from `configs/packages/groups.toml`. "
        "Homebrew ownership: `brew/groups/<name>.Brewfile`.\n\n",
    ]
    for g in data.get("groups") or []:
        name = g.get("name", "")
        parts.append(f"## `{name}`\n\n")
        parts.append(f"{g.get('description', '')}\n\n")
        req = g.get("required") or []
        opt = g.get("optional") or []
        parts.append(f"**Required:** {', '.join(f'`{x}`' for x in req) or '(none)'}\n\n")
        parts.append(f"**Optional:** {', '.join(f'`{x}`' for x in opt) or '(none)'}\n\n")
    return write_or_check(GEN_DIR / "package-groups.md", "".join(parts), check=check)


def generate_skills(check: bool) -> bool:
    src = "configs/skills/manifest.toml"
    data = load_toml(ROOT / src)
    parts = [
        gen_header(src),
        "\n# Skills inventory (generated)\n\n",
        f"Manifest: `{data.get('name', '')}` — {data.get('description', '')}\n\n",
        "## Packs\n\n",
    ]
    packs = data.get("packs") or {}
    pack_rows = []
    for pname, pdata in packs.items():
        pack_rows.append(
            [
                pname,
                ", ".join(pdata.get("groups") or []),
                pdata.get("description", "") or "",
            ]
        )
    parts.append(md_table(["pack", "groups", "description"], pack_rows))
    parts.append("\n## Skills\n\n")
    skill_rows = []
    for s in data.get("skills") or []:
        skill_rows.append(
            [
                s.get("name", ""),
                s.get("source", ""),
                s.get("group", ""),
                "yes" if s.get("enabled", True) else "no",
            ]
        )
    parts.append(md_table(["name", "source", "group", "enabled"], skill_rows))
    return write_or_check(GEN_DIR / "skills.md", "".join(parts), check=check)


def generate_links(check: bool) -> bool:
    src = "configs/links.toml"
    data = load_toml(ROOT / src)
    rows = []
    for link in data.get("links") or []:
        rows.append(
            [
                link.get("source", ""),
                link.get("target", ""),
                link.get("description", "") or "",
            ]
        )
    body = (
        gen_header(src)
        + "\n# Managed links (generated)\n\n"
        + "Active links from `configs/links.toml`. "
        "Dormant `syms/` files not listed here are intentional.\n\n"
        + md_table(["source", "target", "description"], rows)
    )
    return write_or_check(GEN_DIR / "links.md", body, check=check)


def generate_models(check: bool) -> bool:
    src = "configs/models.toml"
    data = load_toml(ROOT / src)
    policy = data.get("policy") or {}
    parts = [
        gen_header(src),
        "\n# Models registry (generated)\n\n",
        "## Policy\n\n",
        md_table(
            ["key", "value"],
            [[k, policy[k]] for k in sorted(policy.keys())],
        ),
        "\n## Models\n\n",
    ]
    rows = []
    for m in data.get("models") or []:
        ident = (
            m.get("ollama_model")
            or m.get("hf_repo")
            or m.get("drawthings_model")
            or m.get("fluidvoice_model")
            or ""
        )
        if m.get("quant"):
            ident = f"{ident}:{m.get('quant')}" if ident else m.get("quant")
        rows.append(
            [
                m.get("id", ""),
                m.get("provider", ""),
                m.get("role", ""),
                m.get("tier", ""),
                "yes" if m.get("default") else "no",
                ", ".join(m.get("platforms") or []),
                m.get("min_memory_gb", ""),
                ident,
                m.get("automation", "auto"),
                m.get("description", "") or "",
            ]
        )
    parts.append(
        md_table(
            [
                "id",
                "provider",
                "role",
                "tier",
                "default",
                "platforms",
                "min_ram_gb",
                "upstream id",
                "automation",
                "description",
            ],
            rows,
        )
    )
    return write_or_check(GEN_DIR / "models.md", "".join(parts), check=check)


def generate_profiles(check: bool) -> bool:
    src_glob = "configs/bootstrap/profiles/*.toml"
    profiles_dir = ROOT / "configs" / "bootstrap" / "profiles"
    parts = [
        gen_header(src_glob),
        "\n# Built-in profiles (generated)\n\n",
        "Repository presets under `configs/bootstrap/profiles/`. "
        "Custom overlays live in `~/.config/dots/profiles/` (not generated).\n\n",
    ]
    for path in sorted(profiles_dir.glob("*.toml")):
        data = load_toml(path)
        p = data.get("profile") or {}
        rt = data.get("runtime") or {}
        parts.append(f"## `{p.get('name', path.stem)}`\n\n")
        parts.append(f"{p.get('description', '')}\n\n")
        parts.append(f"- **Source:** `configs/bootstrap/profiles/{path.name}`\n")
        if p.get("include_all_optional"):
            parts.append("- **include_all_optional:** yes\n")
        with_list = p.get("with") or []
        without = p.get("without") or []
        packages = p.get("packages") or []
        parts.append(f"- **packages:** {', '.join(f'`{x}`' for x in packages) or '(none)'}\n")
        parts.append(f"- **with:** {', '.join(f'`{x}`' for x in with_list) or '(none)'}\n")
        if without:
            parts.append(f"- **without:** {', '.join(f'`{x}`' for x in without)}\n")
        if rt:
            mux = rt.get("multiplexer", "")
            if mux:
                parts.append(f"- **runtime.multiplexer:** `{mux}`\n")
        parts.append("\n")
    # Example templates (names only — point to examples/)
    examples = ROOT / "examples" / "profiles"
    if examples.is_dir():
        parts.append("## Example templates\n\n")
        parts.append("Not applied automatically. Copy from `examples/profiles/`:\n\n")
        ex_rows = []
        for path in sorted(examples.glob("*.toml")):
            data = load_toml(path)
            p = data.get("profile") or {}
            ex_rows.append(
                [
                    path.name,
                    p.get("name", ""),
                    p.get("extends", "") or "—",
                    p.get("description", "") or "",
                ]
            )
        parts.append(md_table(["file", "name", "extends", "description"], ex_rows))
    return write_or_check(GEN_DIR / "profiles.md", "".join(parts), check=check)


def _safe_help(cmd: list[str], timeout: float = 15.0) -> str | None:
    """Run a help command; return stdout+stderr or None on failure."""
    try:
        env = os.environ.copy()
        # Avoid mutating / prompting
        env["CI"] = "1"
        env["DOTS_NONINTERACTIVE"] = "1"
        proc = subprocess.run(
            cmd,
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
            check=False,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        out = out.strip()
        if not out:
            return None
        # Refuse if it looks like it did real work beyond help
        lower = out.lower()
        if "password" in lower or "secret" in lower or "token=" in lower:
            return None
        return out
    except (OSError, subprocess.TimeoutExpired):
        return None


def _extract_usage_from_source(path: Path, marker: str = "Usage:") -> str | None:
    text = path.read_text(encoding="utf-8")
    # Prefer heredoc usage blocks after Usage:
    m = re.search(
        r"(Usage:.*?)(?:^EOF$|^}\s*$)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    if m:
        block = m.group(1).strip()
        # Unescape common shell heredoc noise lightly
        return block
    if marker in text:
        idx = text.index(marker)
        return text[idx : idx + 800].split("EOF")[0].strip()
    return None


def generate_cli_help(check: bool) -> bool:
    src = "dots + bootstrap.sh + setup.sh + configure.sh (safe --help)"
    sections: list[tuple[str, str]] = []

    # Unified CLI
    help_out = _safe_help([str(ROOT / "dots"), "help"])
    if help_out is None:
        help_out = _safe_help([str(ROOT / "dots"), "--help"])
    if help_out is None:
        help_out = _extract_usage_from_source(ROOT / "dots") or "(unavailable)"
    sections.append(("`./dots`", help_out))

    for label, script, args in [
        ("`./bootstrap.sh`", ROOT / "bootstrap.sh", ["--help"]),
        ("`./setup.sh`", ROOT / "setup.sh", ["--help"]),
        ("`./configure.sh`", ROOT / "configure.sh", ["--help"]),
        ("`./scripts/check.sh`", ROOT / "scripts" / "check.sh", ["--help"]),
        ("`./scripts/pull_models.sh`", ROOT / "scripts" / "pull_models.sh", ["--help"]),
    ]:
        out = _safe_help([str(script), *args])
        if out is None:
            out = _extract_usage_from_source(script) or "(help unavailable; see source)"
        sections.append((label, out))

    # Subcommand help from dots source patterns (packages, profile, models)
    for sub in ("packages", "profile", "models", "backup", "restore"):
        out = _safe_help([str(ROOT / "dots"), sub, "--help"])
        if out:
            sections.append((f"`./dots {sub}`", out))

    parts = [
        gen_header(src),
        "\n# CLI help (generated)\n\n",
        "Captured from safe `--help` / `help` invocations. "
        "If a binary is missing or help fails, a source Usage excerpt may be used. "
        "Do not treat this page as inventing flags beyond what the scripts print.\n\n",
    ]
    for title, text in sections:
        parts.append(f"## {title}\n\n```text\n{text.rstrip()}\n```\n\n")
    return write_or_check(GEN_DIR / "cli-help.md", "".join(parts), check=check)


def generate_maintainer_copies(check: bool) -> bool:
    ok = True
    copies = [
        (ROOT / "CONTRIBUTING.md", MAINT_DIR / "contributing.md", "CONTRIBUTING.md"),
        (ROOT / "AGENTS.md", MAINT_DIR / "agents.md", "AGENTS.md"),
        (ROOT / "SKILL.md", MAINT_DIR / "skill.md", "SKILL.md"),
    ]
    for src_path, dest, src_label in copies:
        if not src_path.is_file():
            print(f"WARN: missing {src_label} (skip)", file=sys.stderr)
            # SKILL.md may be created in same PR — for --check require it once present
            if src_label == "SKILL.md" and not check:
                continue
            if check and src_label != "SKILL.md":
                ok = False
            continue
        content = src_path.read_text(encoding="utf-8")
        # Rewrite root-relative markdown links so the docs/maintainers/ copies
        # resolve inside the MkDocs tree (repo-root SKILL.md is not under docs/).
        if src_label == "AGENTS.md":
            content = content.replace("](SKILL.md)", "](skill.md)")
            content = content.replace("](CONTRIBUTING.md)", "](contributing.md)")
        elif src_label == "SKILL.md":
            content = content.replace("](CONTRIBUTING.md)", "](contributing.md)")
            content = content.replace(
                "`docs/concepts/architecture.md`",
                "[architecture](../concepts/architecture.md)",
            )
        elif src_label == "CONTRIBUTING.md":
            content = content.replace("](SKILL.md)", "](skill.md)")
        body = gen_header(src_label) + "\n" + content
        if not write_or_check(dest, body, check=check):
            ok = False
    return ok


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if generated files drift from regenerating now",
    )
    args = parser.parse_args()
    check = args.check

    results = [
        generate_components(check),
        generate_supergroups(check),
        generate_package_groups(check),
        generate_skills(check),
        generate_links(check),
        generate_models(check),
        generate_profiles(check),
        generate_cli_help(check),
        generate_maintainer_copies(check),
    ]
    if not all(results):
        print("generate_reference: FAILED", file=sys.stderr)
        return 1
    print("generate_reference: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
