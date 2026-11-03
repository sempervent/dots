"""Optional OpenRouter benchmarks API ingestion (secondary evidence only)."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

# Official OpenRouter benchmarks endpoint (investigated Phase 3).
# Docs: https://openrouter.ai/docs — GET /api/v1/benchmarks
DEFAULT_BENCHMARKS_URL = "https://openrouter.ai/api/v1/benchmarks"


def fetch_benchmarks(
    *,
    cache_path: Path,
    url: str = DEFAULT_BENCHMARKS_URL,
    api_key: str | None = None,
    allow_network: bool = True,
    timeout: float = 30.0,
) -> dict[str, Any]:
    """Fetch and cache OpenRouter benchmark metadata.

    Never convert benchmark scores into DOTS task success probability.
    """
    if cache_path.is_file() and not allow_network:
        return json.loads(cache_path.read_text(encoding="utf-8"))

    if not allow_network:
        return {"ok": False, "reason": "network_disabled", "benchmarks": []}

    headers = {
        "Accept": "application/json",
        "User-Agent": "dots-agent-eval/0.1",
    }
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return {
            "ok": False,
            "reason": f"http_{exc.code}",
            "benchmarks": [],
            "url": url,
        }
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        return {"ok": False, "reason": str(exc), "benchmarks": [], "url": url}

    rows = _normalize(raw)
    payload = {
        "ok": True,
        "schema_version": 1,
        "source": "openrouter",
        "url": url,
        "fetched_at": time.time(),
        "benchmarks": rows,
        # Explicit: not usable as task success probability
        "used_as_task_success_probability": False,
    }
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return payload


def _normalize(raw: Any) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    data = raw.get("data") if isinstance(raw, dict) else raw
    if isinstance(raw, dict) and data is None:
        data = raw.get("benchmarks") or raw.get("results") or []
    if not isinstance(data, list):
        return out
    for row in data:
        if not isinstance(row, dict):
            continue
        mid = str(row.get("model") or row.get("model_id") or row.get("id") or "")
        if not mid:
            continue
        out.append(
            {
                "benchmark": str(row.get("benchmark") or row.get("name") or "unknown"),
                "model": mid,
                "score": row.get("score") or row.get("quality"),
                "cost": row.get("cost"),
                "speed": row.get("speed"),
                "date": row.get("date") or row.get("updated_at"),
                "source": "openrouter",
                "raw_keys": sorted(row.keys())[:20],
            }
        )
    return out
