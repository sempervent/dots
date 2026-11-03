"""Local inference provider detection (llama.cpp / Ollama)."""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any

from .config import AgentConfig


@dataclass
class LocalProvider:
    name: str  # llamacpp | ollama | none
    base_url: str
    model: str
    healthy: bool
    detail: str = ""


def _get_json(url: str, timeout: float = 2.0) -> Any | None:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        return None


def probe_llamacpp(base: str) -> LocalProvider:
    root = base.rstrip("/")
    if root.endswith("/v1"):
        models_url = root + "/models"
    else:
        models_url = root + "/v1/models"
    data = _get_json(models_url)
    if not data:
        return LocalProvider("llamacpp", base, "", False, "unreachable")
    models = data.get("data") or []
    mid = ""
    if models and isinstance(models[0], dict):
        mid = str(models[0].get("id") or "")
    return LocalProvider("llamacpp", base, mid, True, f"{len(models)} model(s)")


def probe_ollama(base: str) -> LocalProvider:
    root = base.rstrip("/")
    data = _get_json(root + "/api/tags")
    if not data:
        return LocalProvider("ollama", base, "", False, "unreachable")
    models = data.get("models") or []
    mid = ""
    if models and isinstance(models[0], dict):
        mid = str(models[0].get("name") or models[0].get("model") or "")
    return LocalProvider("ollama", base, mid, True, f"{len(models)} model(s)")


def detect_local(cfg: AgentConfig) -> LocalProvider:
    pref = (cfg.local_provider or "auto").lower()
    model_cfg = cfg.local_model
    llama_url = str(cfg.raw.get("local", {}).get("llamacpp_base_url", "http://127.0.0.1:8080/v1"))
    ollama_url = str(cfg.raw.get("local", {}).get("ollama_base_url", "http://127.0.0.1:11434"))

    if pref == "llamacpp":
        p = probe_llamacpp(llama_url)
        if model_cfg and model_cfg != "auto":
            p.model = model_cfg
        return p
    if pref == "ollama":
        p = probe_ollama(ollama_url)
        if model_cfg and model_cfg != "auto":
            p.model = model_cfg
        return p

    # auto: prefer llama.cpp if healthy, else ollama
    llama = probe_llamacpp(llama_url)
    if llama.healthy:
        if model_cfg and model_cfg != "auto":
            llama.model = model_cfg
        llama.detail = "auto→llamacpp; " + llama.detail
        return llama
    ollama = probe_ollama(ollama_url)
    if ollama.healthy:
        if model_cfg and model_cfg != "auto":
            ollama.model = model_cfg
        ollama.detail = "auto→ollama; " + ollama.detail
        return ollama
    return LocalProvider("none", "", "", False, "no local provider reachable")
