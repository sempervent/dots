"""Dynamic Desired-State Textual TUI for DOTS."""

from __future__ import annotations

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import Button, Footer, Header, Input, Static, TabbedContent, TabPane

from .backend import BackendError, CommandResult, DotsBackend
from .model import DesiredStateModel
from .registry import Registry
from .screens.help_pane import HelpPane
from .screens.manage import SoftwarePane
from .screens.modals import (
    ApplyProgressModal,
    ConfirmActionModal,
    HelpKeysModal,
    PackageSearchModal,
    PreviewPlanModal,
    UnsavedChangesModal,
)
from .screens.overview import OverviewPane
from .screens.profile import ProfilePane
from .screens.upgrade import UpgradePane


class DotsTuiApp(App[None]):
    """Dynamic registry-driven lifecycle TUI front-end over DOTS CLI."""

    CSS = """
    Screen {
        background: #1e1e2e;
        color: #cdd6f4;
    }
    #too-small {
        display: none;
        padding: 2;
        color: #f38ba8;
    }
    #main-tabs {
        height: 1fr;
    }
    #software-profile-bar {
        background: #313244;
        color: #cdd6f4;
        padding: 0 1;
        height: 1;
    }
    #software-split, #profile-split {
        height: 1fr;
    }
    #software-left {
        width: 56%;
        border-right: solid #45475a;
    }
    #software-right {
        width: 44%;
        padding: 0 1;
    }
    #software-toolbar {
        height: 3;
        padding: 0 1;
        align-vertical: middle;
    }
    #software-list-title {
        width: 1fr;
        text-style: bold;
    }
    #details-title, .pane-title {
        text-style: bold;
        padding: 0 1;
        background: #181825;
        height: 1;
    }
    #details-scroll, #overview-scroll, #profile-scroll, #upgrade-scroll {
        height: 1fr;
        padding: 1;
    }
    #capability-list, #profile-catalog, #help-topic-list {
        height: 1fr;
    }
    #pending-bar {
        background: #181825;
        color: #a6adc8;
        padding: 0 1;
        height: 1;
    }
    #software-actions, #overview-actions, #profile-actions, #upgrade-actions {
        height: 3;
        padding: 0 1;
        align-vertical: middle;
    }
    Button {
        margin-right: 1;
    }
    .cat-header {
        color: #89b4fa;
        text-style: bold;
        background: #181825;
    }
    .state-inherited {
        color: #a6e3a1;
    }
    .state-local {
        color: #94e2d5;
        text-style: bold;
    }
    .state-excluded {
        color: #fab387;
    }
    .state-unsupported, .cap-disabled {
        color: #6c7086;
    }
    #profile-left {
        width: 42%;
        border-right: solid #45475a;
    }
    #profile-right {
        width: 58%;
    }
    #help-sidebar {
        width: 28;
        border-right: solid #45475a;
        background: #181825;
    }
    #help-body {
        width: 1fr;
        padding: 0 1;
    }
    #modal-dialog {
        width: 84%;
        height: 82%;
        border: round #cba6f7;
        background: #1e1e2e;
        padding: 1 2;
        margin: 2 6;
    }
    #modal-dialog-sm {
        width: 72%;
        height: auto;
        max-height: 75%;
        border: round #cba6f7;
        background: #1e1e2e;
        padding: 1 2;
        margin: 4 10;
    }
    .modal-title {
        text-style: bold;
        color: #cba6f7;
        margin-bottom: 1;
    }
    .modal-body {
        margin-bottom: 1;
    }
    #modal-scroll, #search-results, #ambig-list {
        height: 1fr;
        margin: 1 0;
    }
    #apply-log {
        height: 1fr;
        border: solid #45475a;
        margin: 1 0;
    }
    .modal-buttons {
        height: 3;
        align-horizontal: right;
    }
    """

    BINDINGS = [
        Binding("space", "toggle_item", "Toggle", show=True),
        Binding("slash", "search", "Search", key_display="/"),
        Binding("p", "preview", "Preview"),
        Binding("s", "save_only", "Save"),
        Binding("a", "save_apply", "Save+Apply"),
        Binding("r", "refresh", "Refresh"),
        Binding("question_mark", "help_keys", "Help", key_display="?"),
        Binding("q", "quit_confirm", "Quit"),
    ]

    def __init__(
        self,
        *,
        backend: DotsBackend | None = None,
        dry_run: bool = False,
        initial_tab: str = "tab-software",
        profile: str | None = None,
    ) -> None:
        super().__init__()
        self.backend = backend or DotsBackend()
        self.reg = Registry(self.backend.root)
        self.model = DesiredStateModel(self.backend)
        self.dry_run = dry_run
        self.initial_tab = initial_tab
        self.target_profile = profile
        self.load_error: str = ""
        try:
            self.model.load(profile)
        except Exception as exc:  # noqa: BLE001
            self.load_error = str(exc)

        ver = self.reg.version()
        self.title = "DOTS"
        self.sub_title = f"v{ver}" + (" [dry-run]" if self.dry_run else "")

    def compose(self) -> ComposeResult:
        yield Header(show_clock=False)
        yield Static(
            "Terminal too small (need at least 60x16). Resize or use ./dots install / ./dots profile.",
            id="too-small",
        )
        with TabbedContent(initial=self.initial_tab, id="main-tabs"):
            with TabPane("Overview", id="tab-overview"):
                yield OverviewPane(self.model, id="overview-pane")
            with TabPane("Software", id="tab-software"):
                yield SoftwarePane(self.model, id="software-pane")
            with TabPane("Profile", id="tab-profile"):
                yield ProfilePane(self.model, dry_run=self.dry_run, id="profile-pane")
            with TabPane("Upgrade", id="tab-upgrade"):
                yield UpgradePane(self.model, dry_run=self.dry_run, id="upgrade-pane")
            with TabPane("Help", id="tab-help"):
                yield HelpPane(self.reg, id="help-pane")
        yield Footer()

    def on_mount(self) -> None:
        if self.load_error:
            self.notify(f"Backend error: {self.load_error}", severity="error")
        self._apply_size_guard(self.size.width, self.size.height)

    def on_resize(self, event) -> None:
        self._apply_size_guard(event.size.width, event.size.height)

    def _apply_size_guard(self, width: int, height: int) -> None:
        too_small = width < 60 or height < 16
        self.query_one("#too-small", Static).styles.display = "block" if too_small else "none"
        self.query_one("#main-tabs", TabbedContent).styles.display = "none" if too_small else "block"

    def switch_tab(self, tab_id: str) -> None:
        self.query_one("#main-tabs", TabbedContent).active = tab_id

    def on_tabbed_content_tab_activated(self, event: TabbedContent.TabActivated) -> None:
        if event.pane.id == "tab-upgrade":
            self.query_one("#upgrade-pane", UpgradePane).ensure_loaded()

    def _reload_all_panes(self, preserve_selector: str | None = None) -> None:
        try:
            self.model.load(self.target_profile)
        except Exception as exc:  # noqa: BLE001
            self.notify(f"Refresh failed: {exc}", severity="error")
            return
        self.query_one("#software-pane", SoftwarePane).rebuild(preserve_selector=preserve_selector)
        self.query_one("#overview-pane", OverviewPane).refresh_view()
        self.query_one("#profile-pane", ProfilePane).refresh_view()

    def _on_main_screen(self) -> bool:
        return len(self.screen_stack) <= 1

    def action_toggle_item(self) -> None:
        if not self._on_main_screen():
            return
        if self.query_one("#main-tabs", TabbedContent).active != "tab-software":
            return
        focused = self.focused
        if isinstance(focused, (Button, Input)):
            return
        self.query_one("#software-pane", SoftwarePane).toggle_current()
        self.query_one("#overview-pane", OverviewPane).refresh_view()

    def action_search(self) -> None:
        if not self._on_main_screen():
            return
        def _done(res: tuple[str, str] | None) -> None:
            if not res:
                return
            owner, note = res
            self.switch_tab("tab-software")
            self.query_one("#software-pane", SoftwarePane).focus_selector(owner, note)

        self.push_screen(PackageSearchModal(self.model), _done)

    def action_preview(self) -> None:
        if not self._on_main_screen():
            return
        adds = self.model.pending_adds()
        removes = self.model.pending_removes()
        try:
            plan = self.backend.profile_plan(
                adds,
                removes,
                profile=self.target_profile or (self.model.profile_file or None),
            )
        except BackendError as exc:
            self.notify(f"Plan failed: {exc}", severity="error")
            return

        def _done(choice: str) -> None:
            if choice == "save":
                self._perform_save_only()
            elif choice == "apply":
                self._perform_save_apply()

        self.push_screen(PreviewPlanModal(plan, dry_run=self.dry_run), _done)

    def _save_only_sync(self) -> CommandResult:
        adds = self.model.pending_adds()
        removes = self.model.pending_removes()
        return self.backend.profile_mutate(
            adds,
            removes,
            profile=self.target_profile or (self.model.profile_file or None),
            expected_hash=self.model.profile_hash or None,
            apply=False,
            dry_run=self.dry_run,
        )

    def action_save_only(self) -> bool:
        if not self._on_main_screen():
            return False
        return self._perform_save_only()

    def _perform_save_only(self) -> bool:
        if not self.model.has_unsaved_changes:
            self.notify("No unsaved changes.")
            return True
        try:
            res = self._save_only_sync()
        except Exception as exc:  # noqa: BLE001
            self.notify(f"Save failed: {exc}", severity="error")
            return False
        if not res.ok:
            self.notify(res.combined or "Save failed", severity="error")
            return False
        if self.dry_run:
            self.notify("[dry-run] Save simulated (no files modified).")
            return True
        # Clear target_profile override if builtin transitioned to *-local overlay
        if self.model.profile_kind == "builtin":
            self.target_profile = None
        self._reload_all_panes()
        self.notify("Profile saved (desired state persisted).")
        return True

    def action_save_apply(self) -> None:
        if not self._on_main_screen():
            return
        self._perform_save_apply()

    def _perform_save_apply(self) -> None:
        adds = self.model.pending_adds()
        removes = self.model.pending_removes()
        if not adds and not removes:
            self.notify("No pending profile changes to save and apply.")
            return
        prof_arg = self.target_profile or (self.model.profile_file or None)
        exp_hash = self.model.profile_hash or None

        if self.dry_run:
            res = self.backend.profile_mutate(
                adds,
                removes,
                profile=prof_arg,
                expected_hash=exp_hash,
                apply=True,
                dry_run=True,
            )
            self.notify(res.combined or "[dry-run] Save + Apply simulated")
            return

        overlay_hint = self.model.profile_name
        if self.model.profile_kind != "overlay" and overlay_hint and not overlay_hint.endswith("-local"):
            overlay_hint = f"{overlay_hint}-local"

        def _runner(cb):
            return self.backend.profile_mutate(
                adds,
                removes,
                profile=prof_arg,
                expected_hash=exp_hash,
                apply=True,
                on_line=cb,
            )

        def _done(ok: bool) -> None:
            if self.model.profile_kind == "builtin":
                self.target_profile = None
            self._reload_all_panes()
            if ok:
                self.notify("Profile saved and applied.")

        self.push_screen(
            ApplyProgressModal(
                "Save + Apply Desired State",
                _runner,
                failure_footer=(
                    "Desired state saved successfully.\n"
                    "Machine convergence failed.\n"
                    f"Your profile remains: {overlay_hint}\n"
                    "Retry: dots profile apply"
                ),
            ),
            _done,
        )

    def action_discard(self) -> None:
        if not self._on_main_screen():
            return
        if not self.model.has_unsaved_changes:
            self.notify("No unsaved changes to discard.")
            return
        self.model.discard()
        self.query_one("#software-pane", SoftwarePane).rebuild()
        self.query_one("#overview-pane", OverviewPane).refresh_view()
        self.notify("Pending changes discarded.")

    def action_refresh(self) -> None:
        if not self._on_main_screen():
            return
        if self.model.has_unsaved_changes:
            def _confirm(ok: bool) -> None:
                if ok:
                    self._reload_all_panes()
                    self.notify("Reloaded state from backend.")

            self.push_screen(
                ConfirmActionModal(
                    "Discard unsaved edits and refresh?",
                    f"You have pending edits ({self.model.pending_summary()}). Refreshing will discard them.",
                    confirm_label="Refresh",
                ),
                _confirm,
            )
            return
        self._reload_all_panes()
        self.notify("Refreshed state from backend.")

    def action_help_keys(self) -> None:
        if not self._on_main_screen():
            return
        self.push_screen(HelpKeysModal())

    def action_quit_confirm(self) -> None:
        if not self._on_main_screen():
            return
        if not self.model.has_unsaved_changes:
            self.exit()
            return

        def _done(choice: str) -> None:
            if choice == "save":
                if self._perform_save_only():
                    self.exit()
            elif choice == "discard":
                self.exit()

        self.push_screen(UnsavedChangesModal(self.model.pending_summary()), _done)


def run_lifecycle_tui(*, dry_run: bool = False, profile: str | None = None) -> int:
    DotsTuiApp(dry_run=dry_run, profile=profile).run()
    return 0
