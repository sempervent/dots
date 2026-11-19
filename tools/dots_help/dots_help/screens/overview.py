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
            yield Button("Go to Software", id="ov-software", variant="primary")
            yield Button("Go to Profile", id="ov-profile")
            yield Button("Go to Upgrade", id="ov-upgrade")
            yield Button("Refresh (r)", id="ov-refresh")

    def on_mount(self) -> None:
        self.refresh_view()

    def refresh_view(self) -> None:
        st = gather_state()
        m = self.model
        chain_names = " -> ".join(str(c.get("name")) for c in m.source_chain) or m.profile_name
        desired_groups = [g.id for g in m.groups if g.working.is_desired]
        desired_comps = [c.id for c in m.components if c.working.is_desired]

        lines = [
            f"DOTS v{st.version}",
            "════════════════════════════════════════",
            "",
            f"Host:            {st.host}",
            f"OS / Arch:       {st.os_name} / {st.arch}",
            f"Shell:           {st.shell}",
            f"Multiplexer:     {m.runtime.get('multiplexer') or st.multiplexer or 'tmux'}",
            "",
            f"Active profile:  {m.profile_name} ({m.profile_kind or 'none'})",
            f"Profile file:    {m.profile_file or '(none)'}",
            f"Source chain:    {chain_names}",
            "",
            f"Selected groups ({len(desired_groups)}):",
            f"  {', '.join(desired_groups) if desired_groups else '(none)'}",
            "",
            f"Selected components ({len(desired_comps)}):",
            f"  {', '.join(desired_comps) if desired_comps else '(none)'}",
            "",
            f"Pending changes: {m.pending_summary()}",
            f"Backups:         {st.backup_count} (latest: {st.backup_latest or 'none'})",
        ]
        self.query_one("#overview-body", Static).update("\n".join(lines))

    def on_button_pressed(self, event: Button.Pressed) -> None:
        bid = event.button.id
        if bid == "ov-software":
            self.app.switch_tab("tab-software")  # type: ignore[attr-defined]
        elif bid == "ov-profile":
            self.app.switch_tab("tab-profile")  # type: ignore[attr-defined]
        elif bid == "ov-upgrade":
            self.app.switch_tab("tab-upgrade")  # type: ignore[attr-defined]
        elif bid == "ov-refresh":
            self.app.action_refresh()  # type: ignore[attr-defined]
