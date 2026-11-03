"""Topic body loading and search index."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .registry import Registry
from .state import MachineState, gather_state, platform_ok


@dataclass
class SearchHit:
    category: str
    title: str
    topic_id: str
    detail: str = ""


def read_topic_body(reg: Registry, topic: dict) -> str:
    rel = topic.get("body") or ""
    path = reg.root / rel
    if path.is_file():
        return path.read_text(encoding="utf-8", errors="replace")
    return f"_Missing topic body: {rel}_\n"


def overview_dynamic(reg: Registry, st: MachineState) -> str:
    lines = [
        f"# Overview",
        "",
        f"**DOTS {st.version}**",
        "",
        "## Machine",
        "",
        f"| Field | Value |",
        f"|-------|-------|",
        f"| Host | `{st.host}` |",
        f"| Platform | `{st.os_name}` / `{st.arch}` |",
        f"| Active profile | `{st.profile or '(none)'}` |",
        f"| Shell | `{st.shell}` |",
        f"| Multiplexer | `{st.multiplexer or '(unset)'}` |",
        "",
        "## Environment",
        "",
        f"| Field | Value |",
        f"|-------|-------|",
        f"| Components selected | {len(st.active_components)} |",
        f"| Package groups | `{st.package_groups or '(see profile)'}` |",
        f"| AI selected | `{'yes' if any(c in st.active_components for c in ('hermes','ollama','ai-server','opencode','codex','cursor')) else 'no'}` |",
        f"| LSP selected | `{'yes' if 'lsp' in st.active_components else 'no'}` |",
        "",
        "## Recovery",
        "",
        f"- Latest backup: `{st.backup_latest or '(none)'}`",
        f"- Snapshot count: **{st.backup_count}**",
        f"- Legacy `~/.old_dots`: **{'present' if st.legacy_old_dots else 'absent'}**",
        "",
        "## Fuzzy completion (this host)",
        "",
        f"- fzf {st.mark(st.fzf)}",
        f"- fd {st.mark(st.fd)}",
        f"- fzf-tab {st.mark(st.fzf_tab)}",
        f"- shell `{st.shell}`",
        "",
    ]
    return "\n".join(lines)


def components_dynamic(reg: Registry, st: MachineState) -> str:
    lines = ["# Components", "", "From `configs/components.toml`:", ""]
    for row in reg.component_rows():
        cid = row.get("id", "")
        label = row.get("label", cid)
        selected = cid in st.active_components
        plats = row.get("platforms") or []
        ok = platform_ok(list(plats), st.os_name)
        mark = "✓" if selected else ("○" if ok else "×")
        lines.append(f"## {mark} `{cid}` — {label}")
        lines.append("")
        if row.get("description"):
            lines.append(row["description"])
            lines.append("")
        lines.append(f"- category: `{row.get('category', '')}`")
        lines.append(f"- platforms: `{', '.join(plats)}`")
        lines.append(f"- selected: **{'yes' if selected else 'no'}**")
        if not ok:
            lines.append(f"- unavailable on this host (`{st.os_name}`)")
        lines.append("")
        lines.append("```bash")
        lines.append(f"./dots setup --with {cid}")
        lines.append("```")
        lines.append("")
    return "\n".join(lines)


def packages_dynamic(reg: Registry, st: MachineState) -> str:
    lines = ["# Packages", "", "From `configs/packages/groups.toml`:", ""]
    active = set((st.package_groups or "").replace(",", " ").split())
    for g in reg.package_groups():
        name = g.get("name", "")
        mark = "✓" if name in active else "○"
        lines.append(f"## {mark} `{name}`")
        lines.append("")
        lines.append(g.get("description") or "")
        lines.append("")
        req = ", ".join(g.get("required") or []) or "(none)"
        opt = ", ".join(g.get("optional") or []) or "(none)"
        lines.append(f"- required: {req}")
        lines.append(f"- optional: {opt}")
        lines.append("")
    lines.extend(
        [
            "## Commands",
            "",
            "```bash",
            "./dots packages groups",
            "./dots packages group modern",
            "./dots packages status",
            "./dots packages explain bat",
            "```",
            "",
        ]
    )
    return "\n".join(lines)


def lsp_dynamic(reg: Registry, st: MachineState) -> str:
    lines = ["# Language Servers", "", "| Language | Binary | Present |", "|----------|--------|---------|"]
    for s in reg.lsp_servers():
        binary = s.get("binary") or ""
        label = s.get("label") or s.get("id") or ""
        present = shutil_which(binary)
        lines.append(f"| {label} | `{binary}` | {('✓' if present else '○')} |")
    lines.extend(["", "```bash", "./dots lsp status", "```", ""])
    return "\n".join(lines)


def shutil_which(name: str) -> bool:
    import shutil

    return bool(name) and shutil.which(name) is not None


def supergroups_dynamic(reg: Registry, st: MachineState) -> str:
    lines = ["# Supergroups", ""]
    rows = reg.supergroup_rows()
    if not rows:
        lines.append("_No supergroups declared._")
        lines.append("")
    for item in rows:
        sid = item.get("id", "")
        members = item.get("members") or item.get("components") or []
        label = item.get("label") or sid
        lines.append(f"## `{sid}` — {label}")
        lines.append("")
        if item.get("description"):
            lines.append(str(item["description"]))
            lines.append("")
        lines.append("Members: " + ", ".join(f"`{m}`" for m in members))
        lines.append("")
        for m in members:
            mark = "✓" if m in st.active_components else "○"
            lines.append(f"- {mark} `{m}`")
        lines.append("")
    lines.extend(
        [
            "```bash",
            "./dots setup --with ai",
            "./dots setup --with ai --without lsp",
            "```",
            "",
        ]
    )
    return "\n".join(lines)


def commands_dynamic(reg: Registry, st: MachineState) -> str:
    lines = ["# Commands", "", f"DOTS **{st.version}**", ""]
    for cmd in reg.command_rows():
        mut = "mutating" if cmd.get("mutating") else "read-only"
        lines.append(f"## `{cmd.get('name')}` ({mut})")
        lines.append("")
        lines.append(cmd.get("description") or "")
        lines.append("")
        lines.append(f"Usage: `{cmd.get('usage')}`")
        lines.append("")
        for ex in cmd.get("examples") or []:
            lines.append(f"- `{ex.get('command')}` — {ex.get('description', '')}")
        lines.append("")
    return "\n".join(lines)


def completion_dynamic(reg: Registry, st: MachineState) -> str:
    base = read_topic_body(reg, {"body": "docs/help/completion.md"})
    extra = "\n".join(
        [
            "",
            "## Installed on this host",
            "",
            f"| Tool | State |",
            f"|------|-------|",
            f"| fzf | {st.mark(st.fzf)} |",
            f"| fd | {st.mark(st.fd)} |",
            f"| fzf-tab | {st.mark(st.fzf_tab)} |",
            f"| shell | `{st.shell}` |",
            f"| Tab owner | `{'fzf-tab' if st.fzf_tab and st.shell == 'zsh' else 'normal/fzf'}` |",
            "",
        ]
    )
    return base.rstrip() + "\n" + extra


_AI_CATEGORIES = frozenset(
    {"ai_client", "ai_runtime", "image_ai", "voice_ai", "developer_tooling"}
)
_AI_IDS = frozenset(
    {
        "hermes",
        "ollama",
        "llamacpp",
        "drawthings",
        "opencode",
        "codex",
        "cursor",
        "fluidvoice",
        "ai-server",
        "lsp",
    }
)


def ai_dynamic(reg: Registry, st: MachineState) -> str:
    base = read_topic_body(reg, {"body": "docs/help/ai.md"})
    lines = [
        "",
        "## On this host",
        "",
        "| Component | Selected | Supported | Kind |",
        "|-----------|----------|-----------|------|",
    ]
    for row in reg.component_rows():
        cid = str(row.get("id") or "")
        cat = str(row.get("category") or "")
        if cid not in _AI_IDS and cat not in _AI_CATEGORIES:
            continue
        plats = row.get("platforms") or []
        ok = platform_ok(list(plats), st.os_name)
        sel = "✓" if cid in st.active_components else "○"
        supp = "yes" if ok else f"unavailable on {st.os_name}"
        kind = "cloud" if row.get("cloud") else "local"
        lines.append(f"| `{cid}` | {sel} | {supp} | {kind} |")
    lines.extend(["", "```bash", "./dots setup --with ai", "./dots ai status", "```", ""])
    return base.rstrip() + "\n" + "\n".join(lines)


def models_dynamic(reg: Registry, st: MachineState) -> str:
    base = read_topic_body(reg, {"body": "docs/help/models.md"})
    policy = reg.models.get("policy") or {}
    lines = [
        "",
        "## Policy (configs/models.toml)",
        "",
        f"- reserve_memory_gb: `{policy.get('reserve_memory_gb', '—')}`",
        f"- tier_balanced_max_ram_gb: `{policy.get('tier_balanced_max_ram_gb', '—')}`",
        "",
        "Default catalog entries (ids only; no network):",
        "",
    ]
    for m in (reg.models.get("models") or [])[:12]:
        if not isinstance(m, dict):
            continue
        lines.append(
            f"- `{m.get('id')}` — provider `{m.get('provider')}` tier `{m.get('tier')}`"
        )
    overlay = st.home / ".config" / "dots" / "models.toml"
    lines.append("")
    lines.append(f"User overlay: `{'present' if overlay.is_file() else 'absent'}` (`~/.config/dots/models.toml`)")
    lines.extend(
        [
            "",
            "```bash",
            "./dots models",
            "./dots models discover",
            "./scripts/pull_models.sh --list",
            "```",
            "",
        ]
    )
    return base.rstrip() + "\n" + "\n".join(lines)


def skills_dynamic(reg: Registry, st: MachineState) -> str:
    base = read_topic_body(reg, {"body": "docs/help/skills.md"})
    lines = ["", "## Packs (configs/skills/manifest.toml)", ""]
    packs = reg.skills.get("packs") or {}
    if isinstance(packs, dict):
        for name, meta in packs.items():
            if not isinstance(meta, dict):
                continue
            desc = meta.get("description") or ""
            groups = meta.get("groups") or []
            lines.append(f"### `{name}`")
            if desc:
                lines.append(str(desc))
            if groups:
                lines.append("Groups: " + ", ".join(f"`{g}`" for g in groups))
            sel = "✓" if name in st.active_components else "○"
            lines.append(f"Component selected: {sel}")
            lines.append("")
    elif isinstance(packs, list):
        for p in packs:
            if not isinstance(p, dict):
                continue
            lines.append(f"### `{p.get('id') or p.get('name')}`")
            lines.append(str(p.get("description") or ""))
            lines.append("")
    store = st.home / ".agents" / "skills"
    lines.append(f"Installed path: `{store}` ({'present' if store.is_dir() else 'absent'})")
    lines.extend(
        [
            "",
            "```bash",
            "./dots setup --with skills",
            "./dots setup --with ai-skills",
            "```",
            "",
        ]
    )
    return base.rstrip() + "\n" + "\n".join(lines)


def profiles_dynamic(reg: Registry, st: MachineState) -> str:
    base = read_topic_body(reg, {"body": "docs/help/profiles.md"})
    builtins = ["base", "home", "work", "server", "all"]
    lines = ["", "## Builtin profiles", ""]
    for name in builtins:
        mark = "✓ active" if st.profile == name else "○"
        path = reg.root / "configs" / "bootstrap" / "profiles" / f"{name}.toml"
        exists = "present" if path.is_file() else "missing"
        lines.append(f"- {mark} `{name}` ({exists})")
    custom_dir = st.home / ".config" / "dots" / "profiles"
    lines.extend(["", "## Custom profiles (`~/.config/dots/profiles/`)", ""])
    if custom_dir.is_dir():
        customs = sorted(custom_dir.glob("*.toml"))
        if customs:
            for p in customs:
                mark = "✓ active" if st.profile_file.endswith(p.name) or st.profile == p.stem else "○"
                lines.append(f"- {mark} `{p.stem}`")
        else:
            lines.append("_none_")
    else:
        lines.append("_directory absent_")
    lines.extend(
        [
            "",
            f"Active: **{st.profile or '(none)'}**",
            "",
            "```bash",
            "./dots profile",
            "./bootstrap.sh --profile home --show",
            "```",
            "",
        ]
    )
    return base.rstrip() + "\n" + "\n".join(lines)


def backup_dynamic(reg: Registry, st: MachineState) -> str:
    base = read_topic_body(reg, {"body": "docs/help/backup.md"})
    extra = "\n".join(
        [
            "",
            "## This host",
            "",
            f"- Latest snapshot: `{st.backup_latest or '(none)'}`",
            f"- Snapshot count: **{st.backup_count}**",
            f"- Legacy `~/.old_dots`: **{'present' if st.legacy_old_dots else 'absent'}**",
            "",
            "```bash",
            "./dots backup --name before-change",
            "./dots backups",
            "./dots restore",
            "```",
            "",
        ]
    )
    return base.rstrip() + "\n" + extra


DYNAMIC = {
    "overview": overview_dynamic,
    "components": components_dynamic,
    "packages": packages_dynamic,
    "lsp": lsp_dynamic,
    "supergroups": supergroups_dynamic,
    "commands": commands_dynamic,
    "completion": completion_dynamic,
    "ai": ai_dynamic,
    "models": models_dynamic,
    "skills": skills_dynamic,
    "profiles": profiles_dynamic,
    "backup": backup_dynamic,
}


def render_topic(reg: Registry, topic_id: str, st: MachineState | None = None) -> str:
    st = st or gather_state(reg)
    topic = next((t for t in reg.topic_rows() if t.get("id") == topic_id), None)
    if topic is None:
        return f"# Unknown topic `{topic_id}`\n"
    if topic_id in DYNAMIC:
        return DYNAMIC[topic_id](reg, st)
    return read_topic_body(reg, topic)


def search(reg: Registry, query: str, st: MachineState | None = None) -> list[SearchHit]:
    q = query.strip().lower()
    if not q:
        return []
    st = st or gather_state(reg)
    hits: list[SearchHit] = []
    for t in reg.topic_rows():
        blob = " ".join(
            [
                str(t.get("id", "")),
                str(t.get("title", "")),
                " ".join(t.get("keywords") or []),
            ]
        ).lower()
        if q in blob:
            hits.append(
                SearchHit("topic", str(t.get("title")), str(t.get("id")), ",".join(t.get("keywords") or []))
            )
    for c in reg.command_rows():
        blob = " ".join(
            [
                str(c.get("name", "")),
                str(c.get("usage", "")),
                str(c.get("description", "")),
                str(c.get("category", "")),
            ]
        ).lower()
        if q in blob:
            hits.append(
                SearchHit("command", str(c.get("name")), "commands", str(c.get("description", ""))[:80])
            )
    for row in reg.component_rows():
        blob = f"{row.get('id','')} {row.get('label','')} {row.get('description','')}".lower()
        if q in blob:
            hits.append(
                SearchHit("component", str(row.get("id")), "components", str(row.get("label", "")))
            )
    for g in reg.package_groups():
        blob = f"{g.get('name','')} {g.get('description','')}".lower()
        if q in blob:
            hits.append(SearchHit("package-group", str(g.get("name")), "packages", str(g.get("description", ""))))
    for s in reg.lsp_servers():
        blob = f"{s.get('id','')} {s.get('label','')} {s.get('binary','')}".lower()
        if q in blob:
            hits.append(SearchHit("lsp", str(s.get("id")), "lsp", str(s.get("label", ""))))
    return hits[:40]
