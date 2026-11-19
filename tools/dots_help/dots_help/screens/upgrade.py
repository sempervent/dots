"""Managed software upgrade pane (uses `dots upgrade --dry-run --json`)."""

from __future__ import annotations

from typing import Any

from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.widgets import Button, Label, Static

from ..model import DesiredStateModel
from .modals import AllUpgradeConfirmModal, ApplyProgressModal


class UpgradePane(Vertical):
    """Scoped Homebrew software upgrade UI (explicit refresh; never auto-runs --all)."""

    def __init__(self, model: DesiredStateModel, *, dry_run: bool = False, **kwargs) -> None:
        super().__init__(**kwargs)
        self.model = model
        self.dry_run = dry_run
        self._loaded_once = False
        self._last_preview: dict[str, Any] = {}

    def compose(self) -> ComposeResult:
        yield Label("Managed Software Upgrades (Homebrew desired scope)", classes="pane-title")
        with VerticalScroll(id="upgrade-scroll"):
            yield Static(
                "Click 'Check Outdated' or press r to query outdated packages.\n"
                "Note: dots upgrade updates managed Homebrew packages, NOT the DOTS repo (dots update).",
                id="upgrade-body",
            )
        with Horizontal(id="upgrade-actions"):
            yield Button("Check Outdated", id="btn-upg-check")
            yield Button("Upgrade Managed", id="btn-upg-managed", variant="primary")
            yield Button("Advanced: Upgrade All (--all)", id="btn-upg-all", variant="warning")

    def ensure_loaded(self) -> None:
        if not self._loaded_once:
            self.load_preview()

    def load_preview(self) -> None:
        self._loaded_once = True
        body = self.query_one("#upgrade-body", Static)
        try:
            data = self.model.backend.upgrade_preview(profile=self.model.profile_file or None)
        except Exception as exc:
            body.update(f"Unable to check outdated packages: {exc}")
            return
        self._last_preview = data
        self._render_preview(data)

    def _render_preview(self, data: dict[str, Any]) -> None:
        lines: list[str] = [
            f"Profile: {data.get('profile') or self.model.profile_name}",
            "",
        ]
        if not data.get("homebrew_available", True):
            lines.append(
                str(
                    data.get("note")
                    or "Homebrew/Linuxbrew unavailable; OS packages are not upgraded by dots upgrade."
                )
            )
            self.query_one("#upgrade-body", Static).update("\n".join(lines))
            return

        would = data.get("would_upgrade") or []
        excl = data.get("excluded") or []
        undec = data.get("undeclared") or []

        lines.append(f"Managed updates ({len(would)}):")
        if would:
            for item in would:
                lines.append(f"  {item.get('name')} ({item.get('kind')})")
        else:
            lines.append("  (none outdated in active profile)")

        lines.extend(["", f"Excluded from this profile ({len(excl)}):"])
        if excl:
            for item in excl[:20]:
                lines.append(f"  {item.get('name')} ({item.get('kind')})")
            if len(excl) > 20:
                lines.append(f"  ... (+{len(excl) - 20} more)")
        else:
            lines.append("  (none)")

        lines.extend(["", f"Undeclared ({len(undec)}):"])
        if undec:
            for item in undec[:20]:
                lines.append(f"  {item.get('name')} ({item.get('kind')})")
            if len(undec) > 20:
                lines.append(f"  ... (+{len(undec) - 20} more)")
        else:
            lines.append("  (none)")

        lines.extend([
            "",
            "DOTS never runs brew cleanup, brew bundle cleanup, or OS apt/dnf/pacman/xbps upgrades.",
        ])
        self.query_one("#upgrade-body", Static).update("\n".join(lines))

    def on_button_pressed(self, event: Button.Pressed) -> None:
        bid = event.button.id
        if bid == "btn-upg-check":
            self.load_preview()
        elif bid == "btn-upg-managed":
            self._run_upgrade(include_all=False)
        elif bid == "btn-upg-all":
            def _confirmed(ok: bool) -> None:
                if ok:
                    self._run_upgrade(include_all=True)

            self.app.push_screen(AllUpgradeConfirmModal(), _confirmed)

    def _run_upgrade(self, *, include_all: bool) -> None:
        if self.dry_run:
            res = self.model.backend.upgrade_run(
                profile=self.model.profile_file or None,
                include_all=include_all,
                dry_run=True,
            )
            self.app.notify(res.combined or "[dry-run] upgrade previewed")
            return

        label = "Upgrade All Homebrew (--all)" if include_all else "Upgrade Managed Software"

        def _runner(cb):
            return self.model.backend.upgrade_run(
                profile=self.model.profile_file or None,
                include_all=include_all,
                on_line=cb,
            )

        def _done(ok: bool) -> None:
            self.load_preview()
            if ok:
                self.app.notify("Upgrade finished.")

        self.app.push_screen(
            ApplyProgressModal(label, _runner, failure_footer="Some package upgrades failed; see log above."),
            _done,
        )
