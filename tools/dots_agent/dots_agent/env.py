"""Capability-specific subprocess environments (no full parent env copy)."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Mapping

from dots_agent.secrets import load_litellm_master_key

# Keys allowed into the Pi / bash-facing process.
_PI_ALLOW = frozenset(
    {
        "PATH",
        "HOME",
        "USER",
        "LOGNAME",
        "SHELL",
        "TERM",
        "TMPDIR",
        "TMP",
        "TEMP",
        "LANG",
        "LC_ALL",
        "LC_CTYPE",
        "LC_MESSAGES",
        "TZ",
        "COLORTERM",
        "TERM_PROGRAM",
        "XDG_RUNTIME_DIR",
        "XDG_CACHE_HOME",
        "XDG_CONFIG_HOME",
        "XDG_STATE_HOME",
        "XDG_DATA_HOME",
        # Pi / Node
        "PI_CODING_AGENT_DIR",
        "PI_OFFLINE",
        "NODE_PATH",
        "npm_config_cache",
        # DOTS run ids (non-secret)
        "DOTS_DIR",
        "DOTS_AGENT_RUN_ID",
        "DOTS_AGENT_BUDGET",
        "DOTS_AGENT_MAX_REMOTE",
        "DOTS_AGENT_LOCAL",
        "DOTS_AGENT_EXECUTION_MODE",
        # Local model endpoints (no credentials)
        "OLLAMA_HOST",
        "DOTS_LOCAL_API_BASE",
    }
)

# Prefixes never passed to Pi/bash even if somehow allowlisted later.
_PI_DENY_PREFIXES = (
    "AWS_",
    "GITHUB_",
    "GH_",
    "OPENAI_",
    "ANTHROPIC_",
    "OPENROUTER_",
    "LITELLM_",
    "NPM_TOKEN",
    "PYPI_",
    "DOCKER_",
    "KUBE",
    "GOOGLE_",
    "GCLOUD_",
    "CLOUDSDK_",
)

_SECRET_SUFFIXES = ("_TOKEN", "_KEY", "_SECRET", "_PASSWORD", "_PASSWD", "_API_KEY")


def _is_denied_key(key: str) -> bool:
    if key in ("DOTS_AGENT_APPROVE_EXPENSIVE",):
        return False
    if any(key.startswith(p) for p in _PI_DENY_PREFIXES):
        return True
    if key.endswith(_SECRET_SUFFIXES):
        # Allow empty PATH-like edge cases only if explicitly allowlisted
        if key not in _PI_ALLOW:
            return True
    return False


def _base_from_parent(parent: Mapping[str, str] | None = None) -> dict[str, str]:
    src = dict(parent if parent is not None else os.environ)
    out: dict[str, str] = {}
    for k, v in src.items():
        if k in _PI_ALLOW and not _is_denied_key(k):
            out[k] = v
    # Always ensure PATH/HOME/LANG basics exist
    for req in ("PATH", "HOME", "LANG"):
        if req not in out and req in src:
            out[req] = src[req]
    if "PATH" not in out:
        out["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    # LC_* passthrough
    for k, v in src.items():
        if k.startswith("LC_") and k not in out:
            out[k] = v
    return out


def pi_env(
    *,
    run_id: str | None = None,
    agent_home: Path | None = None,
    pi_agent_dir: Path | None = None,
    local_only: bool = False,
    execution_mode: str = "safe",
    parent: Mapping[str, str] | None = None,
    extra: Mapping[str, str] | None = None,
) -> dict[str, str]:
    """Environment for the Pi process / sandboxed bash.

    Must NOT include OpenRouter or LiteLLM credentials.
    """
    env = _base_from_parent(parent)
    if agent_home is not None:
        env["HOME"] = str(agent_home)
    if pi_agent_dir is not None:
        env["PI_CODING_AGENT_DIR"] = str(pi_agent_dir)
    if run_id:
        env["DOTS_AGENT_RUN_ID"] = run_id
    env["DOTS_AGENT_EXECUTION_MODE"] = execution_mode
    if local_only:
        env["DOTS_AGENT_LOCAL"] = "1"
    # Explicitly scrub secrets that might have slipped in
    for ban in (
        "OPENROUTER_API_KEY",
        "LITELLM_MASTER_KEY",
        "OPENAI_API_KEY",
        "ANTHROPIC_API_KEY",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_ACCESS_KEY_ID",
        "GITHUB_TOKEN",
        "GH_TOKEN",
    ):
        env.pop(ban, None)
    if extra:
        for k, v in extra.items():
            if not _is_denied_key(k):
                env[k] = v
    return env


def model_scout_env(
    *,
    parent: Mapping[str, str] | None = None,
    allow_openrouter: bool = True,
) -> dict[str, str]:
    """Environment for dots-model-scout MCP — may include catalog API key only."""
    env = _base_from_parent(parent)
    src = parent if parent is not None else os.environ
    if allow_openrouter and src.get("OPENROUTER_API_KEY"):
        env["OPENROUTER_API_KEY"] = src["OPENROUTER_API_KEY"]
    env.pop("LITELLM_MASTER_KEY", None)
    return env


def expert_env(
    *,
    parent: Mapping[str, str] | None = None,
) -> dict[str, str]:
    """Environment for dots-expert MCP — LiteLLM master key; not for Pi bash."""
    env = _base_from_parent(parent)
    key = load_litellm_master_key()
    if key:
        env["LITELLM_MASTER_KEY"] = key
    # OpenRouter is used by LiteLLM gateway, not necessarily by expert client;
    # do not put it in expert unless required for direct calls (Phase 1 uses LiteLLM).
    env.pop("OPENROUTER_API_KEY", None)
    return env


def litellm_env(
    *,
    parent: Mapping[str, str] | None = None,
) -> dict[str, str]:
    """Environment for Compose / LiteLLM process."""
    env = _base_from_parent(parent)
    src = parent if parent is not None else os.environ
    key = load_litellm_master_key()
    if key:
        env["LITELLM_MASTER_KEY"] = key
    if src.get("OPENROUTER_API_KEY"):
        env["OPENROUTER_API_KEY"] = src["OPENROUTER_API_KEY"]
    return env


def assert_pi_env_safe(env: Mapping[str, str]) -> None:
    """Raise if Pi env still contains remote credentials."""
    for ban in ("OPENROUTER_API_KEY", "LITELLM_MASTER_KEY", "AWS_SECRET_ACCESS_KEY"):
        if env.get(ban):
            raise RuntimeError(f"refusing to launch Pi with {ban} in environment")
