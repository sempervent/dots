"""Overview pane displaying lightweight local DOTS state."""

from __future__ import annotations

from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.widgets import Button, Static

from ..model import DesiredStateModel
from ..state import gather_state


class OverviewPane(Vertical):
    """Lightweight read-only dashboard (no network, no brew outdated)."""

    def __init__(self, model: DesiredStateModel, **kwargs) -> None:
        super().__init__(**kwargs)
        self.model = model

    def compose(self) -> ComposeResult:
        with VerticalScroll(id="overview-scroll"):
            yield Static("", id="overview-body")
        with Horizontal(id="overview-actions"):
            yield Button("Edit Profile", id="ov-software", variant="primary")
            yield Button("Add Software", id="ov-search")
            yield Button("Review Upgrades", id="ov-upgrade")
            yield Button("Profiles", id="ov-profile")

    def on_mount(self) -> None:
        self.refresh_view()

    def refresh_view(self) -> None:
        st = gather_state()
        m = self.model
        chain_names = " -> ".join(str(c.get("name")) for c in m.source_chain) or m.profile_name
        desired_groups = [g.id for g in m.groups if g.working.is_desired]
        desired_comps = [c.id for c in m.components if c.working.is_desired]
        desired_pkgs = [p.id for p in m.explicit_packages if p.working.is_desired]
        active = m.current_active_profile()
        active_name = str((active or {}).get("name") or m.profile_name)

        lines = [
            f"DOTS v{st.version}",
            "════════════════════════════════════════",
            "",
            f"Host:            {st.host}",
            f"OS / Arch:       {st.os_name} / {st.arch}",
            f"Shell:           {st.shell}",
            f"Multiplexer:     {m.runtime.get('multiplexer') or st.multiplexer or 'tmux'}",
            "",
            f"Active profile:  {active_name}",
            f"Editing profile: {m.profile_name} ({m.profile_kind or 'none'})",
            f"Source chain:    {chain_names}",
            "",
            "Desired state:",
            f"  {len(desired_groups)} package groups",
            f"  {len(desired_comps)} components",
            f"  {len(desired_pkgs)} explicit packages",
            "",
            f"Pending edits:   {m.pending_summary()}",
            "Updates:         Review Upgrades lists outdated managed packages.",
            f"Backups:         {st.backup_count} (latest: {st.backup_latest or 'none'})",
            "",
            "Next: Edit Profile, Add Software, or Review Upgrades.",
        ]
        self.query_one("#overview-body", Static).update("\n".join(lines))

    def on_button_pressed(self, event: Button.Pressed) -> None:
        bid = event.button.id
        if bid == "ov-software":
            self.app.switch_tab("tab-software")  # type: ignore[attr-defined]
        elif bid == "ov-search":
            self.app.switch_tab("tab-software")  # type: ignore[attr-defined]
            self.app.action_search()  # type: ignore[attr-defined]
        elif bid == "ov-profile":
            self.app.switch_tab("tab-profile")  # type: ignore[attr-defined]
        elif bid == "ov-upgrade":
            self.app.switch_tab("tab-upgrade")  # type: ignore[attr-defined]
        elif bid == "ov-refresh":
            self.app.action_refresh()  # type: ignore[attr-defined]
