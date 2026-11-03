"""Isolated Git worktrees for safe agent coding runs."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from dots_agent.config import AgentConfig, load_config


@dataclass
class WorktreeInfo:
    run_id: str
    path: Path
    base_commit: str
    branch: str
    primary_root: Path
    status: str  # active | completed | orphaned
    meta_path: Path

    def to_dict(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "path": str(self.path),
            "base_commit": self.base_commit,
            "branch": self.branch,
            "primary_root": str(self.primary_root),
            "status": self.status,
        }


def worktrees_root(cfg: AgentConfig | None = None) -> Path:
    cfg = cfg or load_config()
    rel = cfg.raw.get("paths", {}).get("worktrees_dir", "dots/agents/worktrees")
    xdg = os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state"))
    p = Path(xdg) / rel
    p.mkdir(parents=True, exist_ok=True)
    return p


def find_git_root(cwd: Path) -> Path | None:
    try:
        out = subprocess.check_output(
            ["git", "-C", str(cwd), "rev-parse", "--show-toplevel"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        return Path(out) if out else None
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def _git(cwd: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(cwd), *args],
        text=True,
        capture_output=True,
        check=check,
    )


def create_worktree(
    *,
    run_id: str,
    primary_cwd: Path,
    cfg: AgentConfig | None = None,
) -> WorktreeInfo:
    cfg = cfg or load_config()
    root = find_git_root(primary_cwd)
    if root is None:
        raise RuntimeError("not a git repository")
    base = _git(root, "rev-parse", "HEAD").stdout.strip()
    branch = f"dots/agent/{run_id}"
    path = worktrees_root(cfg) / run_id
    if path.exists():
        raise RuntimeError(f"worktree path already exists: {path}")
    # Detached-safe: create purpose branch from HEAD without touching user's branch
    _git(root, "worktree", "add", "-b", branch, str(path), base)
    meta = path / ".dots-agent-worktree.json"
    info = WorktreeInfo(
        run_id=run_id,
        path=path,
        base_commit=base,
        branch=branch,
        primary_root=root,
        status="active",
        meta_path=meta,
    )
    meta.write_text(
        json.dumps(
            {
                **info.to_dict(),
                "created_at": datetime.now(timezone.utc).isoformat(),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return info


def load_meta(run_id: str, cfg: AgentConfig | None = None) -> WorktreeInfo | None:
    cfg = cfg or load_config()
    meta = worktrees_root(cfg) / run_id / ".dots-agent-worktree.json"
    # Also check registry sidecar if worktree removed
    registry = worktrees_root(cfg) / f"{run_id}.json"
    path = meta if meta.is_file() else registry
    if not path.is_file():
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    wt_path = Path(data["path"])
    status = data.get("status") or "active"
    if not wt_path.is_dir() and status == "active":
        status = "orphaned"
    return WorktreeInfo(
        run_id=data["run_id"],
        path=wt_path,
        base_commit=data["base_commit"],
        branch=data["branch"],
        primary_root=Path(data["primary_root"]),
        status=status,
        meta_path=path,
    )


def mark_completed(info: WorktreeInfo) -> None:
    data = json.loads(info.meta_path.read_text(encoding="utf-8"))
    data["status"] = "completed"
    data["completed_at"] = datetime.now(timezone.utc).isoformat()
    info.meta_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    # Persist registry copy outside worktree for recovery if path deleted oddly
    reg = info.meta_path.parent.parent / f"{info.run_id}.json"
    reg.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    info.status = "completed"


def list_worktrees(cfg: AgentConfig | None = None) -> list[WorktreeInfo]:
    cfg = cfg or load_config()
    root = worktrees_root(cfg)
    found: dict[str, WorktreeInfo] = {}
    for child in sorted(root.iterdir()):
        if child.is_dir() and (child / ".dots-agent-worktree.json").is_file():
            info = load_meta(child.name, cfg)
            if info:
                found[info.run_id] = info
        elif child.suffix == ".json" and child.name.endswith(".json"):
            rid = child.stem
            if rid not in found:
                info = load_meta(rid, cfg)
                if info:
                    found[rid] = info
    return list(found.values())


def files_changed(info: WorktreeInfo) -> list[str]:
    if not info.path.is_dir():
        return []
    try:
        out = _git(
            info.path, "diff", "--name-only", f"{info.base_commit}...HEAD"
        ).stdout
        tracked = [ln for ln in out.splitlines() if ln.strip()]
        # Also unstaged/untracked relative to base
        status = _git(info.path, "status", "--porcelain").stdout
        for ln in status.splitlines():
            path = ln[3:].strip()
            if path and path not in tracked:
                tracked.append(path)
        return tracked
    except subprocess.CalledProcessError:
        return []


def diff_text(info: WorktreeInfo) -> str:
    if not info.path.is_dir():
        return f"(worktree missing: {info.path})\n"
    try:
        # Include uncommitted changes
        _git(info.path, "add", "-A", check=False)
        committed = _git(
            info.path, "diff", "--binary", f"{info.base_commit}...HEAD", check=False
        ).stdout
        unstaged = _git(info.path, "diff", "--binary", "--cached", check=False).stdout
        # Prefer working tree vs base
        full = _git(
            info.path, "diff", "--binary", info.base_commit, check=False
        ).stdout
        return full or committed or unstaged or "(no changes)\n"
    except subprocess.CalledProcessError as exc:
        return f"(diff failed: {exc})\n"


def primary_is_clean(primary_root: Path) -> bool:
    out = _git(primary_root, "status", "--porcelain").stdout.strip()
    return out == ""


def commit_worktree_if_needed(info: WorktreeInfo) -> str | None:
    """Create an agent commit in the worktree; return commit sha or None if clean."""
    _git(info.path, "add", "-A", check=False)
    porcelain = _git(info.path, "status", "--porcelain").stdout.strip()
    if not porcelain:
        # Maybe already committed ahead of base
        ahead = _git(
            info.path, "rev-list", "--count", f"{info.base_commit}..HEAD"
        ).stdout.strip()
        if ahead != "0":
            return _git(info.path, "rev-parse", "HEAD").stdout.strip()
        return None
    _git(
        info.path,
        "-c",
        "user.email=dots-agent@localhost",
        "-c",
        "user.name=DOTS Agent",
        "commit",
        "-m",
        f"dots agent run {info.run_id}",
        check=True,
    )
    return _git(info.path, "rev-parse", "HEAD").stdout.strip()


def apply_to_primary(info: WorktreeInfo) -> dict[str, Any]:
    """Cherry-pick agent commit(s) onto primary checkout. Refuses dirty target."""
    if not info.path.is_dir():
        return {"ok": False, "error": f"worktree missing: {info.path}"}
    if not primary_is_clean(info.primary_root):
        return {
            "ok": False,
            "error": "primary checkout is dirty — commit/stash first, then re-run apply",
        }
    sha = commit_worktree_if_needed(info)
    if sha is None:
        return {"ok": True, "applied": False, "detail": "no changes to apply"}
    # Cherry-pick range base..HEAD
    commits = _git(
        info.path, "rev-list", "--reverse", f"{info.base_commit}..HEAD"
    ).stdout.splitlines()
    if not commits:
        return {"ok": True, "applied": False, "detail": "no commits ahead of base"}
    for c in commits:
        try:
            _git(info.primary_root, "cherry-pick", c)
        except subprocess.CalledProcessError as exc:
            _git(info.primary_root, "cherry-pick", "--abort", check=False)
            return {
                "ok": False,
                "error": f"cherry-pick failed for {c}: {exc.stderr}",
            }
    return {"ok": True, "applied": True, "commits": commits}


def discard_worktree(info: WorktreeInfo) -> dict[str, Any]:
    """Remove worktree and local agent branch. Never auto-called."""
    root = info.primary_root
    reg = worktrees_root() / f"{info.run_id}.json"
    # Snapshot meta before removing the worktree directory
    data = info.to_dict()
    if info.meta_path.is_file():
        try:
            data = json.loads(info.meta_path.read_text(encoding="utf-8"))
        except Exception:
            pass
    elif reg.is_file():
        try:
            data = json.loads(reg.read_text(encoding="utf-8"))
        except Exception:
            pass
    data["status"] = "discarded"
    data["discarded_at"] = datetime.now(timezone.utc).isoformat()
    reg.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    if info.path.is_dir():
        try:
            _git(root, "worktree", "remove", "--force", str(info.path))
        except subprocess.CalledProcessError:
            # Fallback: unregister + rmtree
            _git(root, "worktree", "prune", check=False)
            shutil.rmtree(info.path, ignore_errors=True)
    # Delete branch if exists
    _git(root, "branch", "-D", info.branch, check=False)
    return {"ok": True, "discarded": info.run_id}
