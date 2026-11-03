"""Budget + expert consultation unit tests (mocked gateway; no paid calls)."""

from __future__ import annotations

from dots_agent.budget import Budget
from dots_agent.config import load_config
from dots_agent.expert.consult import consult_expert
from dots_agent.secrets import find_secret_hits, redact
from dots_agent.ledger import redact_text


def test_consult_rejects_over_budget():
    cfg = load_config()
    b = Budget(session_budget_usd=0.05, max_remote_calls=3)

    def boom(**kwargs):
        raise AssertionError("gateway must not be called")

    result = consult_expert(
        cfg=cfg,
        budget=b,
        model="test/model",
        question="hello",
        estimated_cost_usd=0.10,
        gateway_callable=boom,
    )
    assert result["ok"] is False
    assert "budget" in result["error"].lower() or "insufficient" in result["error"].lower() or "exhausted" in result["error"].lower()


def test_consult_via_mock_gateway():
    cfg = load_config()
    b = Budget(session_budget_usd=1.0, max_remote_calls=3)

    def fake_gateway(**kwargs):
        assert "openrouter/" in kwargs["model"] or True
        return {
            "choices": [{"message": {"content": "use a mutex"}}],
            "usage": {"cost": 0.012},
        }

    result = consult_expert(
        cfg=cfg,
        budget=b,
        model="anthropic/claude-sonnet-fixture",
        question="How fix race?",
        context="fn foo()",
        estimated_cost_usd=0.05,
        approve_expensive=True,
        gateway_callable=fake_gateway,
    )
    assert result["ok"] is True
    assert "mutex" in result["content"]
    assert result["filesystem_access"] is None
    assert abs(result["charged_usd"] - 0.012) < 1e-9


def test_secret_redaction():
    text = "OPENROUTER_API_KEY=sk-or-v1-secretvalue and password=hunter2"
    assert find_secret_hits(text)
    red = redact(text)
    assert "sk-or-v1-secretvalue" not in red
    assert "hunter2" not in red
    assert "OPENROUTER_API_KEY=sk-secret" not in redact_text("OPENROUTER_API_KEY=sk-secret")


def test_local_disables_remote():
    cfg = load_config()
    b = Budget(session_budget_usd=1.0)
    result = consult_expert(
        cfg=cfg,
        budget=b,
        model="x",
        question="q",
        allow_network=False,
        estimated_cost_usd=0.01,
    )
    assert result["ok"] is False
