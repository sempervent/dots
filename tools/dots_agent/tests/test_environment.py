"""Environment allowlist / credential isolation tests."""

from __future__ import annotations

import pytest

from dots_agent.env import (
    assert_pi_env_safe,
    expert_env,
    model_scout_env,
    pi_env,
)


def test_pi_env_strips_secrets(monkeypatch):
    parent = {
        "PATH": "/usr/bin",
        "HOME": "/tmp/home",
        "LANG": "C",
        "OPENROUTER_API_KEY": "sk-or-secret",
        "LITELLM_MASTER_KEY": "sk-litellm-secret",
        "AWS_SECRET_ACCESS_KEY": "aws-secret",
        "GITHUB_TOKEN": "ghp_secret",
        "DOTS_DIR": "/repo",
    }
    env = pi_env(run_id="r1", parent=parent, execution_mode="safe")
    assert "OPENROUTER_API_KEY" not in env
    assert "LITELLM_MASTER_KEY" not in env
    assert "AWS_SECRET_ACCESS_KEY" not in env
    assert "GITHUB_TOKEN" not in env
    assert env["DOTS_DIR"] == "/repo"
    assert_pi_env_safe(env)


def test_assert_pi_env_safe_raises():
    with pytest.raises(RuntimeError):
        assert_pi_env_safe({"OPENROUTER_API_KEY": "x", "PATH": "/bin"})


def test_scout_may_receive_openrouter(monkeypatch):
    parent = {"PATH": "/usr/bin", "HOME": "/tmp", "OPENROUTER_API_KEY": "sk-or"}
    env = model_scout_env(parent=parent)
    assert env.get("OPENROUTER_API_KEY") == "sk-or"
    assert "LITELLM_MASTER_KEY" not in env


def test_expert_receives_litellm_not_openrouter(monkeypatch, tmp_path):
    key_path = tmp_path / "litellm-master-key"
    key_path.parent.mkdir(parents=True, exist_ok=True)
    # secrets.litellm_master_key_path uses XDG_CONFIG_HOME
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    secrets_dir = tmp_path / "dots" / "secrets"
    secrets_dir.mkdir(parents=True)
    (secrets_dir / "litellm-master-key").write_text("sk-dots-test-key\n")
    parent = {"PATH": "/usr/bin", "HOME": "/tmp", "OPENROUTER_API_KEY": "sk-or"}
    env = expert_env(parent=parent)
    assert env.get("LITELLM_MASTER_KEY") == "sk-dots-test-key"
    assert "OPENROUTER_API_KEY" not in env
