"""Secret detection / redaction + DOTS-managed credentials (never logged)."""

from __future__ import annotations

import os
import re
import secrets
from pathlib import Path

# Common secret shapes — not claimed perfect.
_PATTERNS = [
    re.compile(r"(?i)(api[_-]?key|token|password|secret)\s*[:=]\s*['\"]?([^\s'\"]+)"),
    re.compile(r"(?i)bearer\s+[a-z0-9\-._~+/]+=*"),
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"(?i)sk-[a-z0-9]{20,}"),
    re.compile(r"(?i)OPENROUTER_API_KEY\s*[:=]\s*\S+"),
]


def find_secret_hits(text: str) -> list[str]:
    hits: list[str] = []
    for pat in _PATTERNS:
        if pat.search(text):
            hits.append(pat.pattern[:48])
    return hits


def redact(text: str) -> str:
    out = text
    for pat in _PATTERNS:
        out = pat.sub("[REDACTED]", out)
    return out


def reject_or_redact(text: str, *, reject: bool = False) -> tuple[str, list[str]]:
    hits = find_secret_hits(text)
    if hits and reject:
        raise ValueError(f"refusing expert context: possible secrets detected ({len(hits)})")
    return redact(text), hits


def agent_config_dir() -> Path:
    xdg = os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
    return Path(xdg) / "dots"


def litellm_master_key_path() -> Path:
    return agent_config_dir() / "secrets" / "litellm-master-key"


def ensure_litellm_master_key() -> Path:
    """Create a random local LiteLLM master key if missing. Never print the value."""
    path = litellm_master_key_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and path.stat().st_size > 0:
        path.chmod(0o600)
        return path
    # sk- prefix keeps LiteLLM happy; entropy is random, not a shared default.
    value = "sk-dots-" + secrets.token_urlsafe(32)
    path.write_text(value + "\n", encoding="utf-8")
    path.chmod(0o600)
    return path


def load_litellm_master_key() -> str | None:
    """Load key from env or DOTS secret file. Returns None if unset."""
    env = (os.environ.get("LITELLM_MASTER_KEY") or "").strip()
    if env:
        return env
    path = litellm_master_key_path()
    if not path.is_file():
        return None
    raw = path.read_text(encoding="utf-8").strip()
    return raw or None


def litellm_master_key_status() -> str:
    """Doctor-safe status: SET or UNSET (never the value)."""
    return "SET" if load_litellm_master_key() else "UNSET"
