"""Shared loaders for DOTS help / completion / man generators.

Keep this module dependency-free (stdlib only) so generators stay offline.
"""

from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]


def load_toml(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    with path.open("rb") as fh:
        return tomllib.load(fh)


def version() -> str:
    vf = ROOT / "VERSION"
    if vf.is_file():
        return vf.read_text(encoding="utf-8").strip() or "0"
    return "0"


def commands() -> list[dict[str, Any]]:
    data = load_toml(ROOT / "configs" / "help" / "commands.toml")
    return list(data.get("commands") or [])


def topics() -> list[dict[str, Any]]:
    data = load_toml(ROOT / "configs" / "help" / "topics.toml")
    rows = list(data.get("topics") or [])
    return sorted(rows, key=lambda r: int(r.get("order") or 999))


def components() -> list[dict[str, Any]]:
    data = load_toml(ROOT / "configs" / "components.toml")
    return list(data.get("components") or [])


def supergroups() -> list[dict[str, Any]]:
    data = load_toml(ROOT / "configs" / "components.toml")
    raw = data.get("supergroups") or []
    if isinstance(raw, list):
        return [r for r in raw if isinstance(r, dict)]
    if isinstance(raw, dict):
        out: list[dict[str, Any]] = []
        for sid, meta in raw.items():
            if isinstance(meta, dict):
                out.append({"id": sid, **meta})
            elif isinstance(meta, list):
                out.append({"id": sid, "members": meta})
        return out
    return []


def package_groups() -> list[dict[str, Any]]:
    data = load_toml(ROOT / "configs" / "packages" / "groups.toml")
    return list(data.get("groups") or [])


def lsp_servers() -> list[dict[str, Any]]:
    data = load_toml(ROOT / "configs" / "lsp" / "servers.toml")
    return list(data.get("servers") or [])


def keybindings() -> list[dict[str, Any]]:
    data = load_toml(ROOT / "configs" / "help" / "keybindings.toml")
    return list(data.get("bindings") or [])


def builtin_profiles() -> list[str]:
    d = ROOT / "configs" / "bootstrap" / "profiles"
    if not d.is_dir():
        return ["base", "home", "work", "server", "all"]
    names = sorted(p.stem for p in d.glob("*.toml") if p.stem != "all")
    # keep conventional order; append all last if present
    preferred = ["base", "home", "work", "server", "all"]
    out: list[str] = []
    for p in preferred:
        if (d / f"{p}.toml").is_file() and p not in out:
            out.append(p)
    for n in names:
        if n not in out:
            out.append(n)
    if (d / "all.toml").is_file() and "all" not in out:
        out.append("all")
    return out


def model_providers() -> list[str]:
    """Providers used by pull_models / models menu (registry + known set)."""
    known = ["ollama", "llamacpp", "drawthings", "fluidvoice", "all"]
    data = load_toml(ROOT / "configs" / "models.toml")
    found: set[str] = set()
    for m in data.get("models") or []:
        if isinstance(m, dict) and m.get("provider"):
            found.add(str(m["provider"]))
    out = [p for p in known if p == "all" or p in found or p in known]
    # stable unique
    seen: set[str] = set()
    uniq: list[str] = []
    for p in known:
        if p not in seen:
            uniq.append(p)
            seen.add(p)
    for p in sorted(found):
        if p not in seen:
            uniq.append(p)
            seen.add(p)
    return uniq


def model_tiers() -> list[str]:
    return ["auto", "minimal", "balanced", "large", "max"]


def short_desc(text: str, limit: int = 48) -> str:
    text = (text or "").strip().replace("\n", " ")
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"
