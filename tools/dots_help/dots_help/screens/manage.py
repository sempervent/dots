"""Profile Editor: individual software, groups, components, and bundles."""

from __future__ import annotations

from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.widgets import Button, Label, ListItem, ListView, Static

from ..model import CapabilityItem, DesiredStateModel

EDITOR_VIEWS = ("all", "individual", "groups", "components", "bundles", "selected", "changes")
VIEW_LABELS = {
    "all": "All",
    "individual": "Individual",
    "groups": "Groups",
    "components": "Components",
    "bundles": "Bundles",
    "selected": "Selected",
    "changes": "Changes",
}


def item_matches_view(item: CapabilityItem, view: str, *, show_unsupported: bool) -> bool:
    """Catalog visibility. Unsupported hiding is independent of the view filter."""
    if not item.supported and not show_unsupported:
        return False
    if view == "individual":
        return item.kind == "package"
    if view == "groups":
        return item.kind == "group"
    if view == "components":
        return item.kind == "component"
    if view == "bundles":
        return item.kind == "supergroup"
    if view == "selected":
        return item.working.is_desired
    if view == "changes":
        return item.modified
    return True


class SoftwarePane(Vertical):
    """Registry-driven profile editor for software desired state."""

    def __init__(self, model: DesiredStateModel, **kwargs) -> None:
        super().__init__(**kwargs)
        self.model = model
        self.show_unsupported: bool = False
        self.view: str = "all"
        self._row_selectors: list[str | None] = []
        self._search_note: str = ""
        self._current_selector: str | None = None

    def compose(self) -> ComposeResult:
        yield Static("", id="software-profile-bar")
        with Horizontal(id="software-split"):
            with Vertical(id="software-left"):
                with Horizontal(id="software-toolbar"):
                    yield Button("Add Software (/)", id="btn-add-software", variant="primary")
                    yield Button("View: All", id="btn-view")
                    yield Button("Show unavailable", id="btn-toggle-unsup")
                yield ListView(id="capability-list")
            with Vertical(id="software-right"):
                yield Label("Details", id="details-title")
                with VerticalScroll(id="details-scroll"):
                    yield Static("Select a group, bundle, or component.", id="details-body")
        yield Static("Pending: none   |   Installed packages are not automatically removed.", id="pending-bar")
        with Horizontal(id="software-actions"):
            yield Button("Preview (p)", id="btn-preview")
            yield Button("Save (s)", id="btn-save", variant="primary")
            yield Button("Save + Apply (a)", id="btn-apply", variant="success")
            yield Button("Discard", id="btn-discard", variant="warning")

    def on_mount(self) -> None:
        self.rebuild()

    def rebuild(self, preserve_selector: str | None = None) -> None:
        target_sel = preserve_selector or self._current_selector
        self._update_profile_bar()
        self._update_pending_bar()

        lv = self.query_one("#capability-list", ListView)
        lv.clear()
        self._row_selectors = []

        def add_header(text: str) -> None:
            lv.append(ListItem(Label(f"── {text} ──"), classes="cat-header"))
            self._row_selectors.append(None)

        def add_item(item: CapabilityItem) -> bool:
            if not item_matches_view(item, self.view, show_unsupported=self.show_unsupported):
                return False
            st = item.working
            mod_mark = "*" if item.modified else " "
            extra = " unavailable" if not item.supported else ""
            avail = ""
            if item.kind == "group" and item.package_count:
                avail = f"  {item.supported_package_count}/{item.package_count} avail"
            line = f"{mod_mark} {st.glyph()} {item.label:<22} {st.tag}{avail}{extra}"
            classes = f"cap-row state-{st.value}"
            if not item.supported:
                classes += " cap-disabled"
            lv.append(ListItem(Label(line), classes=classes))
            self._row_selectors.append(item.selector)
            return True

        sections: list[tuple[str, list[CapabilityItem]]] = [
            ("Individual Software", list(self.model.explicit_packages)),
            ("Package Groups", list(self.model.groups)),
        ]
        for cat_title, comps in self.model.component_categories():
            sections.append((f"Components · {cat_title}", list(comps)))
        sections.append(("Bundles", list(self.model.supergroups)))
        for title, items in sections:
            visible = [i for i in items if item_matches_view(i, self.view, show_unsupported=self.show_unsupported)]
            if not visible:
                continue
            add_header(title)
            for item in visible:
                add_item(item)

        # Restore focus/index
        chosen_idx = None
        if target_sel:
            for idx, sel in enumerate(self._row_selectors):
                if sel == target_sel:
                    chosen_idx = idx
                    break
        if chosen_idx is None:
            for idx, sel in enumerate(self._row_selectors):
                if sel is not None:
                    chosen_idx = idx
                    break
        if chosen_idx is not None:
            lv.index = chosen_idx
            self._show_details_for(self._row_selectors[chosen_idx])
        self._sync_action_labels()

    def cycle_view(self) -> None:
        idx = EDITOR_VIEWS.index(self.view) if self.view in EDITOR_VIEWS else 0
        self.view = EDITOR_VIEWS[(idx + 1) % len(EDITOR_VIEWS)]
        self.rebuild()

    def _sync_action_labels(self) -> None:
        try:
            view_btn = self.query_one("#btn-view", Button)
            unsup_btn = self.query_one("#btn-toggle-unsup", Button)
            save_btn = self.query_one("#btn-save", Button)
            apply_btn = self.query_one("#btn-apply", Button)
        except Exception:
            return
        view_btn.label = f"View: {VIEW_LABELS.get(self.view, self.view)}"
        unsup_btn.label = "Hide unavailable" if self.show_unsupported else "Show unavailable"
        if self.model.active:
            save_btn.label = "Save (s)"
            apply_btn.label = "Save + Apply (a)"
        else:
            save_btn.label = "Save Profile (s)"
            apply_btn.label = "Save + Activate + Apply (a)"

    def _update_profile_bar(self) -> None:
        m = self.model
        active = m.current_active_profile()
        active_name = str((active or {}).get("name") or "(none)")
        kind = m.profile_kind or "profile"
        plat = f"{m.os_name or '?'} / {m.pkg_mgr or '?'}"
        if m.active:
            editing = f"Editing: {m.profile_name} [{kind}]   ACTIVE"
        else:
            editing = f"Editing profile: {m.profile_name} [{kind}]"
            if kind == "builtin":
                editing += "  (writes an overlay; builtin files stay immutable)"
        active_line = f"Active machine profile: {active_name}   |   Platform: {plat}"
        self.query_one("#software-profile-bar", Static).update(f"{editing}\n{active_line}")

    def _update_pending_bar(self) -> None:
        self.query_one("#pending-bar", Static).update(self.model.pending_bar_text())

    def highlighted_selector(self) -> str | None:
        lv = self.query_one("#capability-list", ListView)
        idx = lv.index
        if idx is None or idx < 0 or idx >= len(self._row_selectors):
            return None
        return self._row_selectors[idx]

    def on_list_view_highlighted(self, event: ListView.Highlighted) -> None:
        if event.list_view.id != "capability-list":
            return
        idx = event.list_view.index
        if idx is None or idx < 0 or idx >= len(self._row_selectors):
            return
        sel = self._row_selectors[idx]
        if sel:
            self._search_note = ""
            self._show_details_for(sel)

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        if event.list_view.id != "capability-list":
            return
        self.toggle_current()

    def toggle_current(self) -> None:
        sel = self.highlighted_selector()
        if not sel:
            return
        ok, msg = self.model.toggle(sel)
        if not ok:
            self.app.notify(msg, severity="warning")
            return
        self._search_note = ""
        self.rebuild(preserve_selector=sel)

    def focus_selector(self, selector: str, note: str = "") -> None:
        self._search_note = note
        item = self.model.get(selector)
        if item and not item.supported:
            self.show_unsupported = True
        if item and not item_matches_view(item, self.view, show_unsupported=self.show_unsupported):
            self.view = "all"
        self.rebuild(preserve_selector=selector)
        self._show_details_for(selector)

    def _show_details_for(self, selector: str | None) -> None:
        self._current_selector = selector
        body = self.query_one("#details-body", Static)
        if not selector:
            body.update("Select a group, bundle, or component.")
            return
        item = self.model.get(selector)
        if item is None:
            body.update(f"Unknown selector: {selector}")
            return

        lines: list[str] = []
        if self._search_note:
            lines.extend([self._search_note, "", "────────────────────────", ""])

        lines.append(f"{item.label}  ({item.selector})")
        lines.append("")
        if item.description:
            lines.extend([item.description, ""])

        lines.extend([
            "State:",
            f"  {item.working.glyph()} {item.working.tag} — {item.working.explanation}",
        ])
        if item.modified:
            lines.append(f"  (pending change from: {item.persisted.tag})")
        lines.append("")

        if item.kind == "package":
            installed = "yes" if item.installed else "no"
            external = "yes" if item.external else "no"
            leaf = "yes" if item.leaf_selectable else "no"
            route = " ".join(x for x in (item.install_method, item.install_kind, item.install_token) if x) or "(none)"
            lines.extend([
                f"Owner:     {item.owner or '(none)'}",
                f"Install:   {route}",
                f"Installed: {installed}",
                f"External:  {external}",
                f"Leaf selectable: {leaf}",
                f"Platform:  {'supported' if item.supported else 'unsupported'}",
            ])
            if item.working.is_desired:
                lines.append("Desired via: explicit package")
            if not item.supported:
                lines.append(f"Unavailable: {item.unsupported_reason or item.leaf_reason or 'unsupported on this platform'}")
            if item.owner:
                owner = self.model.get(item.owner)
                if owner:
                    lines.append(f"Owner state: {owner.label} [{owner.working.tag}]")
                    if owner.working.is_desired:
                        lines.append(
                            f"This package is already satisfied by {item.owner}. "
                            "Adding it explicitly is redundant but valid desired-state intent."
                        )
            lines.append("Removing desired state does not uninstall software.")
        elif item.kind == "group":
            plat_desc = f"{self.model.os_name or '?'}/{self.model.pkg_mgr or '?'}"
            lines.extend([
                f"Required:  {item.required_count}   Optional: {item.optional_count}",
                f"Platform:  {item.supported_package_count}/{item.package_count} supported on {plat_desc}",
                f"Installed: {item.installed_count} / {item.supported_package_count}",
            ])
            if not item.supported:
                lines.append(f"Disabled:  {item.unsupported_reason or 'unsupported on this platform'}")
            if item.unsupported_packages:
                lines.append(f"Unavailable (optional): {', '.join(item.unsupported_packages)}")
            lines.extend(["", "Packages:"])
            for p in item.packages:
                pname = str(p.get("name") or "")
                method = str(p.get("install_method") or "none")
                if not p.get("installable", True):
                    st_str = "unavailable (external)" if p.get("external") else "unavailable"
                elif p.get("external"):
                    st_str = f"external ({method})"
                elif p.get("installed"):
                    st_str = f"installed ({method})"
                else:
                    st_str = f"missing ({method})"
                lines.append(f"  {pname:<20} {st_str}")
        elif item.kind == "component":
            desired = "yes" if item.working.is_desired else "no"
            plats = ", ".join(item.platforms) if item.platforms else "darwin, linux"
            policy = ["explicit opt-in"]
            if item.omit_from_all:
                policy.append("omit_from_all")
            if item.cloud:
                policy.append("cloud AI")
            if item.local_ai:
                policy.append("local AI")
            lines.extend([
                f"Category:  {item.category}",
                f"Platform:  {plats}",
                f"Desired:   {desired}",
                f"Policy:    {', '.join(policy)}",
            ])
            if not item.supported:
                lines.append(f"Disabled:  {item.unsupported_reason or 'unsupported on this platform'}")
            if item.formulae or item.casks:
                lines.append("")
                lines.append("Packages:")
                for f in item.formulae:
                    lines.append(f"  brew: {f}")
                for c in item.casks:
                    lines.append(f"  cask: {c}")
        elif item.kind == "supergroup":
            lines.extend([
                f"Members ({len(item.supported_members)}/{len(item.members)} supported on {self.model.os_name or 'host'}):",
            ])
            for m in item.members:
                comp = self.model.get(f"component:{m}")
                if comp and not comp.supported:
                    lines.append(f"  ! {m} ({comp.unsupported_reason})")
                elif comp:
                    lines.append(f"  + {m} [{comp.working.tag}]")
                else:
                    lines.append(f"  + {m}")

        body.update("\n".join(lines))

    def on_button_pressed(self, event: Button.Pressed) -> None:
        bid = event.button.id
        if bid == "btn-add-software":
            self.app.action_search()  # type: ignore[attr-defined]
        elif bid == "btn-view":
            self.cycle_view()
        elif bid == "btn-toggle-unsup":
            self.show_unsupported = not self.show_unsupported
            self.rebuild()
        elif bid == "btn-preview":
            self.app.action_preview()  # type: ignore[attr-defined]
        elif bid == "btn-save":
            self.app.action_save_only()  # type: ignore[attr-defined]
        elif bid == "btn-apply":
            self.app.action_save_apply()  # type: ignore[attr-defined]
        elif bid == "btn-discard":
            self.app.action_discard()  # type: ignore[attr-defined]
