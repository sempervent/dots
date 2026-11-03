"""Selective Pi seat configuration projection (never symlink ~/.pi/agent)."""

from __future__ import annotations

import json
import os
import shutil
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any

from dots_agent.config import AgentConfig, load_config
from dots_agent.mcp_trust import write_safe_mcp_json
from dots_agent.openrig.roles import RolePolicy, load_roles
from dots_agent.pi_models import models_json_path
from dots_agent.providers import detect_local
from dots_agent.sandbox.policy import SECRET_DENY_PATHS, secret_deny_globs


class SeatRole(str, Enum):
    LEAD = "lead"
    BUILDER = "builder"
    REVIEWER = "reviewer"
    INVESTIGATOR = "investigator"


def openrig_home() -> Path:
    return Path(os.environ.get("OPENRIG_HOME", str(Path.home() / ".openrig"))).expanduser()


def seat_session_name(*, pod_id: str, member_id: str, rig_name: str) -> str:
    """OpenRig canonical session: {podId}-{memberId}@{rigName}."""
    return f"{pod_id}-{member_id}@{rig_name}"


def pi_seat_agent_dir(session_name: str, *, home: Path | None = None) -> Path:
    """$OPENRIG_HOME/state/pi/<session>/agent — OpenRig creates this; we populate selectively."""
    root = home or openrig_home()
    return root / "state" / "pi" / session_name / "agent"


def _sandbox_for_role(
    role: RolePolicy,
    *,
    worktree: Path | None,
    project: Path,
) -> dict[str, Any]:
    """Role-specific sandbox.json — reviewer/investigator are write-denied."""
    allow_read = [str(project), str(Path.home() / ".pi")]
    if worktree is not None:
        allow_read.append(str(worktree))
    allow_write: list[str] = []
    deny_write: list[str] = list(SECRET_DENY_PATHS)
    if role.sandbox == "worktree_rw" and role.write and worktree is not None:
        allow_write.append(str(worktree))
    elif role.sandbox == "read_mostly":
        # Lead may write team notes under worktree/.dots if present
        if worktree is not None:
            allow_write.append(str(worktree / ".dots"))
    else:
        # read_only / reviewer / investigator: deny project and worktree writes
        deny_write.extend([str(project), str(worktree)] if worktree else [str(project)])

    return {
        "network": {
            "allowedDomains": ["localhost", "127.0.0.1"],
        },
        "filesystem": {
            "allowRead": allow_read,
            "allowWrite": allow_write,
            "denyWrite": deny_write,
            "denyRead": [],
            "denyGlobs": secret_deny_globs(),
        },
        "dots": {
            "role": role.name,
            "sandbox_profile": role.sandbox,
            "write_allowed": bool(role.write and role.sandbox == "worktree_rw"),
        },
    }


def provision_pi_seat(
    *,
    rig_name: str,
    pod_id: str = "team",
    member_id: str,
    role: str | SeatRole,
    project: Path,
    worktree: Path | None = None,
    cfg: AgentConfig | None = None,
    openrig_home_path: Path | None = None,
    models_source: Path | None = None,
    force: bool = False,
) -> dict[str, Any]:
    """Populate an isolated OpenRig Pi seat agent dir with DOTS policy only.

    Does NOT copy user history, unrelated MCP servers, or secrets.
    Does NOT symlink ~/.pi/agent.
    """
    cfg = cfg or load_config()
    roles, _ = load_roles(cfg.root / "configs" / "agents" / "openrig" / "roles.toml")
    role_name = role.value if isinstance(role, SeatRole) else str(role)
    policy = roles.get(role_name)
    if policy is None:
        raise ValueError(f"unknown role: {role_name}")

    session = seat_session_name(pod_id=pod_id, member_id=member_id, rig_name=rig_name)
    agent_dir = pi_seat_agent_dir(session, home=openrig_home_path)
    if agent_dir.exists() and any(agent_dir.iterdir()) and not force:
        # Reconcile safe files only — do not wipe sessions/conversations
        pass
    agent_dir.mkdir(parents=True, exist_ok=True)

    # models.json — copy DOTS-managed provider defs only (never session history)
    models_path = agent_dir / "models.json"
    src_models = models_source or models_json_path()
    if src_models.is_file():
        # Copy models.json only — not settings/history/sessions from ~/.pi/agent
        shutil.copy2(src_models, models_path)
    else:
        local = detect_local(cfg)
        from dots_agent.pi_models import llamacpp_provider_entry, ollama_provider_entry

        providers: dict[str, Any] = {}
        if local.healthy and local.name == "ollama" and local.model:
            providers["ollama"] = ollama_provider_entry(
                local.model, base_url=local.base_url or "http://127.0.0.1:11434/v1"
            )
        elif local.healthy and local.name == "llamacpp":
            providers["llamacpp"] = llamacpp_provider_entry(
                local.model or "local",
                base_url=local.base_url or "http://127.0.0.1:8080/v1",
            )
        models_path.write_text(
            json.dumps({"providers": providers}, indent=2) + "\n", encoding="utf-8"
        )

    # MCP — safe allowlist only
    which_scout = shutil.which("dots-model-scout") or str(
        cfg.root / "scripts" / "dots-model-scout"
    )
    which_expert = shutil.which("dots-expert") or str(cfg.root / "scripts" / "dots-expert")
    mcp_servers = list(policy.mcp) or ["dots-model-scout", "dots-expert"]
    # Always write only the trusted pair (Phase 2 boundary); role may subset later
    write_safe_mcp_json(
        agent_dir / "mcp.json",
        scout_command=which_scout,
        expert_command=which_expert,
        scout_env={},
        expert_env={},
    )

    # sandbox.json — role-enforced
    sandbox = _sandbox_for_role(policy, worktree=worktree, project=project.resolve())
    (agent_dir / "sandbox.json").write_text(
        json.dumps(sandbox, indent=2) + "\n", encoding="utf-8"
    )

    # Role prompt (DOTS-managed) — not full user Pi settings
    role_md = (
        cfg.root
        / "configs"
        / "agents"
        / "openrig"
        / "agents"
        / role_name
        / "guidance"
        / "role.md"
    )
    if role_md.is_file():
        (agent_dir / "DOTS_ROLE.md").write_text(
            role_md.read_text(encoding="utf-8"), encoding="utf-8"
        )

    meta = {
        "schema_version": 1,
        "rig": rig_name,
        "session": session,
        "role": role_name,
        "task_class": policy.task_class,
        "quality": policy.quality,
        "sandbox": policy.sandbox,
        "write": policy.write,
        "mcp": mcp_servers,
        "agent_dir": str(agent_dir),
        "user_pi_agent_symlinked": False,
        "history_copied": False,
        "unrelated_mcp_copied": False,
        "project": str(project.resolve()),
        "worktree": str(worktree.resolve()) if worktree else None,
    }
    (agent_dir / "dots-seat.json").write_text(
        json.dumps(meta, indent=2) + "\n", encoding="utf-8"
    )
    return meta


def assert_seat_isolation(agent_dir: Path) -> dict[str, bool]:
    """Test helpers — verify projection hygiene."""
    user_pi = Path.home() / ".pi" / "agent"
    checks = {
        "agent_dir_exists": agent_dir.is_dir(),
        "not_user_pi_symlink": not (
            agent_dir.is_symlink() and agent_dir.resolve() == user_pi.resolve()
        ),
        "has_mcp": (agent_dir / "mcp.json").is_file(),
        "has_sandbox": (agent_dir / "sandbox.json").is_file(),
        "no_sessions_from_user": not (agent_dir / "sessions").is_dir()
        or not any((agent_dir / "sessions").glob("*")),
    }
    if (agent_dir / "mcp.json").is_file():
        data = json.loads((agent_dir / "mcp.json").read_text(encoding="utf-8"))
        servers = set((data.get("mcpServers") or {}).keys())
        checks["only_safe_mcp"] = servers <= {"dots-model-scout", "dots-expert"}
    return checks
