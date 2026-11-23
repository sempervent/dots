"""Profile inspection, inheritance chain, local diff, and switching pane."""

from __future__ import annotations

from typing import Any

from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.widgets import Button, Label, ListItem, ListView, Static

from ..model import DesiredStateModel
from .modals import ApplyProgressModal, ConfirmActionModal


def format_profile_details(data: dict[str, Any], *, editing_file: str = "") -> str:
    """Render structured profile JSON, including explicit package deltas."""
    name = data.get("profile") or "(none)"
    kind = data.get("profile_kind") or "none"
    pfile = str(data.get("profile_file") or "(none)")
    chain = data.get("source_chain") or []
    adds = data.get("local_additions") or {}
    rems = data.get("local_removals") or {}
    runtime = data.get("runtime") or {}
    editing = bool(editing_file) and pfile == editing_file

    lines = [
        f"Profile: {name}   [{kind}]",
        f"File:    {pfile}",
        f"Active:  {'yes' if data.get('active') else 'no'}",
        f"Editing: {'yes' if editing else 'no'}",
        f"Extends: {data.get('extends') or '(none)'}",
        "",
        "Source chain:",
    ]
    if chain:
        for idx, c in enumerate(chain):
            if idx > 0:
                lines.append("    ↓")
            lines.append(f"  {c.get('name')}  [{c.get('kind')}]  ({c.get('file')})")
    else:
        lines.append("  (none)")

    lines.extend(["", "Local additions:"])
    any_add = False
    for g in adds.get("groups") or []:
        lines.append(f"  + group:{g}")
        any_add = True
    for c in adds.get("components") or []:
        lines.append(f"  + component:{c}")
        any_add = True
    for s in adds.get("supergroups") or []:
        lines.append(f"  + supergroup:{s}")
        any_add = True
    for pkg in adds.get("packages") or []:
        lines.append(f"  + package:{pkg}")
        any_add = True
    if not any_add:
        lines.append("  (none)")

    lines.extend(["", "Local exclusions:"])
    any_rem = False
    for g in rems.get("groups") or []:
        lines.append(f"  - group:{g}")
        any_rem = True
    for c in rems.get("components") or []:
        lines.append(f"  - component:{c}")
        any_rem = True
    for s in rems.get("supergroups") or []:
        lines.append(f"  - supergroup:{s}")
        any_rem = True
    for pkg in rems.get("packages") or []:
        lines.append(f"  - package:{pkg}")
        any_rem = True
    if not any_rem:
        lines.append("  (none)")

    if runtime:
        lines.extend(["", "Runtime overrides:"])
        for key in sorted(runtime):
            lines.append(f"  {key} = {runtime[key]}")
    return "\n".join(lines)


class ProfilePane(Vertical):
    """Inspect active or other profiles, inheritance chain, and local deltas."""

    def __init__(self, model: DesiredStateModel, *, dry_run: bool = False, **kwargs) -> None:
        super().__init__(**kwargs)
        self.model = model
        self.dry_run = dry_run
        self._inspected: dict[str, Any] = {}
        self._profiles: list[dict[str, Any]] = []

    def compose(self) -> ComposeResult:
        with Horizontal(id="profile-split"):
            with Vertical(id="profile-left"):
                yield Label("Profiles", classes="pane-title")
                yield Static("Create new profiles with: dots profile create", id="profile-create-hint")
                yield ListView(id="profile-catalog")
            with Vertical(id="profile-right"):
                yield Label("Profile Details & Source Chain", classes="pane-title")
                with VerticalScroll(id="profile-scroll"):
                    yield Static("", id="profile-details")
        with Vertical(id="profile-actions"):
            with Horizontal():
                yield Button("Edit Selected", id="btn-edit-selected", variant="primary")
                yield Button("Edit Active", id="btn-edit-active")
                yield Button("Refresh (r)", id="btn-prof-refresh")
            with Horizontal():
                yield Button("Switch Only", id="btn-switch-only")
                yield Button("Switch + Apply", id="btn-switch-apply", variant="success")

    def on_mount(self) -> None:
        self.refresh_view()

    def refresh_view(self) -> None:
        self._profiles = list(self.model.profiles_catalog)
        lv = self.query_one("#profile-catalog", ListView)
        lv.clear()
        active_idx = 0
        for i, p in enumerate(self._profiles):
            kind = str(p.get("kind") or "custom")
            name = str(p.get("name") or "")
            flags: list[str] = []
            if p.get("active"):
                flags.append("ACTIVE")
                active_idx = i
            if str(p.get("file") or "") == self.model.profile_file:
                flags.append("EDITING")
            mark = "*" if p.get("active") else " "
            editing = ">" if "EDITING" in flags else " "
            flag_s = ("  " + " · ".join(flags)) if flags else ""
            lv.append(ListItem(Label(f"{mark}{editing} {name:<16} [{kind}]{flag_s}")))
        if self._profiles:
            lv.index = active_idx
            self._inspect_profile(str(self._profiles[active_idx].get("file") or ""))
        else:
            self._render_from_model()

    def _inspect_profile(self, target: str) -> None:
        if not target:
            self._render_from_model()
            return
        try:
            self._inspected = self.model.backend.profile_show(target)
        except Exception as exc:
            self.query_one("#profile-details", Static).update(f"Error loading profile: {exc}")
            return
        self._render_profile_dict(self._inspected)

    def _render_from_model(self) -> None:
        m = self.model
        chain = m.source_chain or [{"name": m.profile_name, "kind": m.profile_kind, "file": m.profile_file}]
        lines = [
            f"Profile: {m.profile_name} [{m.profile_kind or 'none'}]",
            f"File:    {m.profile_file or '(none)'}",
            "",
            "Source chain:",
        ]
        for idx, c in enumerate(chain):
            prefix = "  " if idx == 0 else "  ↓ "
            lines.append(f"{prefix}{c.get('name')} [{c.get('kind')}]")
        self.query_one("#profile-details", Static).update("\n".join(lines))

    def _render_profile_dict(self, data: dict[str, Any]) -> None:
        text = format_profile_details(data, editing_file=self.model.profile_file)
        self.query_one("#profile-details", Static).update(text)

    def on_list_view_highlighted(self, event: ListView.Highlighted) -> None:
        if event.list_view.id != "profile-catalog":
            return
        idx = event.list_view.index
        if idx is None or idx < 0 or idx >= len(self._profiles):
            return
        self._inspect_profile(str(self._profiles[idx].get("file") or ""))

    def _selected_profile_entry(self) -> dict[str, Any] | None:
        lv = self.query_one("#profile-catalog", ListView)
        idx = lv.index
        if idx is None or idx < 0 or idx >= len(self._profiles):
            return None
        return self._profiles[idx]

    def on_button_pressed(self, event: Button.Pressed) -> None:
        bid = event.button.id
        if bid == "btn-prof-refresh":
            self.app.action_refresh()  # type: ignore[attr-defined]
            return
        if bid == "btn-edit-active":
            active = self.model.current_active_profile()
            if not active:
                self.app.notify("No active profile is recorded.", severity="warning")
                return
            self.app.request_edit_profile(str(active.get("file") or active.get("name") or ""))  # type: ignore[attr-defined]
            return
        entry = self._selected_profile_entry()
        if bid == "btn-edit-selected":
            if not entry:
                return
            self.app.request_edit_profile(str(entry.get("file") or entry.get("name") or ""))  # type: ignore[attr-defined]
            return
        if not entry:
            return
        target = str(entry.get("file") or entry.get("name") or "")
        pname = str(entry.get("name") or target)
        if bid == "btn-switch-only":
            def _do_switch(ok: bool) -> None:
                if not ok:
                    return
                res = self.model.backend.profile_switch(target, apply=False, dry_run=self.dry_run)
                if res.ok:
                    self.app.notify(f"Switched active profile to {pname}")
                    self.app.action_refresh()  # type: ignore[attr-defined]
                else:
                    self.app.notify(res.combined or "Switch failed", severity="error")

            self.app.push_screen(
                ConfirmActionModal("Switch active profile?", f"Switch active profile pointer to '{pname}'?"),
                _do_switch,
            )
        elif bid == "btn-switch-apply":
            def _do_switch_apply(ok: bool) -> None:
                if not ok:
                    return
                if self.dry_run:
                    res = self.model.backend.profile_switch(target, apply=True, dry_run=True)
                    self.app.notify(res.combined or "[dry-run] switch + apply")
                    return

                def _runner(cb):
                    return self.model.backend.profile_switch(target, apply=True, on_line=cb)

                def _done(success: bool) -> None:
                    self.app.action_refresh()  # type: ignore[attr-defined]
                    if success:
                        self.app.notify(f"Switched and applied {pname}")

                self.app.push_screen(
                    ApplyProgressModal(
                        f"Switch + Apply: {pname}",
                        _runner,
                        failure_footer=f"Convergence failed for {pname}. Retry: dots profile apply {pname}",
                    ),
                    _done,
                )

            self.app.push_screen(
                ConfirmActionModal(
                    "Switch + Apply profile?",
                    f"Switch active profile to '{pname}' and converge the machine via bootstrap.sh?",
                    confirm_label="Switch + Apply",
                ),
                _do_switch_apply,
            )
