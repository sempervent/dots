"""Safe-mode run orchestration: worktree + sandbox policy + isolated Pi env."""

from __future__ import annotations

import os
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from dots_agent.config import AgentConfig, load_config
from dots_agent.env import assert_pi_env_safe, expert_env, model_scout_env, pi_env
from dots_agent.mcp_trust import write_safe_mcp_json
from dots_agent.sandbox.policy import (
    build_run_sandbox_policy,
    write_project_sandbox_policy,
)
from dots_agent.sandbox.status import pi_sandbox_installed
from dots_agent.worktree import WorktreeInfo, create_worktree, find_git_root, mark_completed


SAFE = "safe"
IN_PLACE = "in_place"
UNSAFE_HOST = "unsafe_host"

UNSAFE_WARNING = (
    "WARNING: unrestricted agent execution\n"
    "Pi tools may read, modify, or execute anything available to this user."
)


@dataclass
class RunSession:
    run_id: str
    execution_mode: str
    cwd: Path  # agent working directory
    primary_cwd: Path
    worktree: WorktreeInfo | None
    runtime_home: Path
    pi_agent_dir: Path
    sandbox_enabled: bool
    network_policy: str
    mcp_servers: list[str]
    warnings: list[str]
    pi_env: dict[str, str]
    pi_extra_args: list[str]


def resolve_execution_mode(args_mode: str | None, *, unsafe: bool, in_place: bool) -> str:
    if unsafe:
        return UNSAFE_HOST
    if in_place:
        return IN_PLACE
    if args_mode in (SAFE, IN_PLACE, UNSAFE_HOST):
        return args_mode
    return SAFE


def prepare_run_session(
    *,
    run_id: str,
    primary_cwd: Path,
    execution_mode: str,
    cfg: AgentConfig | None = None,
    interactive: bool = False,
    harness_only: bool = False,
) -> RunSession:
    cfg = cfg or load_config()
    warnings: list[str] = []
    primary_cwd = primary_cwd.resolve()
    runtime_root = cfg.state_dir() / "runtime" / run_id
    runtime_home = runtime_root / "home"
    pi_agent_dir = runtime_root / "pi-agent"
    runtime_home.mkdir(parents=True, exist_ok=True)
    pi_agent_dir.mkdir(parents=True, exist_ok=True)
    run_tmp = runtime_root / "tmp"
    run_tmp.mkdir(parents=True, exist_ok=True)

    worktree: WorktreeInfo | None = None
    cwd = primary_cwd
    sandbox_enabled = execution_mode != UNSAFE_HOST

    if execution_mode == UNSAFE_HOST:
        warnings.append(UNSAFE_WARNING)
        env = pi_env(
            run_id=run_id,
            execution_mode=execution_mode,
            # Keep real HOME for unsafe; still scrub secrets
            agent_home=None,
            pi_agent_dir=None,
        )
        assert_pi_env_safe(env)
        return RunSession(
            run_id=run_id,
            execution_mode=execution_mode,
            cwd=cwd,
            primary_cwd=primary_cwd,
            worktree=None,
            runtime_home=runtime_home,
            pi_agent_dir=pi_agent_dir,
            sandbox_enabled=False,
            network_policy="unrestricted (host)",
            mcp_servers=["(user global MCP)"],
            warnings=warnings,
            pi_env=env,
            pi_extra_args=["--no-sandbox"],
        )

    # Fail closed: sandbox must be available
    installed, detail = pi_sandbox_installed()
    if not installed and not harness_only:
        raise RuntimeError(
            "Agent sandbox unavailable.\n\n"
            f"Detail: {detail}\n\n"
            "Run:\n"
            "  dots agent doctor\n\n"
            "To explicitly bypass:\n"
            "  dots agent run --unsafe-host ..."
        )

    if execution_mode == SAFE:
        git_root = find_git_root(primary_cwd)
        if git_root is not None:
            worktree = create_worktree(
                run_id=run_id, primary_cwd=primary_cwd, cfg=cfg
            )
            cwd = worktree.path
        else:
            warnings.append(
                "Git worktree isolation unavailable; sandbox only."
            )
            cwd = primary_cwd
    else:  # in_place
        cwd = primary_cwd
        warnings.append("in-place mode: sandbox on; writing to current checkout")

    # Project-local sandbox policy (live policy for this run)
    policy = build_run_sandbox_policy(
        worktree_path=cwd if cwd.is_dir() else None,
        run_tmp=run_tmp,
        cfg=cfg,
        interactive=interactive,
    )
    write_project_sandbox_policy(cwd, policy)

    # Also place a copy under PI_CODING_AGENT_DIR so Pi loads DOTS-managed global
    # without mutating the user's ~/.pi/agent/sandbox.json mid-run via agent writes.
    live_sandbox = pi_agent_dir / "sandbox.json"
    live_sandbox.write_text(
        (cwd / ".pi" / "sandbox.json").read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    live_sandbox.chmod(0o600)

    # Safe MCP allowlist only (with capability-specific env embedded)
    dots = Path(os.environ.get("DOTS_DIR") or cfg.root)
    scout_cmd = str(Path.home() / ".local" / "bin" / "dots-model-scout")
    expert_cmd = str(Path.home() / ".local" / "bin" / "dots-expert")
    if not Path(scout_cmd).exists():
        scout_cmd = str(dots / "scripts" / "dots-model-scout")
    if not Path(expert_cmd).exists():
        expert_cmd = str(dots / "scripts" / "dots-expert")

    # Filter env dicts to string values only for mcp.json
    scout_e = {k: v for k, v in model_scout_env().items() if v is not None}
    expert_e = {k: v for k, v in expert_env().items() if v is not None}
    write_safe_mcp_json(
        pi_agent_dir / "mcp.json",
        scout_command=scout_cmd,
        expert_command=expert_cmd,
        scout_env=scout_e,
        expert_env=expert_e,
    )

    # Project models.json if present globally — copy for resolution
    global_models = Path.home() / ".pi" / "agent" / "models.json"
    if global_models.is_file():
        shutil.copy2(global_models, pi_agent_dir / "models.json")

    env = pi_env(
        run_id=run_id,
        agent_home=runtime_home,
        pi_agent_dir=pi_agent_dir,
        execution_mode=execution_mode,
    )
    # Pi still needs a usable PATH including rg for sandbox-init
    assert_pi_env_safe(env)

    return RunSession(
        run_id=run_id,
        execution_mode=execution_mode,
        cwd=cwd,
        primary_cwd=primary_cwd,
        worktree=worktree,
        runtime_home=runtime_home,
        pi_agent_dir=pi_agent_dir,
        sandbox_enabled=True,
        network_policy="bash: localhost/127.0.0.1 only; model/MCP separate",
        mcp_servers=["dots-model-scout", "dots-expert"],
        warnings=warnings,
        pi_env=env,
        pi_extra_args=[],  # sandbox extension active via install; do not pass --no-sandbox
    )


def finish_session(session: RunSession) -> None:
    if session.worktree is not None:
        mark_completed(session.worktree)
