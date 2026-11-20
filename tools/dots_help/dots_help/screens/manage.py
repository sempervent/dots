"""Primary dynamic desired-state Software management pane."""

from __future__ import annotations

from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.widgets import Button, Label, ListItem, ListView, Static

from ..model import CapabilityItem, DesiredStateModel, SelectionState


class SoftwarePane(Vertical):
    """Dynamic registry-driven group / bundle / component selector + details pane."""

    def __init__(self, model: DesiredStateModel, **kwargs) -> None:
        super().__init__(**kwargs)
        self.model = model
        self.show_unsupported: bool = True
        self._row_selectors: list[str | None] = []
        self._search_note: str = ""
        self._current_selector: str | None = None

    def compose(self) -> ComposeResult:
        yield Static("", id="software-profile-bar")
        with Horizontal(id="software-split"):
            with Vertical(id="software-left"):
                with Horizontal(id="software-toolbar"):
                    yield Label("Capabilities (Space=toggle, /=search)", id="software-list-title")
                    yield Button("Hide unsupported", id="btn-toggle-unsup")
                yield ListView(id="capability-list")
            with Vertical(id="software-right"):
                yield Label("Details", id="details-title")
                with VerticalScroll(id="details-scroll"):
                    yield Static("Select a group, bundle, or component.", id="details-body")
        yield Static("Pending: none   |   Installed packages are not automatically removed.", id="pending-bar")
        with Horizontal(id="software-actions"):
            yield Button("Preview (p)", id="btn-preview")
            yield Button("Save Only (s)", id="btn-save", variant="primary")
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

        def add_item(item: CapabilityItem) -> None:
            if not item.supported and not self.show_unsupported:
                return
            st = item.working
            glyph = st.glyph()
            tag = f"[{st.tag}]"
            mod_mark = "*" if item.modified else " "
            suffix = ""
            if item.kind == "group":
                if item.unsupported_package_count > 0:
                    suffix = (
                        f" ({item.installed_count}/{item.supported_package_count} inst, "
                        f"{item.supported_package_count}/{item.package_count} avail)"
                    )
                else:
                    suffix = f" ({item.installed_count}/{item.supported_package_count} inst)"
            elif item.kind == "supergroup":
                suffix = f" ({len(item.supported_members)}/{len(item.members)} components)"
            elif not item.supported:
                suffix = f" ({item.unsupported_reason or 'unavailable'})"
            line = f"{mod_mark}{glyph} {tag:<13} {item.label}{suffix}"
            classes = f"cap-row state-{st.value}"
            if not item.supported:
                classes += " cap-disabled"
            lv.append(ListItem(Label(line), classes=classes))
            self._row_selectors.append(item.selector)

        add_header("Package Groups")
        for g in self.model.groups:
            add_item(g)

        if self.model.supergroups:
            add_header("Bundles (Supergroups)")
            for s in self.model.supergroups:
                add_item(s)

        for cat_title, comps in self.model.component_categories():
            visible = [c for c in comps if c.supported or self.show_unsupported]
            if not visible:
                continue
            add_header(f"Components: {cat_title}")
            for c in visible:
                add_item(c)

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

    def _update_profile_bar(self) -> None:
        m = self.model
        ext = f" -> {m.extends}" if m.extends else ""
        kind = f" [{m.profile_kind}]" if m.profile_kind else ""
        self.query_one("#software-profile-bar", Static).update(
            f"Profile: {m.profile_name}{ext}{kind}   |   OS: {m.os_name or '?'}   |   "
            f"State legend: ● inherited  ✓ local  □ absent  ⊘ excluded  ! unsupported"
        )

    def _update_pending_bar(self) -> None:
        pending = self.model.pending_summary()
        self.query_one("#pending-bar", Static).update(
            f"Pending: {pending}   |   Installed packages are not automatically removed."
        )

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
        if item and not item.supported and not self.show_unsupported:
            self.show_unsupported = True
            self.query_one("#btn-toggle-unsup", Button).label = "Hide unsupported"
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

        if item.kind == "group":
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
        if bid == "btn-toggle-unsup":
            self.show_unsupported = not self.show_unsupported
            event.button.label = "Hide unsupported" if self.show_unsupported else "Show unsupported"
            self.rebuild()
        elif bid == "btn-preview":
            self.app.action_preview()  # type: ignore[attr-defined]
        elif bid == "btn-save":
            self.app.action_save_only()  # type: ignore[attr-defined]
        elif bid == "btn-apply":
            self.app.action_save_apply()  # type: ignore[attr-defined]
        elif bid == "btn-discard":
            self.app.action_discard()  # type: ignore[attr-defined]
