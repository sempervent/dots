"""Structured merge of Pi ~/.pi/agent/models.json for local providers.

Schema reference: https://pi.dev/docs/latest/models-configuration
Ollama uses openai-completions against http://127.0.0.1:11434/v1.
"""

from __future__ import annotations

import json
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .providers import LocalProvider


def pi_agent_dir() -> Path:
    return Path.home() / ".pi" / "agent"


def models_json_path() -> Path:
    return pi_agent_dir() / "models.json"


def mcp_json_path() -> Path:
    return pi_agent_dir() / "mcp.json"


def _backup(path: Path) -> Path | None:
    if not path.is_file():
        return None
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    bak = path.with_suffix(path.suffix + f".bak-{stamp}")
    shutil.copy2(path, bak)
    return bak


def _zero_cost() -> dict[str, float]:
    return {"input": 0.0, "output": 0.0, "cacheRead": 0.0, "cacheWrite": 0.0}


def ollama_provider_entry(model_id: str, *, base_url: str) -> dict[str, Any]:
    """Pi custom provider for Ollama (OpenAI-compatible /v1)."""
    root = base_url.rstrip("/")
    if not root.endswith("/v1"):
        root = root + "/v1"
    return {
        "baseUrl": root,
        "api": "openai-completions",
        "apiKey": "ollama",  # Ollama ignores auth; placeholder satisfies schema
        "models": [
            {
                "id": model_id,
                "name": model_id,
                "reasoning": False,
                "input": ["text"],
                "cost": _zero_cost(),
                "contextWindow": 32768,
                "maxTokens": 8192,
            }
        ],
    }


def llamacpp_provider_entry(model_id: str, *, base_url: str) -> dict[str, Any]:
    """OpenAI-compatible llama.cpp server via models.json (native router also exists)."""
    root = base_url.rstrip("/")
    if not root.endswith("/v1"):
        root = root + "/v1"
    return {
        "baseUrl": root,
        "api": "openai-completions",
        "apiKey": "llamacpp",
        "models": [
            {
                "id": model_id or "local",
                "name": model_id or "local",
                "reasoning": False,
                "input": ["text"],
                "cost": _zero_cost(),
                "contextWindow": 32768,
                "maxTokens": 8192,
            }
        ],
    }


def merge_local_provider(local: LocalProvider, *, path: Path | None = None) -> dict[str, Any]:
    """Merge DOTS-managed local provider into models.json without wiping unrelated entries."""
    path = path or models_json_path()
    path.parent.mkdir(parents=True, exist_ok=True)

    data: dict[str, Any] = {"providers": {}}
    if path.is_file():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                data = loaded
        except (json.JSONDecodeError, OSError):
            _backup(path)
            data = {"providers": {}}

    providers = data.get("providers")
    if not isinstance(providers, dict):
        providers = {}
        data["providers"] = providers

    if local.name == "ollama" and local.healthy and local.model:
        desired_key = "ollama"
        desired = ollama_provider_entry(local.model, base_url=local.base_url)
    elif local.name == "llamacpp" and local.healthy:
        desired_key = "llamacpp"
        desired = llamacpp_provider_entry(local.model or "local", base_url=local.base_url)
    else:
        return {"ok": False, "error": f"no healthy local provider to merge ({local.name})", "path": str(path)}

    existing = providers.get(desired_key)
    # Preserve unrelated models already listed under the same provider id.
    if isinstance(existing, dict):
        existing_models = existing.get("models")
        if isinstance(existing_models, list):
            known_ids = {
                m.get("id")
                for m in desired.get("models", [])
                if isinstance(m, dict)
            }
            merged_models = list(desired["models"])
            for m in existing_models:
                if isinstance(m, dict) and m.get("id") not in known_ids:
                    merged_models.append(m)
            desired["models"] = merged_models
        # Keep user apiKey / headers if they set env interpolation
        if existing.get("apiKey") and str(existing.get("apiKey", "")).startswith("$"):
            desired["apiKey"] = existing["apiKey"]
        if isinstance(existing.get("headers"), dict):
            desired["headers"] = {**existing["headers"], **desired.get("headers", {})}

    changed = existing != desired
    if changed:
        _backup(path)
        providers[desired_key] = desired
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        path.chmod(0o600)

    return {
        "ok": True,
        "changed": changed,
        "provider": desired_key,
        "model": local.model,
        "path": str(path),
        "pi_provider": desired_key,
        "pi_model": local.model,
    }


def resolve_pi_selection(local: LocalProvider) -> dict[str, str | None]:
    """Map detect_local() → Pi --provider / --model flags."""
    if local.name == "ollama" and local.healthy and local.model:
        return {
            "provider": "ollama",
            "model": local.model,
            "endpoint": (local.base_url.rstrip("/") + "/v1")
            if not local.base_url.rstrip("/").endswith("/v1")
            else local.base_url.rstrip("/"),
        }
    if local.name == "llamacpp" and local.healthy:
        endpoint = local.base_url.rstrip("/")
        if not endpoint.endswith("/v1"):
            endpoint = endpoint + "/v1"
        return {
            "provider": "llamacpp",
            "model": local.model or "local",
            "endpoint": endpoint,
        }
    return {"provider": None, "model": None, "endpoint": None}
