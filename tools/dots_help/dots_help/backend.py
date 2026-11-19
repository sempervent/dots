"""Subprocess and structured JSON API client for the DOTS Bash backend.

All profile mutations, package-ownership resolution, planning, and upgrades
delegate to the authoritative `./dots` CLI and `helpers/profile_edit.sh`.
This module never uses `shell=True`, never writes profile TOML directly, and
never invokes `brew` / `apt` / `dnf` / `pacman` / `xbps` directly.
"""

from __future__ import annotations

import json
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from .registry import dots_root


class BackendError(RuntimeError):
    """Raised when a backend CLI call fails or returns malformed output."""


@dataclass
class CommandResult:
    returncode: int
    stdout: str
    stderr: str

    @property
    def ok(self) -> bool:
        return self.returncode == 0

    @property
    def combined(self) -> str:
        parts = [p for p in (self.stdout.strip(), self.stderr.strip()) if p]
        return "\n".join(parts)


class DotsBackend:
    """Thin, safe controller bridge over `./dots`."""

    def __init__(
        self,
        root: Path | None = None,
        dots_bin: Path | None = None,
        env_overrides: dict[str, str] | None = None,
    ) -> None:
        self.root = (root or dots_root()).resolve()
        self.dots_bin = (dots_bin or (self.root / "dots")).resolve()
        self.env_overrides = dict(env_overrides or {})

    def _env(self) -> dict[str, str]:
        env = os.environ.copy()
        env["DOTS_DIR"] = str(self.root)
        env["DOTS_UI_NONINTERACTIVE"] = "1"
        env["NO_COLOR"] = "1"
        env.update(self.env_overrides)
        return env

    def run_args(self, args: list[str], *, timeout: float = 60.0) -> CommandResult:
        cmd = [str(self.dots_bin), *args]
        proc = subprocess.run(
            cmd,
            cwd=str(self.root),
            env=self._env(),
            capture_output=True,
            text=True,
            timeout=timeout,
            shell=False,
            check=False,
        )
        return CommandResult(proc.returncode, proc.stdout or "", proc.stderr or "")

    def run_streaming(
        self,
        args: list[str],
        on_line: Callable[[str], None] | None = None,
        *,
        timeout: float = 600.0,
    ) -> CommandResult:
        cmd = [str(self.dots_bin), *args]
        proc = subprocess.Popen(
            cmd,
            cwd=str(self.root),
            env=self._env(),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            shell=False,
        )
        lines: list[str] = []
        assert proc.stdout is not None
        for line in proc.stdout:
            clean = line.rstrip("\n")
            lines.append(clean)
            if on_line is not None:
                on_line(clean)
        rc = proc.wait(timeout=timeout)
        return CommandResult(rc, "\n".join(lines), "")

    def _run_json(self, args: list[str], *, timeout: float = 60.0) -> dict[str, Any]:
        res = self.run_args(args, timeout=timeout)
        if not res.ok:
            raise BackendError(res.combined or f"Command failed ({res.returncode}): {' '.join(args)}")
        raw = res.stdout.strip()
        if not raw:
            raise BackendError(f"Empty JSON output from: {' '.join(args)}")
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise BackendError(f"Invalid JSON from {' '.join(args)}: {exc}") from exc
        if not isinstance(data, dict):
            raise BackendError(f"Expected JSON object from {' '.join(args)}")
        return data

    def profile_show(self, profile: str | None = None) -> dict[str, Any]:
        args = ["profile", "show", "--json"]
        if profile:
            args.extend(["--profile", profile])
        return self._run_json(args)

    def profile_list(self) -> list[dict[str, Any]]:
        data = self._run_json(["profile", "list", "--json"])
        return list(data.get("profiles") or [])

    def components_list(self, profile: str | None = None) -> dict[str, Any]:
        args = ["components", "list", "--json"]
        if profile:
            args.extend(["--profile", profile])
        return self._run_json(args)

    def package_groups(self, profile: str | None = None) -> dict[str, Any]:
        args = ["packages", "groups", "--json"]
        if profile:
            args.extend(["--profile", profile])
        return self._run_json(args)

    def resolve_selector(self, selector: str) -> dict[str, Any]:
        return self._run_json(["profile", "resolve", selector, "--json"])

    def profile_plan(
        self,
        adds: list[str],
        removes: list[str],
        *,
        profile: str | None = None,
    ) -> dict[str, Any]:
        args = ["profile", "plan", "--json"]
        if profile:
            args.extend(["--profile", profile])
        for a in adds:
            args.extend(["--add", a])
        for r in removes:
            args.extend(["--remove", r])
        return self._run_json(args)

    def profile_mutate(
        self,
        adds: list[str],
        removes: list[str],
        *,
        profile: str | None = None,
        expected_hash: str | None = None,
        apply: bool = False,
        dry_run: bool = False,
        on_line: Callable[[str], None] | None = None,
    ) -> CommandResult:
        args = ["profile", "mutate", "--yes"]
        if profile:
            args.extend(["--profile", profile])
        if expected_hash:
            args.extend(["--expected-hash", expected_hash])
        for a in adds:
            args.extend(["--add", a])
        for r in removes:
            args.extend(["--remove", r])
        if dry_run:
            args.append("--dry-run")
        if apply:
            args.append("--apply")
        if apply and not dry_run and on_line is not None:
            return self.run_streaming(args, on_line=on_line)
        return self.run_args(args, timeout=600.0 if apply else 60.0)

    def profile_switch(
        self,
        profile: str,
        *,
        apply: bool = False,
        dry_run: bool = False,
        on_line: Callable[[str], None] | None = None,
    ) -> CommandResult:
        args = ["profile", "switch", profile]
        if dry_run:
            args.append("--dry-run")
        if apply:
            args.append("--apply")
        if apply and not dry_run and on_line is not None:
            return self.run_streaming(args, on_line=on_line)
        return self.run_args(args, timeout=600.0 if apply else 60.0)

    def upgrade_preview(
        self,
        *,
        profile: str | None = None,
        include_all: bool = False,
    ) -> dict[str, Any]:
        args = ["upgrade", "--dry-run", "--json"]
        if profile:
            args.extend(["--profile", profile])
        if include_all:
            args.append("--all")
        return self._run_json(args, timeout=120.0)

    def upgrade_run(
        self,
        *,
        profile: str | None = None,
        include_all: bool = False,
        dry_run: bool = False,
        on_line: Callable[[str], None] | None = None,
    ) -> CommandResult:
        args = ["upgrade", "--yes"]
        if profile:
            args.extend(["--profile", profile])
        if include_all:
            args.append("--all")
        if dry_run:
            args.append("--dry-run")
        if not dry_run and on_line is not None:
            return self.run_streaming(args, on_line=on_line, timeout=600.0)
        return self.run_args(args, timeout=600.0)
