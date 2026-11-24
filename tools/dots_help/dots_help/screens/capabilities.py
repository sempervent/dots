"""Agent capability browser. Reads the structured capability API; it does not scan registries itself."""

from __future__ import annotations

import json
import os
import subprocess

from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical
from textual.widgets import Button, Input, Static

from dots_help.registry import dots_root


class CapabilitiesPane(Vertical):
    """Stage skill and MCP desired-state edits, then save them in one profile mutate."""

    def __init__(self, **kwargs) -> None:
        super().__init__(**kwargs)
        self.inventory: dict = {}
        self.view = "all"
        self.staged: list[tuple[str, str, str]] = []
        self.preview = ""

    def compose(self) -> ComposeResult:
        yield Static("Agent Capabilities", id="cap-title")
        with Horizontal(id="cap-filters"):
            yield Button("Skills", id="cap-view-skills")
            yield Button("MCP", id="cap-view-mcp")
            yield Button("Clients", id="cap-view-clients")
            yield Button("All", id="cap-view-all")
            yield Button("Problems", id="cap-view-problems")
            yield Button("Updates", id="cap-view-updates")
        yield Input(placeholder="skill or mcp id", id="cap-id")
        with Horizontal(id="cap-actions"):
            yield Button("Enable", id="cap-enable")
            yield Button("Disable", id="cap-disable")
            yield Button("Preview", id="cap-preview")
            yield Button("Save", id="cap-save")
            yield Button("Cancel", id="cap-cancel")
        yield Static("Loading capability registry…", id="cap-summary")
        yield Static("", id="cap-detail")

    def on_mount(self) -> None:
        self.reload()

    def reload(self) -> None:
        root = dots_root()
        env = os.environ.copy()
        env["DOTS_DIR"] = str(root)
        env["PYTHONPATH"] = str(root / "tools" / "dots_agent")
        proc = subprocess.run(
            ["python3", "-m", "dots_agent.capabilities", "capabilities", "--json"],
            cwd=str(root),
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            self.query_one("#cap-summary", Static).update(proc.stderr.strip() or "capability inventory failed")
            return
        self.inventory = json.loads(proc.stdout)
        self._paint()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        button = event.button.id or ""
        if button.startswith("cap-view-"):
            self.view = button.removeprefix("cap-view-")
            self._paint()
            return
        if button == "cap-enable":
            self._stage("add")
        elif button == "cap-disable":
            self._stage("remove")
        elif button == "cap-preview":
            self.preview = self._preview_text()
            self._paint()
        elif button == "cap-cancel":
            self.staged.clear()
            self.preview = ""
            self._paint()
        elif button == "cap-save":
            self._save()

    def _selected(self) -> tuple[str, str]:
        raw = self.query_one("#cap-id", Input).value.strip()
        if not raw:
            return "", ""
        if self.view == "mcp" or raw.startswith("mcp:"):
            return "mcp", raw.removeprefix("mcp:")
        return "skill", raw.removeprefix("skill:")

    def _stage(self, action: str) -> None:
        kind, ident = self._selected()
        if not ident:
            return
        self.staged = [row for row in self.staged if not (row[0] == kind and row[1] == ident)]
        self.staged.append((kind, ident, action))
        self.preview = ""
        self._paint()

    def _preview_text(self) -> str:
        lines = ["Profile change preview", ""]
        for kind, ident, action in self.staged:
            mark = "+" if action == "add" else "-"
            lines.append(f"{kind.title()}:")
            lines.append(f"  {mark} {ident}")
            if kind == "mcp":
                row = next((item for item in self.inventory.get("mcp") or [] if item.get("id") == ident), None)
                perms = (row or {}).get("permissions") or {}
                if perms.get("remote_write") or perms.get("filesystem_write") or perms.get("shell"):
                    lines.append("Warnings:")
                    lines.append(f"  {ident} can write or run outside a read-only boundary.")
                auth = ((row or {}).get("auth") or {}).get("mode")
                if auth and auth != "none":
                    lines.append(f"  {ident} authentication required. DOTS will not start a login.")
        runtime = (self.inventory.get("runtime") or [{}])[0]
        lines.append("")
        lines.append(f"Runtime: Node {runtime.get('resolved') or 'unresolved'}")
        return "\n".join(lines)

    def _save(self) -> None:
        if not self.staged:
            return
        app = self.app
        dry = bool(getattr(app, "dry_run", True))
        if dry:
            self.preview = self._preview_text() + "\n\nSave stays staged in dry-run. No profile was written."
            self._paint()
            return
        args = ["profile", "mutate", "--yes", "--preserve-active"]
        for kind, ident, action in self.staged:
            flag = "--add-skill" if kind == "skill" and action == "add" else ""
            if kind == "skill" and action == "remove":
                flag = "--remove-skill"
            if kind == "mcp" and action == "add":
                flag = "--add-mcp"
            if kind == "mcp" and action == "remove":
                flag = "--remove-mcp"
            args.extend([flag, ident])
        result = app.backend.run_args(args)  # type: ignore[attr-defined]
        self.preview = result.combined or "saved"
        if result.ok:
            self.staged.clear()
        self._paint()

    def _paint(self) -> None:
        summary = self.inventory.get("summary") or {}
        skills = summary.get("skills") or {}
        mcp = summary.get("mcp") or {}
        trust = summary.get("trust") or {}
        header = [
            "Agent Capabilities",
            "",
            "Skills",
            f"  {skills.get('desired', 0)} desired",
            f"  {skills.get('installed', 0)} installed",
            f"  {skills.get('updates', 0)} updates",
            "",
            "MCP",
            f"  {mcp.get('desired', 0)} desired",
            f"  {mcp.get('healthy', 0)} healthy",
            f"  {mcp.get('auth_needed', 0)} auth required",
            "",
            "Clients",
        ]
        for client in self.inventory.get("clients") or []:
            label = "ready" if client.get("installed") else "available"
            header.append(f"  {client.get('id')}  {label}")
        header.extend(["", "Trust", f"  {trust.get('errors', 0)} errors", f"  {trust.get('advisories', 0)} advisories"])
        self.query_one("#cap-summary", Static).update("\n".join(header))
        self.query_one("#cap-detail", Static).update(self._detail())

    def _detail(self) -> str:
        if self.preview:
            return self.preview
        view = self.view
        lines: list[str] = []
        if view in {"skills", "all", "problems", "updates"}:
            for row in self.inventory.get("skills") or []:
                if view == "problems" and row.get("status") in {"REVIEWED", "UNREVIEWED"} and row.get("healthy", True):
                    continue
                if view == "updates" and row.get("status") != "UPDATE_AVAILABLE":
                    continue
                if view == "skills" or view == "all" or view in {"problems", "updates"}:
                    lines.append(f"{row.get('name')}  {row.get('status')}  desired={row.get('desired')}")
        if view in {"mcp", "all", "problems"}:
            for row in self.inventory.get("mcp") or []:
                perms = row.get("permissions") or {}
                if view == "problems" and row.get("safe_mode"):
                    continue
                lines.append(
                    f"{row.get('id')}  network={perms.get('network')} remote_write={perms.get('remote_write')} "
                    f"shell={perms.get('shell')} auth={((row.get('auth') or {}).get('mode'))}"
                )
        if view == "clients":
            for row in self.inventory.get("clients") or []:
                lines.append(f"{row.get('id')}  mcp={row.get('mcp_mode')} skills={row.get('skills_mode')}")
        if self.staged:
            lines.append("")
            lines.append("Staged (not saved):")
            for kind, ident, action in self.staged:
                lines.append(f"  {action} {kind}:{ident}")
        return "\n".join(lines) or "No rows for this view."
