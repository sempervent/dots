#!/usr/bin/env python3
"""Canonical DOTS package-level installability, state, and registry audit engine.

Single source of truth consumed by Bash CLIs (`dots`, `helpers/profile_edit.sh`,
`helpers/packages.sh`, `helpers/package_state.sh`) and indirectly by the TUI.

Distinct concepts preserved throughout:
  - known:              package appears in a DOTS registry or owning Brewfile
  - selected:           owning group or component is part of desired state
  - installable:        DOTS has an authoritative install mechanism on this platform
  - platform_supported: capability/group is supported on this platform
  - unsupported:        known capability has no DOTS-supported install route here
  - installed:          package/binary is currently present on the host
  - external:           present on host, not owned by DOTS's selected install mechanism
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Any


BREWFILE_TOKEN_RE = re.compile(r'^(brew|cask)\s+"([^"]+)"')
LINUX_PKG_MGRS = ("apt", "dnf", "pacman", "xbps")


def _repo_root() -> Path:
    env = os.environ.get("DOTS_DIR") or os.environ.get("REPO_DIR") or os.environ.get("DIR")
    if env:
        return Path(env).resolve()
    return Path(__file__).resolve().parents[1]


def _groups_registry_path(root: Path) -> Path:
    ov = os.environ.get("DOTS_GROUPS_REGISTRY", "").strip()
    if ov and Path(ov).is_file():
        return Path(ov)
    return root / "configs" / "packages" / "groups.toml"


def _components_registry_path(root: Path) -> Path:
    ov = os.environ.get("DOTS_COMPONENTS_REGISTRY", "").strip()
    if ov and Path(ov).is_file():
        return Path(ov)
    return root / "configs" / "components.toml"


def _load_toml(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    return tomllib.loads(path.read_text(encoding="utf-8"))


def _parse_brewfile(path: Path) -> tuple[list[str], list[str]]:
    formulae: list[str] = []
    casks: list[str] = []
    if not path.is_file():
        return formulae, casks
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        m = BREWFILE_TOKEN_RE.match(line)
        if not m:
            continue
        kind, tok = m.group(1), m.group(2).strip()
        if not tok:
            continue
        if kind == "brew":
            formulae.append(tok)
        else:
            casks.append(tok)
    return formulae, casks


def detect_platform() -> tuple[str, str, str]:
    """Return (os_name, darwin_major, pkg_mgr)."""
    forced_os = os.environ.get("DOTS_FORCE_OS", "").strip().lower()
    if forced_os in ("darwin", "linux"):
        os_name = forced_os
    else:
        os_name = "darwin" if sys.platform == "darwin" else "linux"

    darwin_major = os.environ.get("DOTS_FORCE_DARWIN_MAJOR", "").strip()
    if not darwin_major and os_name == "darwin" and sys.platform == "darwin":
        try:
            out = subprocess.check_output(["sw_vers", "-productVersion"], text=True, timeout=5).strip()
            darwin_major = out.split(".", 1)[0]
        except Exception:
            darwin_major = ""

    forced_mgr = os.environ.get("DOTS_FORCE_PKG_MGR", "").strip().lower()
    if forced_mgr:
        if forced_mgr == "homebrew":
            forced_mgr = "brew"
        return os_name, darwin_major, forced_mgr

    if os_name == "darwin":
        return os_name, darwin_major, "brew"

    # Linux (forced or native): do NOT leak macOS /opt/homebrew/bin/brew when DOTS_FORCE_OS=linux
    if not forced_os and shutil.which(os.environ.get("DOTS_BREW_BIN", "brew")):
        return os_name, darwin_major, "brew"

    if shutil.which("apt-get") or shutil.which("apt"):
        return os_name, darwin_major, "apt"
    if shutil.which("pacman"):
        return os_name, darwin_major, "pacman"
    if shutil.which("xbps-install"):
        return os_name, darwin_major, "xbps"
    if shutil.which("dnf") or shutil.which("yum"):
        return os_name, darwin_major, "dnf"
    return os_name, darwin_major, "unknown"


def _load_linux_map(root: Path, mgr: str) -> dict[str, str]:
    if mgr not in LINUX_PKG_MGRS:
        return {}
    data = _load_toml(root / "configs" / "packages" / f"{mgr}.toml")
    raw = data.get("packages") or {}
    return {str(k).strip(): str(v).strip() for k, v in raw.items() if str(k).strip()}


def _brew_installed_sets() -> tuple[bool, set[str], set[str]]:
    """Return (have_lists, formulae_shorts, casks_shorts)."""
    has_mock_f = "DOTS_PKG_MOCK_FORMULAE" in os.environ
    has_mock_c = "DOTS_PKG_MOCK_CASKS" in os.environ
    has_env_f = "INST_F" in os.environ
    has_env_c = "INST_C" in os.environ

    if has_env_f or has_env_c:
        raw_f = os.environ.get("INST_F", "")
        raw_c = os.environ.get("INST_C", "")
        f_set = {x.strip().split("/")[-1] for x in raw_f.splitlines() if x.strip()}
        c_set = {x.strip().split("/")[-1] for x in raw_c.splitlines() if x.strip()}
        return True, f_set, c_set

    if has_mock_f or has_mock_c:
        raw_f = os.environ.get("DOTS_PKG_MOCK_FORMULAE", "")
        raw_c = os.environ.get("DOTS_PKG_MOCK_CASKS", "")
        f_set = {x.strip().split("/")[-1] for x in raw_f.splitlines() if x.strip()}
        c_set = {x.strip().split("/")[-1] for x in raw_c.splitlines() if x.strip()}
        return True, f_set, c_set

    brew_bin = os.environ.get("DOTS_BREW_BIN", "brew")
    if shutil.which(brew_bin):
        f_set: set[str] = set()
        c_set: set[str] = set()
        try:
            out_f = subprocess.check_output([brew_bin, "list", "--formula", "-1"], text=True, stderr=subprocess.DEVNULL, timeout=15)
            f_set = {x.strip().split("/")[-1] for x in out_f.splitlines() if x.strip()}
        except Exception:
            pass
        try:
            out_c = subprocess.check_output([brew_bin, "list", "--cask", "-1"], text=True, stderr=subprocess.DEVNULL, timeout=15)
            c_set = {x.strip().split("/")[-1] for x in out_c.splitlines() if x.strip()}
        except Exception:
            pass
        return True, f_set, c_set

    return False, set(), set()


def _native_installed_set(mgr: str) -> tuple[bool, set[str]]:
    if "DOTS_PKG_MOCK_NATIVE_INSTALLED" in os.environ:
        raw = os.environ.get("DOTS_PKG_MOCK_NATIVE_INSTALLED", "")
        return True, {x.strip() for x in raw.splitlines() if x.strip()}
    if os.environ.get("DOTS_PKG_DISABLE_HOST_WHICH") == "1":
        return False, set()
    # Live non-mutating native query only if running natively on that OS
    if mgr == "apt" and shutil.which("dpkg-query"):
        try:
            out = subprocess.check_output(
                ["dpkg-query", "-W", "-f=${Package}\n"],
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=10,
            )
            return True, {x.strip() for x in out.splitlines() if x.strip()}
        except Exception:
            return False, set()
    if mgr == "pacman" and shutil.which("pacman"):
        try:
            out = subprocess.check_output(["pacman", "-Qq"], text=True, stderr=subprocess.DEVNULL, timeout=10)
            return True, {x.strip() for x in out.splitlines() if x.strip()}
        except Exception:
            return False, set()
    if mgr == "dnf" and shutil.which("rpm"):
        try:
            out = subprocess.check_output(
                ["rpm", "-qa", "--qf", "%{NAME}\n"],
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=10,
            )
            return True, {x.strip() for x in out.splitlines() if x.strip()}
        except Exception:
            return False, set()
    if mgr == "xbps" and shutil.which("xbps-query"):
        try:
            out = subprocess.check_output(["xbps-query", "-l"], text=True, stderr=subprocess.DEVNULL, timeout=10)
            pkgs: set[str] = set()
            for line in out.splitlines():
                parts = line.split()
                if len(parts) >= 2:
                    # format: "ii pkg-1.2_1 desc"
                    name_ver = parts[1]
                    pkgs.add(name_ver.rsplit("-", 1)[0])
            return True, pkgs
        except Exception:
            return False, set()
    return False, set()


def _mock_external_bins() -> set[str]:
    raw = os.environ.get("DOTS_PKG_MOCK_EXTERNAL_BINS", "")
    return {x.strip() for x in raw.splitlines() if x.strip()}


def _mock_helper_installed() -> tuple[bool, set[str]]:
    if "DOTS_PKG_MOCK_HELPER_INSTALLED" in os.environ:
        raw = os.environ.get("DOTS_PKG_MOCK_HELPER_INSTALLED", "")
        return True, {x.strip() for x in raw.splitlines() if x.strip()}
    return False, set()


def _binary_present(pkg_id: str, bin_name: str, short_tok: str | None) -> bool:
    ext_mocks = _mock_external_bins()
    candidates = [x for x in (pkg_id, bin_name, short_tok or "") if x]
    if any(c in ext_mocks for c in candidates):
        return True
    if os.environ.get("DOTS_PKG_DISABLE_HOST_WHICH") == "1":
        return False
    if bin_name == "":
        return False
    return shutil.which(bin_name or pkg_id) is not None


def _comp_supported(comp: dict[str, Any], os_name: str, darwin_major: str) -> tuple[bool, str]:
    plats = [str(p).strip().lower() for p in (comp.get("platforms") or ["darwin", "linux"])]
    if os_name not in plats:
        reason = "macOS only" if plats == ["darwin"] else f"unsupported on {os_name}"
        return False, reason
    if os_name == "darwin" and comp.get("min_darwin") is not None:
        try:
            need = int(str(comp["min_darwin"]).split(".")[0])
            have = int(darwin_major) if darwin_major else 0
        except ValueError:
            return False, f"requires macOS {comp['min_darwin']}+"
        if have < need:
            return False, f"requires macOS {comp['min_darwin']}+ (host {darwin_major or '?'})"
    return True, ""


def _evaluate_group_package(
    pkg_id: str,
    group_name: str,
    pkg_class: str,
    selected: bool,
    os_name: str,
    pkg_mgr: str,
    bf_formulae: list[str],
    bf_casks: list[str],
    brew_aliases: dict[str, str],
    binaries_map: dict[str, str],
    helper_pkgs: dict[str, dict[str, Any]],
    linux_map: dict[str, str],
    have_brew_lists: bool,
    inst_f: set[str],
    inst_c: set[str],
    have_native_list: bool,
    inst_native: set[str],
    have_helper_mock: bool,
    inst_helper: set[str],
) -> dict[str, Any]:
    required = pkg_class == "required"
    bf_f_by_short = {t.split("/")[-1]: t for t in bf_formulae}
    bf_c_by_short = {t.split("/")[-1]: t for t in bf_casks}

    bin_name = binaries_map.get(pkg_id, pkg_id)
    helper_spec = helper_pkgs.get(pkg_id)

    installable = False
    install_method = "none"
    install_kind = "none"
    install_token: str | None = None
    unsupported_reason: str | None = None

    # 1. Check helper-managed package first if owned by this group and supports OS
    if helper_spec and str(helper_spec.get("owner") or "") == f"group:{group_name}":
        plats = [str(p).strip().lower() for p in (helper_spec.get("platforms") or ["darwin", "linux"])]
        if os_name in plats:
            installable = True
            install_method = str(helper_spec.get("method") or "helper")
            install_kind = "helper"
            install_token = str(helper_spec.get("token") or pkg_id)
        else:
            unsupported_reason = f"{pkg_id} helper ({helper_spec.get('helper')}) unsupported on {os_name}"
    elif pkg_mgr == "brew":
        alias_tok = brew_aliases.get(pkg_id, pkg_id)
        short_cand = alias_tok.split("/")[-1]
        if alias_tok in bf_formulae or short_cand in bf_f_by_short:
            tok = alias_tok if alias_tok in bf_formulae else bf_f_by_short[short_cand]
            installable = True
            install_method = "brew"
            install_kind = "formula"
            install_token = tok
        elif alias_tok in bf_casks or short_cand in bf_c_by_short:
            tok = alias_tok if alias_tok in bf_casks else bf_c_by_short[short_cand]
            installable = True
            install_method = "brew"
            install_kind = "cask"
            install_token = tok
        else:
            unsupported_reason = (
                f"{pkg_id} has no Homebrew formula/cask entry in brew/groups/{group_name}.Brewfile"
            )
    elif pkg_mgr in LINUX_PKG_MGRS:
        if pkg_id in linux_map:
            mapped = linux_map[pkg_id]
            if mapped:
                installable = True
                install_method = pkg_mgr
                install_kind = "native"
                install_token = mapped
            else:
                unsupported_reason = (
                    f"{pkg_id} is mapped empty in configs/packages/{pkg_mgr}.toml (unavailable via {pkg_mgr})"
                )
        else:
            unsupported_reason = f"{pkg_id} has no mapping in configs/packages/{pkg_mgr}.toml"
    else:
        unsupported_reason = f"no supported package manager detected on {os_name} (pkg_mgr={pkg_mgr})"

    # Determine installed + external separately from installability
    short_tok = install_token.split("/")[-1] if install_token else None
    installed = False
    external = False
    bin_present = _binary_present(pkg_id, bin_name, short_tok)

    if install_kind in ("formula", "cask") and have_brew_lists:
        owned_here = (short_tok in inst_f) if install_kind == "formula" else (short_tok in inst_c)
        if owned_here:
            installed = True
            external = False
        elif bin_present:
            installed = True
            external = True
    elif install_kind == "native":
        if have_native_list:
            if install_token in inst_native:
                installed = True
                external = False
            elif bin_present:
                installed = True
                external = True
        elif bin_present:
            installed = True
            external = False
    elif install_kind == "helper":
        if have_helper_mock:
            if pkg_id in inst_helper or (install_token and install_token in inst_helper):
                installed = True
                external = False
            elif bin_present:
                installed = True
                external = True
        elif bin_present:
            installed = True
            external = False
    else:
        # Unsupported on this platform: if binary is present anyway, it is installed + external
        if bin_present:
            installed = True
            external = True

    return {
        "name": pkg_id,
        "owner": f"group:{group_name}",
        "class": pkg_class,
        "required": required,
        "known": True,
        "selected": selected,
        "installed": installed,
        "installable": installable,
        "unsupported": not installable,
        "external": external,
        "platform_supported": installable,
        "install_method": install_method,
        "install_kind": install_kind,
        "install_token": install_token,
        "binary": bin_name,
        "unsupported_reason": unsupported_reason,
    }


def compute_groups_data(
    root: Path,
    pstate: dict[str, Any] | None = None,
    *,
    os_name: str | None = None,
    darwin_major: str | None = None,
    pkg_mgr: str | None = None,
    probe_installed: bool = True,
) -> dict[str, Any]:
    det_os, det_dmajor, det_mgr = detect_platform()
    os_name = os_name or det_os
    darwin_major = darwin_major if darwin_major is not None else det_dmajor
    pkg_mgr = pkg_mgr or det_mgr

    groups_data = _load_toml(_groups_registry_path(root))
    brew_aliases = {
        str(k).strip(): str(v).strip()
        for k, v in (groups_data.get("brew_aliases") or {}).items()
        if str(k).strip() and str(v).strip()
    }
    binaries_map = {
        str(k).strip(): str(v).strip()
        for k, v in (groups_data.get("binaries") or {}).items()
        if str(k).strip()
    }
    helper_pkgs = {
        str(k).strip(): dict(v)
        for k, v in (groups_data.get("helper_packages") or {}).items()
        if str(k).strip() and isinstance(v, dict)
    }

    linux_map = _load_linux_map(root, pkg_mgr)
    if probe_installed:
        have_brew_lists, inst_f, inst_c = _brew_installed_sets() if pkg_mgr == "brew" else (False, set(), set())
        have_native_list, inst_native = _native_installed_set(pkg_mgr) if pkg_mgr in LINUX_PKG_MGRS else (False, set())
        have_helper_mock, inst_helper = _mock_helper_installed()
    else:
        have_brew_lists, inst_f, inst_c = False, set(), set()
        have_native_list, inst_native = False, set()
        have_helper_mock, inst_helper = False, set()

    grp_states = (pstate or {}).get("groups") or {}

    out_groups: list[dict[str, Any]] = []
    for g in groups_data.get("groups") or []:
        name = str(g.get("name") or "").strip()
        if not name:
            continue
        req = [str(x).strip() for x in (g.get("required") or []) + (g.get("tools") or []) if str(x).strip()]
        opt = [str(x).strip() for x in (g.get("optional") or []) if str(x).strip()]
        comp = [str(x).strip() for x in (g.get("brew_companions") or []) if str(x).strip()]

        bf_rel = f"brew/groups/{name}.Brewfile"
        bf_f, bf_c = _parse_brewfile(root / bf_rel)

        # Deduplicate aliases: if alias target is in Brewfile, keep logical id from req/opt
        aliased_targets = {brew_aliases[x] for x in req + opt if x in brew_aliases}
        aliased_shorts = {t.split("/")[-1] for t in aliased_targets}

        entries: list[tuple[str, str]] = []
        seen_ids: set[str] = set()
        for x in req:
            if x not in seen_ids:
                seen_ids.add(x)
                entries.append((x, "required"))
        for x in opt:
            if x not in seen_ids:
                seen_ids.add(x)
                entries.append((x, "optional"))
        for x in comp:
            if x not in seen_ids and x not in aliased_targets and x.split("/")[-1] not in aliased_shorts:
                seen_ids.add(x)
                entries.append((x, "companion"))
        for x in bf_f + bf_c:
            short = x.split("/")[-1]
            if x not in seen_ids and short not in seen_ids and x not in aliased_targets and short not in aliased_shorts:
                seen_ids.add(x)
                entries.append((x, "companion"))

        sel_state = (grp_states.get(name) or {}).get("state") or "absent"
        selected = sel_state in ("inherited", "local")

        pkg_details = [
            _evaluate_group_package(
                pkg_id=pid,
                group_name=name,
                pkg_class=pcls,
                selected=selected,
                os_name=os_name,
                pkg_mgr=pkg_mgr,
                bf_formulae=bf_f,
                bf_casks=bf_c,
                brew_aliases=brew_aliases,
                binaries_map=binaries_map,
                helper_pkgs=helper_pkgs,
                linux_map=linux_map,
                have_brew_lists=have_brew_lists,
                inst_f=inst_f,
                inst_c=inst_c,
                have_native_list=have_native_list,
                inst_native=inst_native,
                have_helper_mock=have_helper_mock,
                inst_helper=inst_helper,
            )
            for pid, pcls in entries
        ]

        supported_count = sum(1 for p in pkg_details if p["installable"])
        unsupported_pkgs = [p["name"] for p in pkg_details if not p["installable"]]
        req_unsupported = [p["name"] for p in pkg_details if p["required"] and not p["installable"]]
        inst_count = sum(1 for p in pkg_details if p["installed"])
        ext_count = sum(1 for p in pkg_details if p["external"])

        platform_supported = len(req_unsupported) == 0
        group_unsup_reason = (
            f"required package(s) unsupported on {os_name}/{pkg_mgr}: {', '.join(req_unsupported)}"
            if req_unsupported
            else None
        )

        out_groups.append(
            {
                "name": name,
                "description": str(g.get("description") or "").strip(),
                "brewfile": bf_rel,
                "required": req,
                "optional": opt,
                "brew_companions": comp,
                "required_count": len(req),
                "optional_count": len(opt),
                "package_count": len(pkg_details),
                "supported_package_count": supported_count,
                "unsupported_package_count": len(unsupported_pkgs),
                "installed_count": inst_count,
                "external_count": ext_count,
                "platform_supported": platform_supported,
                "required_unsupported": req_unsupported,
                "unsupported_packages": unsupported_pkgs,
                "unsupported_reason": group_unsup_reason,
                "packages": pkg_details,
                "selected_state": sel_state,
            }
        )

    return {
        "schema_version": 1,
        "profile": (pstate or {}).get("profile"),
        "os": os_name,
        "pkg_mgr": pkg_mgr,
        "groups": out_groups,
    }


def resolve_selector(
    root: Path,
    raw: str,
    pstate: dict[str, Any] | None = None,
) -> dict[str, Any]:
    raw = raw.strip()
    os_name, darwin_major, pkg_mgr = detect_platform()
    gjson = compute_groups_data(root, pstate, os_name=os_name, darwin_major=darwin_major, pkg_mgr=pkg_mgr)
    groups_by_name = {g["name"]: g for g in gjson["groups"]}

    groups_data = _load_toml(_groups_registry_path(root))
    brew_aliases = {
        str(k).strip(): str(v).strip()
        for k, v in (groups_data.get("brew_aliases") or {}).items()
        if str(k).strip() and str(v).strip()
    }
    reverse_aliases = {v.split("/")[-1]: k for k, v in brew_aliases.items()}

    comps_data = _load_toml(_components_registry_path(root))
    comps_by_id: dict[str, dict[str, Any]] = {}
    sgs_by_id: dict[str, dict[str, Any]] = {}
    pkg_owners: dict[str, set[str]] = {}
    comp_pkg_tokens: dict[str, dict[str, Any]] = {}

    for g in gjson["groups"]:
        gname = g["name"]
        for p in g["packages"]:
            pname = p["name"]
            pkg_owners.setdefault(pname, set()).add(f"group:{gname}")
            pkg_owners.setdefault(pname.split("/")[-1], set()).add(f"group:{gname}")
            if pname in brew_aliases:
                al = brew_aliases[pname]
                pkg_owners.setdefault(al, set()).add(f"group:{gname}")
                pkg_owners.setdefault(al.split("/")[-1], set()).add(f"group:{gname}")
            tok = p.get("install_token")
            if tok:
                pkg_owners.setdefault(tok, set()).add(f"group:{gname}")
                pkg_owners.setdefault(tok.split("/")[-1], set()).add(f"group:{gname}")

    for c in comps_data.get("components") or []:
        cid = str(c.get("id") or "").strip()
        if not cid:
            continue
        comps_by_id[cid] = c
        bf_rel = str(c.get("brewfile") or "").strip()
        bf_f, bf_c = _parse_brewfile(root / bf_rel) if bf_rel else ([], [])
        for kind, toks in (("formula", bf_f), ("cask", bf_c)):
            for tok in toks:
                pkg_owners.setdefault(tok, set()).add(f"component:{cid}")
                pkg_owners.setdefault(tok.split("/")[-1], set()).add(f"component:{cid}")
                comp_pkg_tokens[(cid, tok.split("/")[-1])] = {"kind": kind, "token": tok}
        for hp in c.get("helper_packages") or []:
            h = str(hp).strip()
            if h:
                pkg_owners.setdefault(h, set()).add(f"component:{cid}")
                comp_pkg_tokens[(cid, h)] = {"kind": "helper", "token": h}
        for lp in c.get("linux_packages") or []:
            lpkg = str(lp).strip()
            if lpkg:
                pkg_owners.setdefault(lpkg, set()).add(f"component:{cid}")
                comp_pkg_tokens[(cid, lpkg)] = {"kind": "native", "token": lpkg}

    for s in comps_data.get("supergroups") or []:
        sid = str(s.get("id") or "").strip()
        if sid:
            sgs_by_id[sid] = s

    explicit_kind = ""
    target = raw
    if ":" in raw:
        prefix, rest = raw.split(":", 1)
        if prefix in ("group", "component", "supergroup", "package") and rest:
            explicit_kind = prefix
            target = rest.strip()
        else:
            return {
                "status": "unknown",
                "selector": raw,
                "owner_exists": False,
                "os": os_name,
                "pkg_mgr": pkg_mgr,
                "installable": False,
                "platform_supported": False,
                "direct_install_allowed": False,
                "choices": [],
            }

    candidates: list[str] = []
    via_pkg = ""
    if explicit_kind == "group":
        if target in groups_by_name:
            candidates = [f"group:{target}"]
    elif explicit_kind == "component":
        if target in comps_by_id:
            candidates = [f"component:{target}"]
    elif explicit_kind == "supergroup":
        if target in sgs_by_id:
            candidates = [f"supergroup:{target}"]
    elif explicit_kind == "package":
        via_pkg = target
        short = target.split("/")[-1]
        candidates = sorted(set(pkg_owners.get(target, set())) | set(pkg_owners.get(short, set())))
    else:
        direct: list[str] = []
        if target in groups_by_name:
            direct.append(f"group:{target}")
        if target in comps_by_id:
            direct.append(f"component:{target}")
        if target in sgs_by_id:
            direct.append(f"supergroup:{target}")
        short = target.split("/")[-1]
        pkg_found = set(pkg_owners.get(target, set())) | set(pkg_owners.get(short, set()))
        if direct:
            merged = sorted(set(direct) | pkg_found)
            candidates = merged
            if len(merged) > len(direct):
                via_pkg = target
        elif pkg_found:
            candidates = sorted(pkg_found)
            via_pkg = target

    if not candidates:
        return {
            "status": "unknown",
            "selector": raw,
            "owner_exists": False,
            "os": os_name,
            "pkg_mgr": pkg_mgr,
            "installable": False,
            "platform_supported": False,
            "direct_install_allowed": False,
            "choices": [],
        }

    def _find_pkg_in_group(gname: str, pkg_query: str) -> dict[str, Any] | None:
        g = groups_by_name.get(gname)
        if not g:
            return None
        q_short = pkg_query.split("/")[-1]
        mapped_id = reverse_aliases.get(q_short, pkg_query)
        for p in g["packages"]:
            if p["name"] in (pkg_query, q_short, mapped_id):
                return p
            tok = p.get("install_token") or ""
            if tok and (tok == pkg_query or tok.split("/")[-1] == q_short):
                return p
        return None

    if len(candidates) > 1:
        grp_pkgs = {
            c.split(":", 1)[1]: [p["name"] for p in groups_by_name[c.split(":", 1)[1]]["packages"]]
            for c in candidates
            if c.startswith("group:") and c.split(":", 1)[1] in groups_by_name
        }
        pkg_options: list[dict[str, Any]] = []
        any_inst = False
        for c in candidates:
            ckind, cid = c.split(":", 1)
            if ckind == "group":
                pinfo = _find_pkg_in_group(cid, via_pkg or target)
                if pinfo:
                    pkg_options.append(pinfo)
                    if pinfo["installable"]:
                        any_inst = True
            elif ckind == "component":
                sup, reason = _comp_supported(comps_by_id[cid], os_name, darwin_major)
                if sup:
                    any_inst = True
                pkg_options.append(
                    {
                        "name": via_pkg or target,
                        "owner": c,
                        "known": True,
                        "installable": sup,
                        "unsupported": not sup,
                        "platform_supported": sup,
                        "unsupported_reason": reason or None,
                    }
                )
        return {
            "status": "ambiguous",
            "selector": raw,
            "owner_exists": True,
            "os": os_name,
            "pkg_mgr": pkg_mgr,
            "via_package": via_pkg or target,
            "choices": candidates,
            "group_packages": grp_pkgs,
            "installable": any_inst,
            "platform_supported": any_inst,
            "package_options": pkg_options,
        }

    owner = candidates[0]
    kind, oid = owner.split(":", 1)

    if kind == "group":
        g = groups_by_name[oid]
        group_summary = {
            "name": g["name"],
            "package_count": g["package_count"],
            "supported_package_count": g["supported_package_count"],
            "unsupported_package_count": g["unsupported_package_count"],
            "installed_count": g["installed_count"],
            "platform_supported": g["platform_supported"],
            "required_unsupported": g["required_unsupported"],
            "unsupported_packages": g["unsupported_packages"],
            "unsupported_reason": g["unsupported_reason"],
        }
        pkg_obj = _find_pkg_in_group(oid, via_pkg) if via_pkg else None
        if via_pkg and pkg_obj is not None:
            inst = bool(pkg_obj["installable"])
            psup = bool(pkg_obj["platform_supported"])
            unsup_reason = pkg_obj.get("unsupported_reason")
            direct_ok = inst
            direct_err = None
            if not inst:
                direct_err = (
                    f"{pkg_obj['name']} is known to DOTS through {owner},\n"
                    f"but DOTS has no supported installer for {pkg_obj['name']} on {os_name}.\n\n"
                    f"Selecting {owner} is still valid, but this direct package request\n"
                    f"cannot be satisfied."
                )
        else:
            inst = bool(g["platform_supported"])
            psup = bool(g["platform_supported"])
            unsup_reason = g.get("unsupported_reason")
            direct_ok = bool(g["platform_supported"])
            direct_err = None
            if not direct_ok:
                direct_err = (
                    f"{owner} has required package(s) with no supported installer on {os_name}/{pkg_mgr}: "
                    f"{', '.join(g['required_unsupported'])}."
                )

        return {
            "status": "ok",
            "selector": raw,
            "owner": owner,
            "kind": kind,
            "id": oid,
            "via_package": via_pkg or None,
            "owner_exists": True,
            "os": os_name,
            "pkg_mgr": pkg_mgr,
            "installable": inst,
            "platform_supported": psup,
            "unsupported_reason": unsup_reason,
            "package": pkg_obj,
            "group_summary": group_summary,
            "group_packages": [p["name"] for p in g["packages"]],
            "direct_install_allowed": direct_ok,
            "direct_install_error": direct_err,
            "choices": candidates,
        }

    if kind == "component":
        comp = comps_by_id[oid]
        sup, reason = _comp_supported(comp, os_name, darwin_major)
        pkg_obj = None
        if via_pkg:
            tok_meta = comp_pkg_tokens.get((oid, via_pkg.split("/")[-1])) or comp_pkg_tokens.get((oid, via_pkg))
            pkg_obj = {
                "name": via_pkg,
                "owner": owner,
                "class": "component",
                "required": False,
                "known": True,
                "selected": False,
                "installed": False,
                "installable": sup,
                "unsupported": not sup,
                "external": False,
                "platform_supported": sup,
                "install_method": (tok_meta["kind"] if tok_meta else "brew") if sup else "none",
                "install_kind": (tok_meta["kind"] if tok_meta else "brew") if sup else "none",
                "install_token": tok_meta["token"] if (tok_meta and sup) else None,
                "unsupported_reason": reason or None,
            }
        direct_err = None if sup else f"{owner} is unsupported on {os_name}: {reason}"
        return {
            "status": "ok",
            "selector": raw,
            "owner": owner,
            "kind": kind,
            "id": oid,
            "via_package": via_pkg or None,
            "owner_exists": True,
            "os": os_name,
            "pkg_mgr": pkg_mgr,
            "installable": sup,
            "platform_supported": sup,
            "unsupported_reason": reason or None,
            "package": pkg_obj,
            "group_packages": [],
            "direct_install_allowed": sup,
            "direct_install_error": direct_err,
            "choices": candidates,
        }

    # supergroup
    sg = sgs_by_id[oid]
    members = [str(m).strip() for m in (sg.get("members") or []) if str(m).strip()]
    sup_members = [
        m for m in members if m in comps_by_id and _comp_supported(comps_by_id[m], os_name, darwin_major)[0]
    ]
    sup = len(sup_members) > 0
    return {
        "status": "ok",
        "selector": raw,
        "owner": owner,
        "kind": kind,
        "id": oid,
        "via_package": None,
        "owner_exists": True,
        "os": os_name,
        "pkg_mgr": pkg_mgr,
        "installable": sup,
        "platform_supported": sup,
        "unsupported_reason": None if sup else f"no members of {owner} supported on {os_name}",
        "package": None,
        "group_packages": [],
        "direct_install_allowed": sup,
        "direct_install_error": None if sup else f"no members of {owner} supported on {os_name}",
        "choices": candidates,
    }


def run_audit(root: Path, *, strict: bool = False) -> dict[str, Any]:
    findings: list[dict[str, Any]] = []

    def add(level: str, code: str, message: str, *, owner: str | None = None, package: str | None = None, file: str | None = None) -> None:
        findings.append(
            {
                "level": level,
                "code": code,
                "message": message,
                "owner": owner,
                "package": package,
                "file": file,
            }
        )

    groups_path = _groups_registry_path(root)
    comps_path = _components_registry_path(root)
    groups_data = _load_toml(groups_path)
    comps_data = _load_toml(comps_path)

    brew_aliases = {
        str(k).strip(): str(v).strip()
        for k, v in (groups_data.get("brew_aliases") or {}).items()
        if str(k).strip() and str(v).strip()
    }
    helper_pkgs = {
        str(k).strip(): dict(v)
        for k, v in (groups_data.get("helper_packages") or {}).items()
        if str(k).strip() and isinstance(v, dict)
    }
    ownership_exceptions = {
        str(k).strip(): sorted(str(o).strip() for o in (v or []))
        for k, v in (groups_data.get("ownership_exceptions") or {}).items()
        if str(k).strip()
    }

    linux_maps = {mgr: _load_linux_map(root, mgr) for mgr in LINUX_PKG_MGRS}

    # Track ownership across groups and components
    group_pkg_owners: dict[str, list[str]] = {}
    all_pkg_owners: dict[str, list[str]] = {}
    all_group_declared_ids: set[str] = set()
    req_opt_group_ids: set[str] = set()

    for g in groups_data.get("groups") or []:
        gname = str(g.get("name") or "").strip()
        if not gname:
            continue
        bf_rel = f"brew/groups/{gname}.Brewfile"
        bf_path = root / bf_rel
        if not bf_path.is_file():
            add(
                "ERROR",
                "missing_group_brewfile",
                f"Group '{gname}' is missing {bf_rel}",
                owner=f"group:{gname}",
                file=bf_rel,
            )
            bf_f, bf_c = [], []
        else:
            bf_f, bf_c = _parse_brewfile(bf_path)

        bf_all = bf_f + bf_c
        bf_shorts = {t.split("/")[-1] for t in bf_all}

        req = [str(x).strip() for x in (g.get("required") or []) + (g.get("tools") or []) if str(x).strip()]
        opt = [str(x).strip() for x in (g.get("optional") or []) if str(x).strip()]
        comp = [str(x).strip() for x in (g.get("brew_companions") or []) if str(x).strip()]

        for pid in req + opt:
            req_opt_group_ids.add(pid)
            all_group_declared_ids.add(pid)
            group_pkg_owners.setdefault(pid, []).append(f"group:{gname}")
            all_pkg_owners.setdefault(pid, []).append(f"group:{gname}")

            # Check if package has at least one installation route on any supported platform
            alias_tok = brew_aliases.get(pid, pid)
            has_brew = (alias_tok in bf_all) or (alias_tok.split("/")[-1] in bf_shorts)
            hspec = helper_pkgs.get(pid)
            has_helper = bool(hspec and str(hspec.get("owner") or "") == f"group:{gname}")
            has_linux = any(bool(linux_maps[m].get(pid)) for m in LINUX_PKG_MGRS)

            if not (has_brew or has_helper or has_linux):
                is_req = pid in req
                lvl = "ERROR" if is_req else "WARN"
                add(
                    lvl,
                    "package_no_install_path",
                    f"{'Required' if is_req else 'Optional'} package '{pid}' in group:{gname} has no supported installation path on any platform",
                    owner=f"group:{gname}",
                    package=pid,
                    file="configs/packages/groups.toml",
                )

            # Check presence in all 4 Linux maps (missing key = stale/incomplete map)
            for mgr in LINUX_PKG_MGRS:
                if pid not in linux_maps[mgr]:
                    add(
                        "ERROR" if pid in req else "WARN",
                        "stale_map_entry",
                        f"Group package '{pid}' (group:{gname}) is missing key in configs/packages/{mgr}.toml",
                        owner=f"group:{gname}",
                        package=pid,
                        file=f"configs/packages/{mgr}.toml",
                    )

        for pid in comp:
            all_group_declared_ids.add(pid)
            group_pkg_owners.setdefault(pid, []).append(f"group:{gname}")
            all_pkg_owners.setdefault(pid, []).append(f"group:{gname}")

        # Check every Brewfile token is represented in owning registry (required, optional, brew_companions, or brew_aliases)
        alias_targets_for_group = {brew_aliases[pid].split("/")[-1] for pid in req + opt if pid in brew_aliases}
        declared_for_group = set(req) | set(opt) | set(comp) | alias_targets_for_group
        for tok in bf_all:
            short = tok.split("/")[-1]
            if tok not in declared_for_group and short not in declared_for_group:
                add(
                    "ERROR",
                    "brewfile_token_unrepresented",
                    f"Brewfile token '{tok}' in {bf_rel} is not represented in group:{gname} in groups.toml",
                    owner=f"group:{gname}",
                    package=tok,
                    file=bf_rel,
                )

    # Check aggregate brew/Brewfile drift for core..infra
    agg_path = root / "brew" / "Brewfile"
    if agg_path.is_file():
        agg_f, agg_c = _parse_brewfile(agg_path)
        agg_set = {("brew", t) for t in agg_f} | {("cask", t) for t in agg_c}
        for gname in ("core", "modern", "workstation", "media", "gui", "infra"):
            bf_f, bf_c = _parse_brewfile(root / "brew" / "groups" / f"{gname}.Brewfile")
            for tok in bf_f:
                if ("brew", tok) not in agg_set:
                    add(
                        "ERROR",
                        "aggregate_brewfile_drift",
                        f"Aggregate brew/Brewfile is missing brew \"{tok}\" from brew/groups/{gname}.Brewfile",
                        owner=f"group:{gname}",
                        package=tok,
                        file="brew/Brewfile",
                    )
            for tok in bf_c:
                if ("cask", tok) not in agg_set:
                    add(
                        "ERROR",
                        "aggregate_brewfile_drift",
                        f"Aggregate brew/Brewfile is missing cask \"{tok}\" from brew/groups/{gname}.Brewfile",
                        owner=f"group:{gname}",
                        package=tok,
                        file="brew/Brewfile",
                    )

    # Components: missing Brewfiles, helper metadata, Linux packages
    comp_linux_ids: set[str] = set()
    declared_helper_scripts: set[str] = set()
    for hp, hspec in helper_pkgs.items():
        hrel = str(hspec.get("helper") or "").strip()
        if hrel:
            declared_helper_scripts.add(hrel)
            if not (root / hrel).is_file():
                add(
                    "ERROR",
                    "missing_helper_script",
                    f"Helper script '{hrel}' declared for '{hp}' does not exist",
                    owner=str(hspec.get("owner") or ""),
                    package=hp,
                    file=hrel,
                )

    for c in comps_data.get("components") or []:
        cid = str(c.get("id") or "").strip()
        if not cid:
            continue
        bf_rel = str(c.get("brewfile") or "").strip()
        if bf_rel:
            bf_path = root / bf_rel
            if not bf_path.is_file():
                add(
                    "ERROR",
                    "missing_component_brewfile",
                    f"Component '{cid}' references missing Brewfile '{bf_rel}'",
                    owner=f"component:{cid}",
                    file=bf_rel,
                )
            else:
                bf_f, bf_c = _parse_brewfile(bf_path)
                for tok in bf_f + bf_c:
                    short = tok.split("/")[-1]
                    all_pkg_owners.setdefault(short, []).append(f"component:{cid}")
        hrel = str(c.get("helper") or "").strip()
        if hrel:
            declared_helper_scripts.add(hrel)
            if not (root / hrel).is_file():
                add(
                    "ERROR",
                    "missing_helper_script",
                    f"Component '{cid}' references missing helper '{hrel}'",
                    owner=f"component:{cid}",
                    file=hrel,
                )
        for lp in c.get("linux_packages") or []:
            lpid = str(lp).strip()
            if lpid:
                comp_linux_ids.add(lpid)
                all_pkg_owners.setdefault(lpid, []).append(f"component:{cid}")

    # Helper-managed package check: scan helpers/*.sh for direct package-installer calls
    helper_dir = root / "helpers"
    if helper_dir.is_dir():
        pkg_helper_patterns = (
            ("helpers/mapshaper.sh", "mapshaper", "group:geo"),
            ("helpers/pi.sh", "@earendil-works/pi-coding-agent", "component:pi"),
            ("helpers/openrig.sh", "@openrig/cli", "component:openrig"),
            ("helpers/agent_sandbox.sh", "pi-sandbox", "component:agent-sandbox"),
            ("helpers/davinci_resolve.sh", "davinci-resolve", "component:davinci-resolve"),
        )
        for hrel, expected_pkg, expected_owner in pkg_helper_patterns:
            if not (root / hrel).is_file():
                continue
            if expected_owner.startswith("group:"):
                represented = expected_pkg in helper_pkgs and helper_pkgs[expected_pkg].get("owner") == expected_owner
            else:
                cid = expected_owner.split(":", 1)[1]
                comp_row = next((x for x in (comps_data.get("components") or []) if x.get("id") == cid), None)
                represented = bool(comp_row and expected_pkg in (comp_row.get("helper_packages") or []))
            if not represented:
                add(
                    "ERROR",
                    "helper_package_unrepresented",
                    f"Helper-managed package '{expected_pkg}' installed by {hrel} is not represented in desired-state metadata ({expected_owner})",
                    owner=expected_owner,
                    package=expected_pkg,
                    file=hrel,
                )

    # Check platform-map keys for orphan / unowned packages
    owned_map_keys = all_group_declared_ids | comp_linux_ids
    for mgr in LINUX_PKG_MGRS:
        for k, val in linux_maps[mgr].items():
            if k not in owned_map_keys:
                add(
                    "ERROR",
                    "platform_map_orphan",
                    f"Platform map key '{k}' in configs/packages/{mgr}.toml has no owning capability in groups.toml or components.toml",
                    package=k,
                    file=f"configs/packages/{mgr}.toml",
                )
            elif val and k not in req_opt_group_ids and k not in comp_linux_ids:
                add(
                    "INFO",
                    "companion_map_entry",
                    f"Companion map key '{k}' -> '{val}' in configs/packages/{mgr}.toml",
                    package=k,
                    file=f"configs/packages/{mgr}.toml",
                )

    # Duplicate / multi-owner audit
    for pid, raw_owners in sorted(all_pkg_owners.items()):
        uniq_owners = sorted(set(raw_owners))
        if len(uniq_owners) <= 1:
            continue
        exc = ownership_exceptions.get(pid)
        if exc == uniq_owners:
            add(
                "INFO",
                "documented_shared_ownership",
                f"Package '{pid}' has documented shared ownership: {', '.join(uniq_owners)}",
                package=pid,
                file="configs/packages/groups.toml",
            )
            continue
        grp_only = [o for o in uniq_owners if o.startswith("group:")]
        if len(grp_only) > 1:
            add(
                "ERROR",
                "duplicate_ownership",
                f"Package '{pid}' is owned by multiple package groups: {', '.join(grp_only)}",
                package=pid,
                file="configs/packages/groups.toml",
            )
        else:
            add(
                "WARN",
                "duplicate_ownership",
                f"Package '{pid}' has undocumented multi-owner ambiguity: {', '.join(uniq_owners)}",
                package=pid,
                file="configs/packages/groups.toml",
            )

    # Check required packages unsupported on declared profile platforms
    profiles_dir = root / "configs" / "bootstrap" / "profiles"
    if profiles_dir.is_dir():
        groups_by_name = {
            str(g.get("name") or "").strip(): g
            for g in (groups_data.get("groups") or [])
            if g.get("name")
        }
        for prof_file in sorted(profiles_dir.glob("*.toml")):
            pdata = _load_toml(prof_file)
            prof = pdata.get("profile") or {}
            pname = str(prof.get("name") or prof_file.stem).strip()
            pgroups = [str(x).strip() for x in (prof.get("packages") or []) if str(x).strip()]
            # Determine declared platforms for profile (default all; macOS-only profiles like macos if ever present)
            declared_mgrs = ["brew", *LINUX_PKG_MGRS]
            for gname in pgroups:
                g = groups_by_name.get(gname)
                if not g:
                    continue
                req = [str(x).strip() for x in (g.get("required") or []) + (g.get("tools") or []) if str(x).strip()]
                bf_f, bf_c = _parse_brewfile(root / "brew" / "groups" / f"{gname}.Brewfile")
                bf_shorts = {t.split("/")[-1] for t in bf_f + bf_c}
                for pid in req:
                    for mgr in declared_mgrs:
                        if mgr == "brew":
                            alias_tok = brew_aliases.get(pid, pid)
                            ok_here = (alias_tok in bf_f + bf_c) or (alias_tok.split("/")[-1] in bf_shorts)
                        else:
                            ok_here = bool(linux_maps[mgr].get(pid))
                        if not ok_here:
                            # gui / font-* on native Linux is documented macOS-oriented
                            if pid.startswith("font-") or pid == "terminal-notifier":
                                add(
                                    "INFO",
                                    "darwin_oriented_required_in_profile",
                                    f"Profile '{pname}' includes group:{gname} whose macOS-oriented required package '{pid}' is skipped on native {mgr}",
                                    owner=f"group:{gname}",
                                    package=pid,
                                    file=f"configs/bootstrap/profiles/{prof_file.name}",
                                )
                            else:
                                add(
                                    "ERROR",
                                    "required_unsupported_on_profile_platform",
                                    f"Profile '{pname}' requires '{pid}' (via group:{gname}) which is unsupported on {mgr}",
                                    owner=f"group:{gname}",
                                    package=pid,
                                    file=f"configs/bootstrap/profiles/{prof_file.name}",
                                )

    errors = sum(1 for f in findings if f["level"] == "ERROR")
    warnings = sum(1 for f in findings if f["level"] == "WARN")
    info = sum(1 for f in findings if f["level"] == "INFO")
    ok = (errors == 0) and (not strict or warnings == 0)

    return {
        "schema_version": 1,
        "ok": ok,
        "summary": {
            "errors": errors,
            "warnings": warnings,
            "info": info,
        },
        "findings": findings,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="package_truth.py")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_groups = sub.add_parser("groups-json")
    p_groups.add_argument("--os", dest="os_name", default=None)
    p_groups.add_argument("--pkg-mgr", dest="pkg_mgr", default=None)

    p_res = sub.add_parser("resolve")
    p_res.add_argument("--selector", required=True)

    p_audit = sub.add_parser("audit")
    p_audit.add_argument("--json", action="store_true", dest="as_json")
    p_audit.add_argument("--strict", action="store_true")

    args = parser.parse_args(argv)
    root = _repo_root()

    if args.cmd == "groups-json":
        pjson_raw = os.environ.get("PJSON", "").strip()
        pstate = json.loads(pjson_raw) if pjson_raw else None
        out = compute_groups_data(root, pstate, os_name=args.os_name, pkg_mgr=args.pkg_mgr)
        print(json.dumps(out, indent=2))
        return 0

    if args.cmd == "resolve":
        pjson_raw = os.environ.get("PJSON", "").strip()
        pstate = json.loads(pjson_raw) if pjson_raw else None
        out = resolve_selector(root, args.selector, pstate)
        print(json.dumps(out, indent=2))
        return 0

    if args.cmd == "audit":
        res = run_audit(root, strict=args.strict)
        if args.as_json:
            print(json.dumps(res, indent=2))
        else:
            s = res["summary"]
            print("DOTS Package Registry Audit")
            print(f"Summary: errors={s['errors']}  warnings={s['warnings']}  info={s['info']}")
            if res["findings"]:
                print("")
                for f in res["findings"]:
                    loc = f" [{f['file']}]" if f.get("file") else ""
                    print(f"  {f['level']:<5} {f['code']}: {f['message']}{loc}")
            else:
                print("  OK: no findings")
        return 0 if res["ok"] else 1

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
