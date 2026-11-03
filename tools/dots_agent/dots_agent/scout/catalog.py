"""OpenRouter model catalog fetch + cache."""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class Catalog:
    models: list[dict[str, Any]]
    source: str  # live | cached
    fetched_at: float
    url: str
    age_seconds: float = 0.0
    stale: bool = False


def cache_path(cache_dir: Path) -> Path:
    return cache_dir / "openrouter-models.json"


def _authorized_get(url: str, api_key: str | None, timeout: float = 30.0) -> dict[str, Any]:
    headers = {
        "Accept": "application/json",
        "User-Agent": "dots-model-scout/0.1",
    }
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    req = urllib.request.Request(url, headers=headers, method="GET")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def save_cache(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def load_cache(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def fetch_catalog(
    *,
    cache_dir: Path,
    catalog_url: str,
    catalog_url_public: str,
    ttl_seconds: int,
    force_live: bool = False,
    allow_network: bool = True,
    api_key: str | None = None,
) -> Catalog:
    """Fetch account-filtered catalog when key present; else public list.

    Never sends task/source content — metadata only.
    """
    path = cache_path(cache_dir)
    now = time.time()
    api_key = api_key if api_key is not None else os.environ.get("OPENROUTER_API_KEY")
    url = catalog_url if api_key else catalog_url_public

    cached = load_cache(path)
    if cached and not force_live:
        fetched_at = float(cached.get("fetched_at") or 0)
        age = now - fetched_at
        if age <= ttl_seconds:
            models = cached.get("models") or []
            return Catalog(
                models=list(models),
                source="cached",
                fetched_at=fetched_at,
                url=str(cached.get("url") or url),
                age_seconds=age,
                stale=False,
            )

    if not allow_network:
        if cached:
            fetched_at = float(cached.get("fetched_at") or 0)
            age = now - fetched_at
            return Catalog(
                models=list(cached.get("models") or []),
                source="cached",
                fetched_at=fetched_at,
                url=str(cached.get("url") or url),
                age_seconds=age,
                stale=age > ttl_seconds,
            )
        raise RuntimeError("catalog unavailable offline and no cache")

    try:
        body = _authorized_get(url, api_key)
        models = body.get("data") or body.get("models") or []
        if not isinstance(models, list):
            models = []
        payload = {"fetched_at": now, "url": url, "models": models}
        save_cache(path, payload)
        return Catalog(
            models=models,
            source="live",
            fetched_at=now,
            url=url,
            age_seconds=0.0,
            stale=False,
        )
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
        if cached:
            fetched_at = float(cached.get("fetched_at") or 0)
            age = now - fetched_at
            # Refuse ancient cache as current pricing (> 7 days)
            stale = age > ttl_seconds
            ancient = age > 7 * 86400
            if ancient:
                raise RuntimeError(
                    f"OpenRouter unreachable and cache too old ({int(age)}s): {exc}"
                ) from exc
            return Catalog(
                models=list(cached.get("models") or []),
                source="cached",
                fetched_at=fetched_at,
                url=str(cached.get("url") or url),
                age_seconds=age,
                stale=stale,
            )
        raise RuntimeError(f"OpenRouter catalog unreachable: {exc}") from exc
