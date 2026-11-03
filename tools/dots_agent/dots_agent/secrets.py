"""Secret detection / redaction for expert context (defense in depth)."""

from __future__ import annotations

import re

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
