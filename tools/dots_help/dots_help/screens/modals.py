"""Modal dialogs for preview, apply progress, search, ambiguous owners, and confirmations."""

from __future__ import annotations

from typing import Any, Callable

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.screen import ModalScreen
from textual.widgets import Button, Input, Label, ListItem, ListView, RichLog, Static

from ..backend import CommandResult
from ..model import CapabilityItem, DesiredStateModel, SearchAction, SearchHit, SelectionState


class PreviewPlanModal(ModalScreen[str]):
    """Preview computed profile delta and package impact before Save / Save + Apply."""

    BINDINGS = [
        Binding("escape", "cancel", "Back"),
    ]

    def __init__(
        self,
        plan: dict[str, Any],
        *,
        dry_run: bool = False,
        editing_active: bool = True,
        active_name: str = "",
    ) -> None:
        super().__init__()
        self.plan = plan
        self.dry_run = dry_run
        self.editing_active = editing_active
        self.active_name = active_name

    def compose(self) -> ComposeResult:
        p = self.plan
        delta = p.get("delta") or {}
        lines: list[str] = [
            f"Target profile: {p.get('target_profile') or '—'}",
            f"Overlay:        {p.get('overlay_name') or '—'}",
            f"Overlay file:   {p.get('overlay_file') or '—'}",
            "",
            "Profile changes:",
        ]
        for g in delta.get("add_groups") or []:
            lines.append(f"  + group:{g}")
        for c in delta.get("add_components") or []:
            lines.append(f"  + component:{c}")
        for s in delta.get("add_supergroups") or []:
            lines.append(f"  + supergroup:{s}")
        for g in delta.get("remove_groups") or []:
            lines.append(f"  - group:{g}")
        for c in delta.get("remove_components") or []:
            lines.append(f"  - component:{c}")
        for s in delta.get("remove_supergroups") or []:
            lines.append(f"  - supergroup:{s}")
        for pkg in delta.get("add_packages") or []:
            lines.append(f"  + package:{pkg}")
        for pkg in delta.get("remove_packages") or []:
            lines.append(f"  - package:{pkg}")
        if not p.get("changed"):
            lines.append("  (no profile changes)")

        to_install = p.get("packages_to_install") or []
        satisfied = p.get("already_satisfied_packages") or []
        unsupported = p.get("unsupported") or []
        comps_cfg = p.get("components_to_configure") or []

        lines.extend(["", f"Packages expected to install ({len(to_install)}):"])
        if to_install:
            for pkg in to_install[:25]:
                if isinstance(pkg, dict):
                    via = pkg.get("desired_via") or ""
                    kind = pkg.get("kind") or ""
                    lines.append(f"  {pkg.get('name')} ({kind}, {via})")
                else:
                    lines.append(f"  {pkg}")
            if len(to_install) > 25:
                lines.append(f"  ... (+{len(to_install) - 25} more)")
        else:
            lines.append("  (none)")

        lines.extend(["", f"Already satisfied ({len(satisfied)}):"])
        if satisfied:
            for pkg in satisfied[:15]:
                lines.append(f"  {pkg}")
            if len(satisfied) > 15:
                lines.append(f"  ... (+{len(satisfied) - 15} more)")
        else:
            lines.append("  (none)")

        if comps_cfg:
            lines.extend(["", "Components to configure:"])
            for cid in comps_cfg:
                lines.append(f"  {cid}")

        if unsupported:
            lines.extend(["", "Unsupported on this platform:"])
            for u in unsupported:
                lines.append(f"  ! {u.get('id')}: {u.get('reason')}")

        for sat in p.get("explicit_satisfied_by_owner") or []:
            lines.append(f"  explicit package satisfied by owner bundle: {sat.get('name')} ({sat.get('owner')})")
        lines.extend([
            "",
            "Owner bundles are not enabled by explicit package selection.",
            "No automatic uninstall: removed software may remain installed.",
        ])
        if self.editing_active:
            lines.append("Saving keeps the current active profile.")
        else:
            lines.append(
                f"Saving this preview will NOT activate {p.get('overlay_name') or 'this profile'}."
            )
            lines.append(f"Active machine profile stays: {self.active_name or '(unchanged)'}")
            lines.append("Save + Activate + Apply will make this profile active and converge the machine.")
        if self.dry_run:
            lines.append("[DRY-RUN MODE: Save/Apply buttons simulate without mutating]")

        save_label = "Save" if self.editing_active else "Save Profile"
        apply_label = "Save + Apply" if self.editing_active else "Save + Activate + Apply"
        with Vertical(id="modal-dialog"):
            yield Label("Preview Desired-State Plan", classes="modal-title")
            with VerticalScroll(id="modal-scroll"):
                yield Static("\n".join(lines), id="preview-text")
            with Horizontal(classes="modal-buttons"):
                yield Button(save_label, id="btn-save", variant="primary")
                yield Button(apply_label, id="btn-apply", variant="success")
                yield Button("Back", id="btn-cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-save":
            self.dismiss("save")
        elif event.button.id == "btn-apply":
            self.dismiss("apply")
        else:
            self.dismiss("cancel")

    def action_cancel(self) -> None:
        self.dismiss("cancel")


class UnsavedChangesModal(ModalScreen[str]):
    """Confirm Save / Discard / Cancel when quitting with unsaved changes."""

    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
    ]

    def __init__(self, pending_summary: str) -> None:
        super().__init__()
        self.pending_summary = pending_summary

    def compose(self) -> ComposeResult:
        with Vertical(id="modal-dialog-sm"):
            yield Label("You have unsaved changes.", classes="modal-title")
            yield Static(f"Pending: {self.pending_summary}", classes="modal-body")
            with Horizontal(classes="modal-buttons"):
                yield Button("Save", id="btn-save", variant="primary")
                yield Button("Discard", id="btn-discard", variant="warning")
                yield Button("Cancel", id="btn-cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-save":
            self.dismiss("save")
        elif event.button.id == "btn-discard":
            self.dismiss("discard")
        else:
            self.dismiss("cancel")

    def action_cancel(self) -> None:
        self.dismiss("cancel")


class AmbiguousOwnerModal(ModalScreen[str | None]):
    """Let user pick an owner when a package belongs to multiple DOTS owners."""

    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
    ]

    def __init__(self, package_name: str, choices: list[str]) -> None:
        super().__init__()
        self.package_name = package_name
        self.choices = choices

    def compose(self) -> ComposeResult:
        with Vertical(id="modal-dialog-sm"):
            yield Label(f"{self.package_name} is available through:", classes="modal-title")
            yield ListView(
                *[ListItem(Label(f"  {c}")) for c in self.choices],
                id="ambig-list",
            )
            with Horizontal(classes="modal-buttons"):
                yield Button("Select", id="btn-select", variant="primary")
                yield Button("Cancel", id="btn-cancel")

    def on_mount(self) -> None:
        lv = self.query_one("#ambig-list", ListView)
        if self.choices:
            lv.index = 0
        lv.focus()

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        idx = event.list_view.index
        if idx is not None and 0 <= idx < len(self.choices):
            self.dismiss(self.choices[idx])

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-select":
            lv = self.query_one("#ambig-list", ListView)
            idx = lv.index
            if idx is not None and 0 <= idx < len(self.choices):
                self.dismiss(self.choices[idx])
                return
        self.dismiss(None)

    def action_cancel(self) -> None:
        self.dismiss(None)


class EditTargetModal(ModalScreen[str]):
    """Protect unsaved edits before the Profile Editor loads a different profile."""

    BINDINGS = [Binding("escape", "cancel", "Cancel")]

    def __init__(self, current_name: str, next_target: str) -> None:
        super().__init__()
        self.current_name = current_name
        self.next_target = next_target

    def compose(self) -> ComposeResult:
        with Vertical(id="modal-dialog-sm"):
            yield Label(f"Unsaved changes in profile {self.current_name}", classes="modal-title")
            yield Static(
                "Save the current profile, discard those edits, or stay here.",
                classes="modal-body",
            )
            with Horizontal(classes="modal-buttons"):
                yield Button(f"Save {self.current_name}", id="btn-save-target", variant="primary")
                yield Button("Discard and edit", id="btn-discard-target", variant="warning")
                yield Button("Cancel", id="btn-cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-save-target":
            self.dismiss("save")
        elif event.button.id == "btn-discard-target":
            self.dismiss("discard")
        else:
            self.dismiss("cancel")

    def action_cancel(self) -> None:
        self.dismiss("cancel")


class LeafActionModal(ModalScreen[SearchAction | None]):
    """Stage an individual package or its owner. Buttons act immediately."""

    BINDINGS = [Binding("escape", "cancel", "Cancel")]

    def __init__(self, hit: SearchHit, item: CapabilityItem | None) -> None:
        super().__init__()
        self.hit = hit
        self.item = item

    def compose(self) -> ComposeResult:
        hit = self.hit
        item = self.item
        state = item.working.tag if item else (hit.state_tag or "absent")
        lines = [
            hit.title,
            "",
            f"Owner: {hit.owner_selector or '(unknown)'}",
            f"State: {state}",
        ]
        if hit.install_method or hit.install_token:
            lines.append(f"Install route: {hit.install_method} {hit.install_kind} {hit.install_token}".strip())
        leaf_ok = bool(hit.leaf_selectable) and bool(item.supported if item else hit.installable is not False)
        unsupported = bool(item and not item.supported) or hit.installable is False
        lifecycle = hit.leaf_selectable is False
        if lifecycle:
            lines.extend([
                "",
                "This package cannot be selected independently.",
                f"Reason: {hit.leaf_reason or hit.unsupported_reason or 'requires component lifecycle'}",
            ])
        elif unsupported:
            lines.extend([
                "",
                "Unavailable on this platform.",
                f"Reason: {hit.unsupported_reason or (item.unsupported_reason if item else '') or 'unsupported'}",
            ])
        with Vertical(id="modal-dialog"):
            yield Label("Add or Manage Software", classes="modal-title")
            yield Static("\n".join(lines))
            with Horizontal(classes="modal-buttons"):
                if leaf_ok and not unsupported and state in ("absent", "excluded"):
                    yield Button(f"Add {hit.title} only", id="btn-add-leaf", variant="primary")
                if leaf_ok and not unsupported and state == "local":
                    yield Button(f"Remove {hit.title} from profile", id="btn-remove-leaf", variant="warning")
                if leaf_ok and not unsupported and state == "inherited":
                    yield Button(f"Exclude {hit.title} in this profile", id="btn-remove-leaf", variant="warning")
                if hit.owner_selector and not unsupported and lifecycle:
                    yield Button(f"Enable {hit.owner_selector}", id="btn-owner", variant="primary")
                elif hit.owner_selector and not unsupported and state in ("absent", "excluded"):
                    yield Button(f"Enable {hit.owner_selector}", id="btn-owner")
                if hit.owner_selector and (unsupported or state in ("local", "inherited")):
                    yield Button("View owner", id="btn-focus")
                elif unsupported:
                    yield Button("View details", id="btn-focus")
                yield Button("Cancel", id="btn-cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        pkg = f"package:{self.hit.target_id}"
        bid = event.button.id
        if bid == "btn-add-leaf":
            self.dismiss(SearchAction(pkg, "add"))
        elif bid == "btn-remove-leaf":
            self.dismiss(SearchAction(pkg, "remove"))
        elif bid == "btn-owner" and self.hit.owner_selector:
            self.dismiss(SearchAction(self.hit.owner_selector, "add"))
        elif bid == "btn-focus":
            target = self.hit.owner_selector or pkg
            self.dismiss(SearchAction(target, "focus"))
        else:
            self.dismiss(None)

    def action_cancel(self) -> None:
        self.dismiss(None)


class PackageSearchModal(ModalScreen[SearchAction | None]):
    """Search packages, groups, components, and bundles. Actions stage immediately."""

    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
    ]

    def __init__(self, model: DesiredStateModel) -> None:
        super().__init__()
        self.model = model
        self._hits: list[SearchHit] = []

    def compose(self) -> ComposeResult:
        with Vertical(id="modal-dialog"):
            yield Label("Add or Manage Software", classes="modal-title")
            yield Input(placeholder="Search packages, groups, components, or bundles…", id="search-input")
            yield ListView(id="search-results")
            yield Static("Choose a result. The action stages desired state immediately.", id="search-hint")
            with Horizontal(classes="modal-buttons"):
                yield Button("Cancel", id="btn-cancel")

    def on_mount(self) -> None:
        self.query_one("#search-input", Input).focus()

    def on_input_changed(self, event: Input.Changed) -> None:
        q = event.value.strip()
        lv = self.query_one("#search-results", ListView)
        lv.clear()
        self._hits = self.model.search(q) if q else []
        kind_label = {"package": "individual", "group": "group", "component": "component", "supergroup": "bundle"}
        for h in self._hits[:40]:
            kind = kind_label.get(h.kind, h.kind)
            state = h.state_tag or "absent"
            owner = ""
            if h.kind == "package" and h.owner_selector:
                owner = f"  owner: {h.owner_selector.split(':', 1)[-1]}"
            lv.append(ListItem(Label(f"{h.title:<18} {kind:<12} {state:<12}{owner}")))

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        idx = event.list_view.index
        if idx is None or idx < 0 or idx >= len(self._hits):
            return
        hit = self._hits[idx]
        self._resolve_and_return(hit)

    def on_input_submitted(self, event: Input.Submitted) -> None:
        if self._hits:
            self._resolve_and_return(self._hits[0])
            return
        raw = event.value.strip()
        if not raw:
            return
        try:
            res = self.model.backend.resolve_selector(raw)
        except Exception as exc:
            self.query_one("#search-hint", Static).update(f"Lookup error: {exc}")
            return
        status = res.get("status")
        if status == "ok" and res.get("owner"):
            owner = str(res["owner"])
            note = self._build_package_note(raw, owner, res.get("group_packages") or [], res)
            self.dismiss(self._action_for_selector(owner, note))
        elif status == "ambiguous":
            choices = list(res.get("choices") or [])
            self._pick_ambiguous(raw, choices, res.get("group_packages") or {}, res)
        else:
            self.query_one("#search-hint", Static).update(
                f"'{raw}' is not declared in DOTS. Maintainer workflow: dots packages adopt {raw} --group modern"
            )

    def _action_for_selector(self, selector: str, note: str = "") -> SearchAction:
        item = self.model.get(selector)
        if item and item.supported and not item.working.is_desired:
            return SearchAction(selector, "add", note)
        return SearchAction(selector, "focus", note)

    def _resolve_and_return(self, hit: SearchHit) -> None:
        if hit.kind == "package":
            item = self.model.get(f"package:{hit.target_id}")
            self.app.push_screen(LeafActionModal(hit, item), self._on_leaf_action)
            return
        if hit.owner_selector:
            self.dismiss(self._action_for_selector(hit.owner_selector))
            return
        try:
            res = self.model.backend.resolve_selector(hit.target_id)
        except Exception:
            return
        status = res.get("status")
        if status == "ok" and res.get("owner"):
            owner = str(res["owner"])
            note = self._build_package_note(hit.target_id, owner, res.get("group_packages") or [], res)
            self.dismiss(self._action_for_selector(owner, note))
        elif status == "ambiguous":
            choices = list(res.get("choices") or [])
            self._pick_ambiguous(hit.target_id, choices, res.get("group_packages") or {}, res)

    def _on_leaf_action(self, choice: SearchAction | None) -> None:
        if choice:
            self.dismiss(choice)

    def _pick_ambiguous(
        self,
        pkg: str,
        choices: list[str],
        grp_pkgs: dict[str, list[str]],
        res: dict[str, Any] | None = None,
    ) -> None:
        def _picked(choice: str | None) -> None:
            if not choice:
                return
            gpkgs = grp_pkgs.get(choice.split(":", 1)[1], []) if choice.startswith("group:") else []
            note = self._build_package_note(pkg, choice, gpkgs, res)
            self.dismiss(self._action_for_selector(choice, note))

        self.app.push_screen(AmbiguousOwnerModal(pkg, choices), _picked)

    def _build_package_note(
        self,
        pkg: str,
        owner: str,
        group_pkgs: list[str],
        res: dict[str, Any] | None = None,
    ) -> str:
        res = res or {}
        pkg_info = res.get("package") or {}
        grp_sum = res.get("group_summary") or {}
        lines: list[str] = []
        if pkg_info:
            lines.append(f"{pkg_info.get('name') or pkg}")
            lines.append(f"Owner: {owner}")
            if not pkg_info.get("installable", True):
                lines.append("Platform: unavailable through DOTS on this machine")
                if pkg_info.get("unsupported_reason"):
                    lines.append(f"Reason: {pkg_info['unsupported_reason']}")
                inst_lbl = "yes (external)" if pkg_info.get("installed") else "no"
                lines.append(f"Installed: {inst_lbl}")
            else:
                meth = pkg_info.get("install_method") or "brew"
                tok = pkg_info.get("install_token") or pkg
                lines.append(f"Installable: yes ({meth}: {tok})")
                inst_lbl = "yes (external)" if pkg_info.get("external") else ("yes" if pkg_info.get("installed") else "no")
                lines.append(f"Installed: {inst_lbl}")
            lines.append("")

        if not owner.startswith("group:"):
            if not lines:
                return f"Package {pkg} is provided by {owner}."
            lines.append(f"Selecting {owner} enables this component.")
            return "\n".join(lines)

        gname = owner.split(":", 1)[1]
        if pkg_info and not pkg_info.get("installable", True):
            supp = grp_sum.get("supported_package_count")
            tot = grp_sum.get("package_count")
            cnt_note = f" ({supp}/{tot} supported)" if supp is not None and tot is not None else ""
            lines.append(
                f"Direct install of {pkg} is unavailable here, though selecting {owner}{cnt_note} remains valid."
            )
        else:
            lines.append(f"Selecting {pkg} activates package group {gname}.")

        others = [p for p in group_pkgs if p != pkg]
        preview = "\n".join(f"  {p}" for p in others[:12])
        more = f"\n  ... (+{len(others) - 12} more)" if len(others) > 12 else ""
        lines.extend(["", f"Additional packages in {gname}:", f"{preview}{more}"])
        return "\n".join(lines)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-cancel":
            self.dismiss(None)

    def action_cancel(self) -> None:
        self.dismiss(None)


class ApplyProgressModal(ModalScreen[bool]):
    """Execute a save/apply or upgrade command while streaming output."""

    BINDINGS = [
        Binding("escape", "close_if_done", "Close"),
    ]

    def __init__(
        self,
        title: str,
        runner: Callable[[Callable[[str], None]], CommandResult],
        *,
        failure_footer: str = "",
    ) -> None:
        super().__init__()
        self._title = title
        self._runner = runner
        self._failure_footer = failure_footer
        self._done = False
        self._ok = False

    def compose(self) -> ComposeResult:
        with Vertical(id="modal-dialog"):
            yield Label(self._title, classes="modal-title")
            yield Static(
                "Profile persisted: PENDING   Convergence: RUNNING",
                id="apply-stages",
            )
            yield RichLog(id="apply-log", wrap=True, highlight=False, markup=False)
            yield Static("", id="apply-result")
            with Horizontal(classes="modal-buttons"):
                yield Button("Close", id="btn-close", disabled=True)

    def on_mount(self) -> None:
        self.run_worker(self._execute, thread=True, exclusive=True)

    def _append_log(self, line: str) -> None:
        log = self.query_one("#apply-log", RichLog)
        log.write(line)

    def _finish(self, res: CommandResult) -> None:
        self._done = True
        self._ok = res.ok
        stages = self.query_one("#apply-stages", Static)
        result_box = self.query_one("#apply-result", Static)
        btn = self.query_one("#btn-close", Button)
        btn.disabled = False
        btn.focus()
        if res.ok:
            stages.update("Profile persisted: OK   Convergence: OK   Verification: OK")
            result_box.update("Operation completed successfully.")
        else:
            stages.update("Operation completed with errors.")
            msg = self._failure_footer or f"Command exited with code {res.returncode}."
            result_box.update(msg)

    def _execute(self) -> None:
        def _cb(line: str) -> None:
            self.app.call_from_thread(self._append_log, line)

        try:
            res = self._runner(_cb)
        except Exception as exc:  # noqa: BLE001
            res = CommandResult(1, "", str(exc))
            self.app.call_from_thread(self._append_log, f"Error: {exc}")
        self.app.call_from_thread(self._finish, res)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if self._done:
            self.dismiss(self._ok)

    def action_close_if_done(self) -> None:
        if self._done:
            self.dismiss(self._ok)


class AllUpgradeConfirmModal(ModalScreen[bool]):
    """Explicit warning confirmation before upgrading outside DOTS desired scope."""

    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
    ]

    def compose(self) -> ComposeResult:
        with Vertical(id="modal-dialog-sm"):
            yield Label("Upgrade ALL Homebrew packages (--all)?", classes="modal-title")
            yield Static(
                "This may upgrade Homebrew software outside your active DOTS desired state.\n"
                "DOTS still never runs brew cleanup or uninstalls packages.",
                classes="modal-body",
            )
            with Horizontal(classes="modal-buttons"):
                yield Button("Upgrade All (--all)", id="btn-yes", variant="warning")
                yield Button("Cancel", id="btn-no")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.dismiss(event.button.id == "btn-yes")

    def action_cancel(self) -> None:
        self.dismiss(False)


class ConfirmActionModal(ModalScreen[bool]):
    """Generic yes/no confirmation modal."""

    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
    ]

    def __init__(self, title: str, body: str, confirm_label: str = "Confirm") -> None:
        super().__init__()
        self._title = title
        self._body = body
        self._confirm_label = confirm_label

    def compose(self) -> ComposeResult:
        with Vertical(id="modal-dialog-sm"):
            yield Label(self._title, classes="modal-title")
            yield Static(self._body, classes="modal-body")
            with Horizontal(classes="modal-buttons"):
                yield Button(self._confirm_label, id="btn-yes", variant="primary")
                yield Button("Cancel", id="btn-no")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.dismiss(event.button.id == "btn-yes")

    def action_cancel(self) -> None:
        self.dismiss(False)


class HelpKeysModal(ModalScreen[None]):
    """Keyboard shortcuts and state glyph legend."""

    BINDINGS = [
        Binding("escape", "close", "Close"),
        Binding("q", "close", "Close"),
    ]

    def compose(self) -> ComposeResult:
        lines = [
            "Keyboard Navigation:",
            "  Up/Down   Move selection",
            "  Space     Toggle capability",
            "  Tab       Next pane",
            "  Shift+Tab Previous pane",
            "  /         Add or manage software",
            "  v         Change catalog view",
            "  p         Preview plan",
            "  s         Save profile (does not activate a different profile)",
            "  a         Save + Apply, or Save + Activate + Apply",
            "  r         Refresh from backend",
            "  ?         This legend",
            "  q         Quit (prompts if unsaved)",
            "",
            "Profiles chooses a profile. Profile Editor changes its desired software.",
            "Active is the machine profile. Editing is the profile open in the editor.",
            "Save Profile writes without changing which profile is active.",
            "Save + Activate + Apply asks before switching the active profile.",
            "",
            "Selection States (non-color accessible):",
        ]
        for st in SelectionState:
            lines.append(f"  {st.glyph()} [{st.tag:<11}] {st.explanation}")

        with Vertical(id="modal-dialog-sm"):
            yield Label("DOTS TUI Help & Legend", classes="modal-title")
            yield Static("\n".join(lines), classes="modal-body")
            with Horizontal(classes="modal-buttons"):
                yield Button("Close", id="btn-close", variant="primary")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.dismiss(None)

    def action_close(self) -> None:
        self.dismiss(None)
