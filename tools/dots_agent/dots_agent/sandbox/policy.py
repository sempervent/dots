"""DOTS-managed Pi sandbox.json policy (structured merge; fail-closed safe mode).

Schema follows current pi-sandbox (verified 0.7.3):
  ~/.pi/agent/sandbox.json  and/or  <project>/.pi/sandbox.json

Precedence (pi-sandbox):
  Read: allowRead/allowWrite grant; denyRead is default-deny marker (promptable)
  Write: denyWrite hard-blocks and overrides allowWrite; allowWrite also grants read

Linux note: glob patterns in allowWrite/denyWrite are NOT enforced for bash
(bubblewrap); use concrete secret directories + direct-tool denies.
"""

from __future__ import annotations

import json
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from dots_agent.config import AgentConfig, load_config


SECRET_DENY_PATHS: tuple[str, ...] = (
    "~/.ssh",
    "~/.aws",
    "~/.gnupg",
    "~/.kube",
    "~/.docker",
    "~/.config/gcloud",
    "~/.config/gh",
    "~/.config/dots/secrets",
    "~/.npmrc",
    "~/.pypirc",
    "~/.netrc",
)

# Direct-tool globs (honored by Pi read/write/edit on all platforms).
# Bash on Linux cannot enforce these globs — rely on directory denies above.
SECRET_DENY_GLOBS: tuple[str, ...] = (
    ".env",
    ".env.*",
    "*.pem",
    "*.key",
    "*.p12",
    "*.pfx",
    "id_rsa",
    "id_ed25519",
    "id_ecdsa",
    "hosts.yml",
)


def secret_deny_globs() -> list[str]:
    return list(SECRET_DENY_GLOBS)


def _expand(p: str) -> str:
    return str(Path(p).expanduser())


def _backup(path: Path) -> Path | None:
    if not path.is_file():
        return None
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    bak = path.with_suffix(path.suffix + f".bak-{stamp}")
    shutil.copy2(path, bak)
    return bak


def _deep_merge_arrays(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    """Merge objects; concatenate+dedupe list fields under network/filesystem."""
    out = dict(base)
    for k, v in overlay.items():
        if k in ("network", "filesystem") and isinstance(v, dict):
            cur = dict(out.get(k) or {}) if isinstance(out.get(k), dict) else {}
            for sk, sv in v.items():
                if isinstance(sv, list) and isinstance(cur.get(sk), list):
                    seen: list[Any] = []
                    for item in list(cur[sk]) + list(sv):
                        if item not in seen:
                            seen.append(item)
                    cur[sk] = seen
                else:
                    cur[sk] = sv
            out[k] = cur
        else:
            out[k] = v
    return out


def dots_managed_global_policy(cfg: AgentConfig | None = None) -> dict[str, Any]:
    """Conservative global policy DOTS maintains (never grants $HOME broadly)."""
    cfg = cfg or load_config()
    sandbox = cfg.raw.get("sandbox") or {}
    timeout = int(
        cfg.raw.get("agent", {}).get("permission_prompt_timeout_seconds", 5)
    )
    domains = list(
        sandbox.get("bash_allowed_domains")
        or ["localhost", "127.0.0.1"]
    )
    home = str(Path.home())
    deny_read = [
        home,  # broad home — punch holes only via allowRead for specific needs
        _expand("~/.ssh"),
        _expand("~/.aws"),
        _expand("~/.gnupg"),
        _expand("~/.kube"),
        _expand("~/.docker"),
        _expand("~/.config/gcloud"),
        _expand("~/.config/gh"),
        _expand("~/.config/dots"),
        _expand("~/.local/state/dots"),
    ]
    # allowRead: cwd + minimal tool paths — NOT whole ~/.config / ~/.local
    allow_read = [
        ".",
        "/tmp",
        "/var/tmp",
        _expand("~/.pi/agent"),  # Pi needs its own agent dir
    ]
    allow_write = [
        ".",
        "/tmp",
        "/var/tmp",
    ]
    deny_write = list(SECRET_DENY_GLOBS) + [
        _expand("~/.config/dots"),
        _expand("~/.local/state/dots"),
        _expand("~/.pi/agent/sandbox.json"),
        _expand("~/.pi/agent/mcp.json"),
        _expand("~/.pi/agent/settings.json"),
    ]
    return {
        "enabled": True,
        "sandboxUserShell": True,
        "enableAccessRequestTool": bool(
            sandbox.get("enable_access_request_tool", False)
        ),
        "permissionPromptTimeoutSeconds": timeout,
        "allowBrowserProcess": False,
        "network": {
            "disabled": False,
            "allowLocalBinding": True,
            "allowAllUnixSockets": False,
            "allowUnauthenticatedSocksProxy": False,
            "allowSSHAgentSocket": False,
            "allowedDomains": domains,
            "deniedDomains": [],
        },
        "filesystem": {
            "denyRead": deny_read,
            "allowRead": allow_read,
            "allowWrite": allow_write,
            "denyWrite": deny_write,
        },
        # Marker so merges can identify DOTS-managed keys without wiping user extras
        "_dots_managed": True,
        "_dots_policy_version": 2,
    }


def build_run_sandbox_policy(
    *,
    worktree_path: Path | None,
    run_tmp: Path,
    cfg: AgentConfig | None = None,
    interactive: bool = False,
) -> dict[str, Any]:
    """Project-local policy for one run. Not committed to user history."""
    cfg = cfg or load_config()
    base = dots_managed_global_policy(cfg)
    timeout = int(
        cfg.raw.get("agent", {}).get("permission_prompt_timeout_seconds", 5)
    )
    if not interactive:
        # Fail closed quickly on permission prompts in noninteractive harness.
        base["permissionPromptTimeoutSeconds"] = max(1, timeout)
        base["enableAccessRequestTool"] = False
    else:
        base["permissionPromptTimeoutSeconds"] = max(timeout, 30)

    cwd = str(worktree_path.resolve()) if worktree_path else "."
    fs = dict(base["filesystem"])
    # Restrict writes to this worktree + run tmp only.
    fs["allowWrite"] = [cwd, str(run_tmp.resolve()), "/tmp", "/var/tmp"]
    fs["allowRead"] = [
        cwd,
        str(run_tmp.resolve()),
        "/tmp",
        "/var/tmp",
        _expand("~/.pi/agent"),
    ]
    # Hard-deny secrets even inside worktree via globs + absolute dirs
    fs["denyWrite"] = list(dict.fromkeys(list(fs.get("denyWrite") or []) + list(SECRET_DENY_GLOBS)))
    fs["denyRead"] = list(
        dict.fromkeys(
            list(fs.get("denyRead") or [])
            + [_expand(p) for p in SECRET_DENY_PATHS]
            + [
                _expand("~/.config/dots"),
                _expand("~/.local/state/dots"),
            ]
        )
    )
    base["filesystem"] = fs
    base["enabled"] = True
    return base


def write_project_sandbox_policy(
    project_root: Path, policy: dict[str, Any]
) -> Path:
    """Write <project>/.pi/sandbox.json and exclude from git tracking."""
    pi_dir = project_root / ".pi"
    pi_dir.mkdir(parents=True, exist_ok=True)
    path = pi_dir / "sandbox.json"
    # Strip internal markers before write if desired — keep for diagnostics
    clean = {k: v for k, v in policy.items() if not str(k).startswith("_dots")}
    # Keep markers in a nested key that Pi ignores? Safer strip markers.
    path.write_text(json.dumps(clean, indent=2) + "\n", encoding="utf-8")
    path.chmod(0o600)
    _ensure_git_exclude(project_root, ".pi/")
    return path


def _ensure_git_exclude(repo: Path, pattern: str) -> None:
    git_dir = repo / ".git"
    if git_dir.is_file():
        # worktree: .git is a file pointing at main gitdir
        try:
            text = git_dir.read_text(encoding="utf-8")
            for line in text.splitlines():
                if line.startswith("gitdir:"):
                    git_dir = Path(line.split(":", 1)[1].strip())
                    break
        except OSError:
            return
    if not git_dir.is_dir():
        return
    exclude = git_dir / "info" / "exclude"
    exclude.parent.mkdir(parents=True, exist_ok=True)
    existing = exclude.read_text(encoding="utf-8") if exclude.is_file() else ""
    if pattern not in existing.splitlines():
        with exclude.open("a", encoding="utf-8") as fh:
            if existing and not existing.endswith("\n"):
                fh.write("\n")
            fh.write(f"# DOTS agent sandbox (untracked)\n{pattern}\n")


def global_sandbox_path() -> Path:
    return Path.home() / ".pi" / "agent" / "sandbox.json"


def merge_global_sandbox_policy(cfg: AgentConfig | None = None) -> dict[str, Any]:
    """Structured merge into ~/.pi/agent/sandbox.json without wiping unrelated keys."""
    cfg = cfg or load_config()
    path = global_sandbox_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    desired = dots_managed_global_policy(cfg)
    # Strip markers for on-disk Pi config
    desired_clean = {k: v for k, v in desired.items() if not str(k).startswith("_dots")}

    existing: dict[str, Any] = {}
    if path.is_file():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                existing = loaded
        except (json.JSONDecodeError, OSError):
            _backup(path)
            existing = {}

    # Preserve user network/filesystem extras by merging arrays
    merged = _deep_merge_arrays(existing, desired_clean)
    # Force critical safety scalars from DOTS
    merged["enabled"] = True
    merged["allowBrowserProcess"] = False
    # Ensure secret deny lists are present
    fs = merged.setdefault("filesystem", {})
    if not isinstance(fs, dict):
        fs = {}
        merged["filesystem"] = fs
    for key, extras in (
        ("denyWrite", list(SECRET_DENY_GLOBS)),
        (
            "denyRead",
            [_expand(p) for p in SECRET_DENY_PATHS]
            + [_expand("~/.config/dots"), _expand("~/.local/state/dots")],
        ),
    ):
        cur = list(fs.get(key) or [])
        for item in extras:
            if item not in cur:
                cur.append(item)
        fs[key] = cur

    changed = merged != existing
    if changed:
        _backup(path)
        path.write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")
        path.chmod(0o600)
    return {"ok": True, "changed": changed, "path": str(path)}


def path_is_secret(path: str | Path) -> bool:
    """Heuristic used by unit tests / doctor — not a substitute for OS policy."""
    p = Path(path).expanduser()
    name = p.name
    if name in SECRET_DENY_GLOBS or name.startswith(".env"):
        return True
    for pat in ("*.pem", "*.key", "*.p12", "*.pfx"):
        if name.endswith(pat[1:]):
            return True
    resolved = str(p.resolve()) if p.exists() else str(p)
    for secret in SECRET_DENY_PATHS:
        root = str(Path(secret).expanduser())
        if resolved == root or resolved.startswith(root + os.sep):
            return True
    if name in ("id_rsa", "id_ed25519", "id_ecdsa"):
        return True
    return False
