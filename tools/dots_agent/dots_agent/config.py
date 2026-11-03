"""Load DOTS agent configuration (repo defaults + optional user override)."""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


def dots_root() -> Path:
    env = os.environ.get("DOTS_DIR")
    if env:
        return Path(env).expanduser().resolve()
    # tools/dots_agent/dots_agent/config.py → repo root
    return Path(__file__).resolve().parents[3]


def _deep_merge(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    out = dict(base)
    for k, v in overlay.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


def _load_toml(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    with path.open("rb") as fh:
        data = tomllib.load(fh)
    return data if isinstance(data, dict) else {}


@dataclass
class AgentConfig:
    raw: dict[str, Any] = field(default_factory=dict)
    root: Path = field(default_factory=dots_root)

    @property
    def session_budget_usd(self) -> float:
        return float(self.raw.get("agent", {}).get("session_budget_usd", 1.0))

    @property
    def max_remote_calls(self) -> int:
        return int(self.raw.get("agent", {}).get("max_remote_calls", 3))

    @property
    def max_iterations(self) -> int:
        return int(self.raw.get("agent", {}).get("max_iterations", 25))

    @property
    def timeout_seconds(self) -> int:
        return int(self.raw.get("agent", {}).get("timeout_seconds", 1800))

    @property
    def approval_threshold_usd(self) -> float:
        return float(self.raw.get("agent", {}).get("approval_threshold_usd", 0.5))

    @property
    def live_test_max_usd(self) -> float:
        return float(self.raw.get("agent", {}).get("live_test_max_usd", 0.05))

    @property
    def gateway_base_url(self) -> str:
        return str(self.raw.get("gateway", {}).get("base_url", "http://127.0.0.1:4000"))

    @property
    def catalog_cache_ttl(self) -> int:
        return int(self.raw.get("scout", {}).get("catalog_cache_ttl_seconds", 900))

    @property
    def catalog_url(self) -> str:
        return str(
            self.raw.get("scout", {}).get(
                "catalog_url", "https://openrouter.ai/api/v1/models/user"
            )
        )

    @property
    def catalog_url_public(self) -> str:
        return str(
            self.raw.get("scout", {}).get(
                "catalog_url_public", "https://openrouter.ai/api/v1/models"
            )
        )

    @property
    def provider_sort(self) -> str:
        return str(self.raw.get("scout", {}).get("provider_sort", "price"))

    @property
    def max_candidates(self) -> int:
        return int(self.raw.get("scout", {}).get("max_candidates", 5))

    @property
    def local_provider(self) -> str:
        return str(self.raw.get("local", {}).get("provider", "auto"))

    @property
    def local_model(self) -> str:
        return str(self.raw.get("local", {}).get("model", "auto"))

    def cache_dir(self) -> Path:
        xdg = os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))
        rel = self.raw.get("paths", {}).get("cache_dir", "dots/agents")
        p = Path(xdg) / rel
        p.mkdir(parents=True, exist_ok=True)
        return p

    def state_dir(self) -> Path:
        xdg = os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state"))
        rel = self.raw.get("paths", {}).get("state_dir", "dots/agents")
        p = Path(xdg) / rel
        p.mkdir(parents=True, exist_ok=True)
        return p

    def runs_dir(self) -> Path:
        p = self.state_dir() / "runs"
        p.mkdir(parents=True, exist_ok=True)
        return p

    def capabilities_path(self) -> Path:
        return self.root / "configs" / "agents" / "model-capabilities.toml"

    def foreman_prompt_path(self) -> Path:
        rel = self.raw.get("policy", {}).get(
            "system_prompt_path", "configs/agents/local-foreman.md"
        )
        return self.root / rel

    def evals_dir(self) -> Path:
        p = self.state_dir() / "evals"
        p.mkdir(parents=True, exist_ok=True)
        return p

    def eval_registry_path(self) -> Path:
        rel = self.raw.get("evals", {}).get(
            "registry", "configs/agents/evals/registry.toml"
        )
        return self.root / rel

    @property
    def routing_policy_version(self) -> int:
        return int(self.raw.get("routing", {}).get("policy_version", 1))

    @property
    def routing_preference(self) -> str:
        return str(self.raw.get("routing", {}).get("preference", "economy"))

    def quality_floors(self) -> dict[str, float]:
        q = self.raw.get("routing", {}).get("quality") or {}
        return {
            "basic": float(q.get("basic", 0.40)),
            "capable": float(q.get("capable", 0.60)),
            "strong": float(q.get("strong", 0.80)),
            "frontier": float(q.get("frontier", 0.90)),
        }

    @property
    def evidence_minimum_attempts(self) -> int:
        return int(self.raw.get("routing", {}).get("evidence", {}).get("minimum_attempts", 5))

    @property
    def evidence_max_age_days(self) -> float:
        return float(self.raw.get("routing", {}).get("evidence", {}).get("max_age_days", 90))

    @property
    def wilson_z(self) -> float:
        return float(self.raw.get("routing", {}).get("evidence", {}).get("wilson_z", 1.96))

    @property
    def eval_default_suite(self) -> str:
        return str(self.raw.get("evals", {}).get("default_suite", "standard"))

    @property
    def eval_default_local_runs(self) -> int:
        return int(self.raw.get("evals", {}).get("default_local_runs", 3))

    @property
    def eval_default_remote_runs(self) -> int:
        return int(self.raw.get("evals", {}).get("default_remote_runs", 1))


def load_config(root: Path | None = None) -> AgentConfig:
    root = root or dots_root()
    defaults = _load_toml(root / "configs" / "agents" / "defaults.toml")
    user = _load_toml(Path.home() / ".config" / "dots" / "agents.toml")
    env_overlay: dict[str, Any] = {}
    if os.environ.get("DOTS_AGENT_BUDGET"):
        env_overlay.setdefault("agent", {})["session_budget_usd"] = float(
            os.environ["DOTS_AGENT_BUDGET"]
        )
    if os.environ.get("DOTS_AGENT_MAX_REMOTE"):
        env_overlay.setdefault("agent", {})["max_remote_calls"] = int(
            os.environ["DOTS_AGENT_MAX_REMOTE"]
        )
    merged = _deep_merge(defaults, user)
    merged = _deep_merge(merged, env_overlay)
    return AgentConfig(raw=merged, root=root)
