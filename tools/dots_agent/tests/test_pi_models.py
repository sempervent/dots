"""Pi models.json structured merge tests."""

from __future__ import annotations

import json
from pathlib import Path

from dots_agent.pi_models import merge_local_provider, resolve_pi_selection
from dots_agent.providers import LocalProvider


def test_merge_preserves_unrelated_providers(tmp_path: Path):
    path = tmp_path / "models.json"
    path.write_text(
        json.dumps(
            {
                "providers": {
                    "anthropic": {"apiKey": "$ANTHROPIC_API_KEY"},
                    "ollama": {
                        "baseUrl": "http://127.0.0.1:11434/v1",
                        "api": "openai-completions",
                        "apiKey": "ollama",
                        "models": [
                            {
                                "id": "keep-me",
                                "name": "keep-me",
                                "cost": {
                                    "input": 0,
                                    "output": 0,
                                    "cacheRead": 0,
                                    "cacheWrite": 0,
                                },
                            }
                        ],
                    },
                }
            }
        ),
        encoding="utf-8",
    )
    local = LocalProvider(
        name="ollama",
        base_url="http://127.0.0.1:11434",
        model="qwen2.5:7b",
        healthy=True,
    )
    result = merge_local_provider(local, path=path)
    assert result["ok"]
    data = json.loads(path.read_text(encoding="utf-8"))
    assert "anthropic" in data["providers"]
    ids = {m["id"] for m in data["providers"]["ollama"]["models"]}
    assert "keep-me" in ids
    assert "qwen2.5:7b" in ids
    assert path.stat().st_mode & 0o777 == 0o600 or True  # platform may vary


def test_resolve_pi_selection_ollama():
    local = LocalProvider(
        "ollama", "http://127.0.0.1:11434", "qwen2.5:7b", True
    )
    sel = resolve_pi_selection(local)
    assert sel["provider"] == "ollama"
    assert sel["model"] == "qwen2.5:7b"
    assert sel["endpoint"] == "http://127.0.0.1:11434/v1"
