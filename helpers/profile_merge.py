"""Shared profile inheritance merge (groups, components, explicit packages).

Consumed by profile_edit heredocs and package_truth — not a second ownership catalog.
"""

from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Any


def str_list(val: Any) -> list[str]:
    if not val:
        return []
    return [str(x).strip() for x in val if str(x).strip()]


def resolve_extends_path(ext: str, from_path: Path, *, builtin_dir: Path, user_dir: Path) -> Path:
    ext = ext.strip()
    if ext.endswith(".toml") or "/" in ext or ext.startswith("~") or ext.startswith("."):
        p = Path(ext).expanduser()
        if not p.is_absolute():
            p = (from_path.parent / p).resolve()
        return p
    b = builtin_dir / f"{ext}.toml"
    if b.is_file():
        return b.resolve()
    u = user_dir / f"{ext}.toml"
    if u.is_file():
        return u.resolve()
    raise SystemExit(f"Error: unknown extends base '{ext}' in {from_path}")


def load_chain(leaf: Path, *, builtin_dir: Path, user_dir: Path) -> list[tuple[Path, dict[str, Any]]]:
    chain: list[tuple[Path, dict[str, Any]]] = []
    seen: set[str] = set()
    cur = leaf.resolve()
    while True:
        k = str(cur)
        if k in seen:
            raise SystemExit(f"Error: inheritance loop at {cur}")
        seen.add(k)
        data = tomllib.loads(cur.read_text(encoding="utf-8"))
        chain.append((cur, data))
        ext = (data.get("profile") or {}).get("extends") or ""
        if not isinstance(ext, str) or not ext.strip():
            break
        cur = resolve_extends_path(ext, cur, builtin_dir=builtin_dir, user_dir=user_dir)
    chain.reverse()
    return chain


def effective_state(
    chain: list[tuple[Path, dict[str, Any]]],
    *,
    comps_data: dict[str, Any],
    builtin_dir: Path,
) -> dict[str, Any]:
    supergroups = {
        str(s.get("id") or "").strip(): [str(m).strip() for m in (s.get("members") or []) if str(m).strip()]
        for s in (comps_data.get("supergroups") or []) if s.get("id")
    }
    pkgs: list[str] = []
    pkg_include: list[str] = []
    pkg_exclude: set[str] = set()
    with_raw: list[str] = []
    without_raw: set[str] = set()
    include_all = False
    pkg_explicit = False
    prof_name = ""
    for _p, data in chain:
        prof = data.get("profile") or {}
        if prof.get("name"):
            prof_name = str(prof["name"]).strip()
        if prof.get("include_all_optional"):
            include_all = True
        if "packages" in prof and prof["packages"] is not None:
            pkgs = str_list(prof["packages"])
            pkg_explicit = True
        ptbl = data.get("packages") or {}
        for g in str_list(ptbl.get("add")):
            if g not in pkgs:
                pkgs.append(g)
            pkg_explicit = True
        for g in str_list(ptbl.get("remove")):
            pkgs = [x for x in pkgs if x != g]
            pkg_explicit = True
        if "groups" in ptbl and ptbl["groups"] is not None:
            pkgs = str_list(ptbl["groups"])
            pkg_explicit = True
        for p in str_list(ptbl.get("include")):
            if p not in pkg_exclude and p not in pkg_include:
                pkg_include.append(p)
        for p in str_list(ptbl.get("exclude")):
            pkg_exclude.add(p)
            pkg_include = [x for x in pkg_include if x != p]
        for w in str_list(prof.get("with")):
            if w not in with_raw:
                with_raw.append(w)
        for o in str_list(prof.get("without")):
            without_raw.add(o)
        ctbl = data.get("components") or {}
        for w in str_list(ctbl.get("with")):
            if w not in with_raw:
                with_raw.append(w)
        for o in str_list(ctbl.get("without")):
            without_raw.add(o)

    if include_all:
        for c in comps_data.get("components") or []:
            cid = str(c.get("id") or "").strip()
            if cid and not c.get("omit_from_all") and cid not in with_raw:
                with_raw.append(cid)

    if not pkg_explicit and prof_name:
        fb = builtin_dir / f"{prof_name}.toml"
        if fb.is_file():
            fb_data = tomllib.loads(fb.read_text(encoding="utf-8"))
            pkgs = str_list((fb_data.get("profile") or {}).get("packages"))
    if not pkg_explicit and not pkgs:
        pkgs = ["core", "modern"]

    expanded_without: set[str] = set()
    for o in without_raw:
        if o in supergroups:
            expanded_without.update(supergroups[o])
        else:
            expanded_without.add(o)

    expanded_with: list[str] = []
    for w in with_raw:
        for m in supergroups.get(w, [w]):
            if m not in expanded_without and m not in expanded_with:
                expanded_with.append(m)

    return {
        "groups": pkgs,
        "with_raw": with_raw,
        "without_raw": without_raw,
        "expanded_with": expanded_with,
        "expanded_without": expanded_without,
        "pkg_include": pkg_include,
        "pkg_exclude": pkg_exclude,
        "supergroups": supergroups,
    }