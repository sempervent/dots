"""Dynamic desired-state working model for the DOTS Textual TUI.

All group, component, supergroup, and package entries come directly from the
structured DOTS backend APIs and registries — never from hard-coded lists.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

from .backend import DotsBackend


class SelectionState(str, Enum):
    INHERITED = "inherited"
    LOCAL_ADD = "local"
    NOT_SELECTED = "absent"
    LOCAL_EXCLUDE = "excluded"
    UNSUPPORTED = "unsupported"

    @classmethod
    def from_raw(cls, raw: str) -> "SelectionState":
        raw_l = (raw or "").strip().lower()
        for member in cls:
            if member.value == raw_l:
                return member
        return cls.NOT_SELECTED

    @property
    def is_desired(self) -> bool:
        return self in (SelectionState.INHERITED, SelectionState.LOCAL_ADD)

    def glyph(self, *, ascii_only: bool = False) -> str:
        if ascii_only or os.environ.get("DOTS_TUI_ASCII") == "1":
            return {
                SelectionState.INHERITED: "*",
                SelectionState.LOCAL_ADD: "+",
                SelectionState.NOT_SELECTED: " ",
                SelectionState.LOCAL_EXCLUDE: "-",
                SelectionState.UNSUPPORTED: "!",
            }[self]
        return {
            SelectionState.INHERITED: "●",
            SelectionState.LOCAL_ADD: "✓",
            SelectionState.NOT_SELECTED: "□",
            SelectionState.LOCAL_EXCLUDE: "⊘",
            SelectionState.UNSUPPORTED: "!",
        }[self]

    @property
    def tag(self) -> str:
        return {
            SelectionState.INHERITED: "inherited",
            SelectionState.LOCAL_ADD: "local",
            SelectionState.NOT_SELECTED: "absent",
            SelectionState.LOCAL_EXCLUDE: "excluded",
            SelectionState.UNSUPPORTED: "unsupported",
        }[self]

    @property
    def explanation(self) -> str:
        return {
            SelectionState.INHERITED: "Inherited from parent/base profile",
            SelectionState.LOCAL_ADD: "Local addition",
            SelectionState.NOT_SELECTED: "Not selected",
            SelectionState.LOCAL_EXCLUDE: "Inherited capability explicitly excluded",
            SelectionState.UNSUPPORTED: "Unavailable on this platform",
        }[self]


def humanize_category(cat: str) -> str:
    raw = (cat or "other").strip()
    if not raw:
        return "Other"
    words = raw.replace("-", "_").split("_")
    out = []
    for w in words:
        if w.lower() == "ai":
            out.append("AI")
        else:
            out.append(w.capitalize())
    return " ".join(out)


@dataclass
class CapabilityItem:
    kind: str  # "group" | "component" | "supergroup"
    id: str
    label: str
    description: str
    category: str = ""
    persisted: SelectionState = SelectionState.NOT_SELECTED
    working: SelectionState = SelectionState.NOT_SELECTED
    supported: bool = True
    unsupported_reason: str = ""
    # Group fields
    required: list[str] = field(default_factory=list)
    optional: list[str] = field(default_factory=list)
    required_count: int = 0
    optional_count: int = 0
    package_count: int = 0
    supported_package_count: int = 0
    unsupported_package_count: int = 0
    installed_count: int = 0
    required_unsupported: list[str] = field(default_factory=list)
    unsupported_packages: list[str] = field(default_factory=list)
    packages: list[dict[str, Any]] = field(default_factory=list)
    brewfile: str = ""
    # Component fields
    platforms: list[str] = field(default_factory=list)
    min_darwin: str | None = None
    omit_from_all: bool = False
    cloud: bool = False
    local_ai: bool = False
    formulae: list[str] = field(default_factory=list)
    casks: list[str] = field(default_factory=list)
    # Supergroup fields
    members: list[str] = field(default_factory=list)
    supported_members: list[str] = field(default_factory=list)

    @property
    def selector(self) -> str:
        return f"{self.kind}:{self.id}"

    @property
    def modified(self) -> bool:
        return self.working != self.persisted


@dataclass
class SearchHit:
    title: str
    subtitle: str
    kind: str  # "group" | "component" | "supergroup" | "package"
    target_id: str  # group/component/supergroup id or package name
    owner_selector: str | None = None  # e.g. "group:dev" when unambiguous
    installable: bool | None = None
    installed: bool | None = None
    external: bool = False
    install_method: str = ""
    unsupported_reason: str = ""


class DesiredStateModel:
    """In-memory controller model synchronized with DOTS structured JSON APIs."""

    def __init__(self, backend: DotsBackend) -> None:
        self.backend = backend
        self.active: bool = False
        self.profile_name: str = "(none)"
        self.profile_file: str = ""
        self.profile_kind: str = ""
        self.profile_hash: str = ""
        self.extends: str = ""
        self.source_chain: list[dict[str, Any]] = []
        self.runtime: dict[str, Any] = {}
        self.os_name: str = ""
        self.pkg_mgr: str = ""
        self.groups: list[CapabilityItem] = []
        self.components: list[CapabilityItem] = []
        self.supergroups: list[CapabilityItem] = []
        self.profiles_catalog: list[dict[str, Any]] = []
        self._by_selector: dict[str, CapabilityItem] = {}
        self._pkg_index: dict[str, list[CapabilityItem]] = {}
        self._pkg_meta_index: dict[str, list[tuple[CapabilityItem, dict[str, Any]]]] = {}

    def load(self, profile: str | None = None) -> None:
        pshow = self.backend.profile_show(profile)
        target_prof = profile or pshow.get("profile_file") or pshow.get("profile")
        gdata = self.backend.package_groups(target_prof if pshow.get("profile") else None)
        cdata = self.backend.components_list(target_prof if pshow.get("profile") else None)
        try:
            self.profiles_catalog = self.backend.profile_list()
        except Exception:
            self.profiles_catalog = []

        self.active = bool(pshow.get("active", False))
        self.profile_name = str(pshow.get("profile") or "(none)")
        self.profile_file = str(pshow.get("profile_file") or "")
        self.profile_kind = str(pshow.get("profile_kind") or "")
        self.profile_hash = str(pshow.get("profile_hash") or "")
        self.extends = str(pshow.get("extends") or "")
        self.source_chain = list(pshow.get("source_chain") or [])
        self.runtime = dict(pshow.get("runtime") or {})
        self.os_name = str(gdata.get("os") or cdata.get("os") or "")
        self.pkg_mgr = str(gdata.get("pkg_mgr") or "")

        self.groups = []
        self.components = []
        self.supergroups = []
        self._by_selector = {}
        self._pkg_index = {}
        self._pkg_meta_index = {}

        for g in gdata.get("groups") or []:
            name = str(g.get("name") or "").strip()
            if not name:
                continue
            st = SelectionState.from_raw(str(g.get("selected_state") or "absent"))
            raw_psup = bool(g.get("platform_supported", True))
            # If pkg_mgr is unknown (e.g. DOTS_FORCE_OS=linux on a Darwin test host without DOTS_FORCE_PKG_MGR),
            # keep group toggleable while surfacing unsupported_reason honestly.
            sup = True if self.pkg_mgr == "unknown" else raw_psup
            pkgs_list = list(g.get("packages") or [])
            item = CapabilityItem(
                kind="group",
                id=name,
                label=name,
                description=str(g.get("description") or ""),
                category="Package Groups",
                persisted=st,
                working=st,
                supported=sup,
                unsupported_reason=str(g.get("unsupported_reason") or ""),
                required=list(g.get("required") or []),
                optional=list(g.get("optional") or []),
                required_count=int(g.get("required_count") or 0),
                optional_count=int(g.get("optional_count") or 0),
                package_count=int(g.get("package_count") or len(pkgs_list)),
                supported_package_count=int(g.get("supported_package_count") or 0),
                unsupported_package_count=int(g.get("unsupported_package_count") or 0),
                installed_count=int(g.get("installed_count") or 0),
                required_unsupported=list(g.get("required_unsupported") or []),
                unsupported_packages=list(g.get("unsupported_packages") or []),
                packages=pkgs_list,
                brewfile=str(g.get("brewfile") or ""),
            )
            self.groups.append(item)
            self._by_selector[item.selector] = item
            for p in item.packages:
                pname = str(p.get("name") or "").strip()
                if pname:
                    short = pname.split("/")[-1]
                    self._pkg_index.setdefault(pname, []).append(item)
                    self._pkg_meta_index.setdefault(pname, []).append((item, p))
                    if short != pname:
                        self._pkg_index.setdefault(short, []).append(item)
                        self._pkg_meta_index.setdefault(short, []).append((item, p))

        for s in cdata.get("supergroups") or []:
            sid = str(s.get("id") or "").strip()
            if not sid:
                continue
            st = SelectionState.from_raw(str(s.get("selected_state") or "absent"))
            item = CapabilityItem(
                kind="supergroup",
                id=sid,
                label=str(s.get("label") or sid),
                description=str(s.get("description") or ""),
                category="Bundles",
                persisted=st,
                working=st,
                supported=True,
                members=list(s.get("members") or []),
                supported_members=list(s.get("supported_members") or []),
            )
            self.supergroups.append(item)
            self._by_selector[item.selector] = item

        for c in cdata.get("components") or []:
            cid = str(c.get("id") or "").strip()
            if not cid:
                continue
            sup = bool(c.get("supported_on_current_platform", True))
            reason = str(c.get("unsupported_reason") or "")
            raw_st = str(c.get("selected_state") or ("absent" if sup else "unsupported"))
            st = SelectionState.UNSUPPORTED if not sup else SelectionState.from_raw(raw_st)
            item = CapabilityItem(
                kind="component",
                id=cid,
                label=str(c.get("label") or cid),
                description=str(c.get("description") or ""),
                category=str(c.get("category") or "other"),
                persisted=st,
                working=st,
                supported=sup,
                unsupported_reason=reason,
                brewfile=str(c.get("brewfile") or ""),
                platforms=list(c.get("platforms") or []),
                min_darwin=str(c["min_darwin"]) if c.get("min_darwin") is not None else None,
                omit_from_all=bool(c.get("omit_from_all", False)),
                cloud=bool(c.get("cloud", False)),
                local_ai=bool(c.get("local_ai", False)),
                formulae=list(c.get("formulae") or []),
                casks=list(c.get("casks") or []),
            )
            self.components.append(item)
            self._by_selector[item.selector] = item
            for tok in item.formulae + item.casks:
                short = tok.split("/")[-1]
                cmeta = {
                    "name": short,
                    "installable": sup,
                    "installed": False,
                    "external": False,
                    "install_method": "brew" if sup else "none",
                    "unsupported_reason": reason or None,
                }
                self._pkg_index.setdefault(tok, []).append(item)
                self._pkg_meta_index.setdefault(tok, []).append((item, cmeta))
                if short != tok:
                    self._pkg_index.setdefault(short, []).append(item)
                    self._pkg_meta_index.setdefault(short, []).append((item, cmeta))

    def get(self, selector: str) -> CapabilityItem | None:
        return self._by_selector.get(selector)

    def all_items(self) -> list[CapabilityItem]:
        return [*self.groups, *self.supergroups, *self.components]

    def component_categories(self) -> list[tuple[str, list[CapabilityItem]]]:
        """Group components dynamically by registry category preserving order."""
        grouped: dict[str, list[CapabilityItem]] = {}
        for comp in self.components:
            cat_key = comp.category or "other"
            grouped.setdefault(cat_key, []).append(comp)
        return [(humanize_category(k), rows) for k, rows in grouped.items()]

    def toggle(self, selector: str) -> tuple[bool, str]:
        item = self._by_selector.get(selector)
        if item is None:
            return False, f"Unknown item: {selector}"
        cur = item.working
        if (not item.supported or item.persisted == SelectionState.UNSUPPORTED) and not cur.is_desired:
            reason = item.unsupported_reason or "unsupported on this platform"
            return False, f"{item.label} is unavailable: {reason}"

        if cur == SelectionState.INHERITED:
            item.working = SelectionState.LOCAL_EXCLUDE
        elif cur == SelectionState.LOCAL_EXCLUDE:
            item.working = SelectionState.INHERITED
        elif cur == SelectionState.NOT_SELECTED:
            item.working = SelectionState.LOCAL_ADD
        elif cur == SelectionState.LOCAL_ADD:
            item.working = SelectionState.NOT_SELECTED
        return True, f"{item.id}: {item.working.tag}"

    def discard(self) -> None:
        for item in self.all_items():
            item.working = item.persisted

    def pending_adds(self) -> list[str]:
        adds: list[str] = []
        for item in self.all_items():
            if not item.modified:
                continue
            if item.working.is_desired and not item.persisted.is_desired:
                adds.append(item.selector)
        return adds

    def pending_removes(self) -> list[str]:
        rems: list[str] = []
        for item in self.all_items():
            if not item.modified:
                continue
            if not item.working.is_desired and item.persisted.is_desired:
                rems.append(item.selector)
        return rems

    @property
    def has_unsaved_changes(self) -> bool:
        return bool(self.pending_adds() or self.pending_removes())

    def pending_summary(self) -> str:
        adds = self.pending_adds()
        rems = self.pending_removes()
        if not adds and not rems:
            return "none"
        tokens = [f"+{x.split(':', 1)[1]}" for x in adds] + [
            f"-{x.split(':', 1)[1]}" for x in rems
        ]
        return " ".join(tokens)

    def search(self, query: str) -> list[SearchHit]:
        q = (query or "").strip().lower()
        if not q:
            return []
        hits: list[SearchHit] = []
        seen_keys: set[tuple[str, str]] = set()

        for g in self.groups:
            blob = f"{g.id} {g.description}".lower()
            if q in blob:
                key = ("group", g.id)
                if key not in seen_keys:
                    seen_keys.add(key)
                    hits.append(
                        SearchHit(
                            title=g.id,
                            subtitle=f"Package group — {g.description}",
                            kind="group",
                            target_id=g.id,
                            owner_selector=g.selector,
                        )
                    )

        for s in self.supergroups:
            blob = f"{s.id} {s.label} {s.description} {' '.join(s.members)}".lower()
            if q in blob:
                key = ("supergroup", s.id)
                if key not in seen_keys:
                    seen_keys.add(key)
                    hits.append(
                        SearchHit(
                            title=f"{s.label} ({s.id})",
                            subtitle=f"Bundle ({len(s.members)} components) — {s.description}",
                            kind="supergroup",
                            target_id=s.id,
                            owner_selector=s.selector,
                        )
                    )

        for c in self.components:
            blob = f"{c.id} {c.label} {c.category} {c.description}".lower()
            if q in blob:
                key = ("component", c.id)
                if key not in seen_keys:
                    seen_keys.add(key)
                    hits.append(
                        SearchHit(
                            title=f"{c.label} ({c.id})",
                            subtitle=f"Component [{humanize_category(c.category)}] — {c.description}",
                            kind="component",
                            target_id=c.id,
                            owner_selector=c.selector,
                        )
                    )

        # Package search across dynamic index
        pkg_matches: list[tuple[str, list[tuple[CapabilityItem, dict[str, Any]]]]] = []
        for pname, entries in self._pkg_meta_index.items():
            if q in pname.lower():
                uniq_entries: list[tuple[CapabilityItem, dict[str, Any]]] = []
                seen_o: set[str] = set()
                for o, meta in entries:
                    if o.selector not in seen_o:
                        seen_o.add(o.selector)
                        uniq_entries.append((o, meta))
                pkg_matches.append((pname, uniq_entries))

        pkg_matches.sort(key=lambda pair: (pair[0].lower() != q, len(pair[0]), pair[0].lower()))
        for pname, entries in pkg_matches:
            key = ("package", pname)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            if len(entries) == 1:
                owner, meta = entries[0]
                inst_ok = meta.get("installable")
                is_installed = bool(meta.get("installed", False))
                is_external = bool(meta.get("external", False))
                method = str(meta.get("install_method") or "")
                unsup_reason = str(meta.get("unsupported_reason") or "")
                if inst_ok is False:
                    plat_str = "Platform: unavailable through DOTS on this machine"
                    if is_installed:
                        plat_str += " (installed externally)"
                    subtitle = f"Owner: {owner.id}  |  {plat_str}"
                elif inst_ok is True:
                    inst_str = "yes" if is_installed else "no"
                    via = f" ({method})" if method else ""
                    subtitle = f"Owner: {owner.id}  |  Installable: yes{via}  |  Installed: {inst_str}"
                else:
                    subtitle = f"Package provided by {owner.selector}"
                hits.append(
                    SearchHit(
                        title=pname,
                        subtitle=subtitle,
                        kind="package",
                        target_id=pname,
                        owner_selector=owner.selector,
                        installable=inst_ok,
                        installed=is_installed,
                        external=is_external,
                        install_method=method,
                        unsupported_reason=unsup_reason,
                    )
                )
            else:
                owner_str = ", ".join(o.selector for o, _ in entries)
                any_inst = any(bool(m.get("installable")) for _, m in entries)
                hits.append(
                    SearchHit(
                        title=pname,
                        subtitle=f"Owners: {owner_str}  |  Installable: {'yes' if any_inst else 'no'}",
                        kind="package",
                        target_id=pname,
                        owner_selector=None,
                        installable=any_inst,
                    )
                )

        return hits
