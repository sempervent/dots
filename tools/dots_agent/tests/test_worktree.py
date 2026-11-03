"""Git worktree isolation tests."""

from __future__ import annotations

import subprocess
from pathlib import Path

from dots_agent.worktree import (
    apply_to_primary,
    create_worktree,
    discard_worktree,
    files_changed,
    list_worktrees,
    load_meta,
    primary_is_clean,
)


def _git(cwd: Path, *args: str) -> None:
    subprocess.check_call(["git", "-C", str(cwd), *args], stdout=subprocess.DEVNULL)


def _init_repo(path: Path) -> None:
    path.mkdir(parents=True)
    _git(path, "init")
    _git(path, "config", "user.email", "test@example.com")
    _git(path, "config", "user.name", "Test")
    (path / "README.md").write_text("hello\n")
    _git(path, "add", "README.md")
    _git(path, "commit", "-m", "init")


def test_worktree_lifecycle(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    primary = tmp_path / "primary"
    _init_repo(primary)
    info = create_worktree(run_id="run1", primary_cwd=primary)
    assert info.path.is_dir()
    assert primary_is_clean(primary)
    # Modify worktree only
    (info.path / "NEW.txt").write_text("agent change\n")
    # Primary unchanged
    assert not (primary / "NEW.txt").exists()
    assert "NEW.txt" in files_changed(info)
    # Dirty target blocks apply
    (primary / "dirty.txt").write_text("x")
    blocked = apply_to_primary(info)
    assert blocked["ok"] is False
    (primary / "dirty.txt").unlink()
    _git(primary, "checkout", "--", ".")
    # Apply
    result = apply_to_primary(info)
    assert result["ok"] is True
    assert (primary / "NEW.txt").read_text() == "agent change\n"
    # Discard
    listed = list_worktrees()
    assert any(x.run_id == "run1" for x in listed)
    discard = discard_worktree(info)
    assert discard["ok"]
    assert load_meta("run1") is not None  # registry may remain as discarded
