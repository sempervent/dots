"""Expected-cost routing: cheaper/call can lose to more reliable model."""

from __future__ import annotations

from pathlib import Path

from dots_agent.routing.evidence import EvidenceType, ModelClassEvidence
from dots_agent.scout.select import Requirements, select_model
from dots_agent.stats import expected_cost_to_success, summarize_binomial

ROOT = Path(__file__).resolve().parents[3]
CAPS = ROOT / "configs" / "agents" / "model-capabilities.toml"


def _model(mid: str, prompt: str, completion: str, ctx: int = 32000) -> dict:
    return {
        "id": mid,
        "context_length": ctx,
        "supported_parameters": ["tools", "response_format"],
        "pricing": {"prompt": prompt, "completion": completion},
    }


def test_expected_cost_selects_reliable_over_cheap():
    """A cheapest/call low reliability; B medium; C expensive; D insufficient evidence.

    Policy must select B.
    """
    # Pricing is per-token dollars in OpenRouter catalog style used by estimate_cost
    # estimate: cost = tokens * price (see cost.py)
    models = [
        _model("test/cheap-unreliable", "0.000002", "0.000002"),  # ~$0.02 for 8k+2k? tune
        _model("test/balanced-reliable", "0.000006", "0.000006"),
        _model("test/expensive-reliable", "0.00005", "0.00005"),
        _model("test/new-unknown", "0.000001", "0.000001"),
    ]

    # Build synthetic evidence with known Wilson bounds
    # A: 2/8 = 25% → low Wilson
    # B: 18/20 = 90%
    # C: 19/20 = 95%
    # D: 1/1 insufficient
    sa = summarize_binomial(2, 8)
    sb = summarize_binomial(18, 20)
    sc = summarize_binomial(19, 20)
    sd = summarize_binomial(1, 1)

    evidence = {
        ("test/cheap-unreliable", "debugging"): ModelClassEvidence(
            model_id="test/cheap-unreliable",
            task_class="debugging",
            evidence=EvidenceType.EMPIRICAL,
            attempts=8,
            successes=2,
            raw_success_rate=sa.raw_rate,
            conservative_success_rate=sa.wilson_lower,
        ),
        ("test/balanced-reliable", "debugging"): ModelClassEvidence(
            model_id="test/balanced-reliable",
            task_class="debugging",
            evidence=EvidenceType.EMPIRICAL,
            attempts=20,
            successes=18,
            raw_success_rate=sb.raw_rate,
            conservative_success_rate=sb.wilson_lower,
        ),
        ("test/expensive-reliable", "debugging"): ModelClassEvidence(
            model_id="test/expensive-reliable",
            task_class="debugging",
            evidence=EvidenceType.EMPIRICAL,
            attempts=20,
            successes=19,
            raw_success_rate=sc.raw_rate,
            conservative_success_rate=sc.wilson_lower,
        ),
        ("test/new-unknown", "debugging"): ModelClassEvidence(
            model_id="test/new-unknown",
            task_class="debugging",
            evidence=EvidenceType.EMPIRICAL,
            attempts=1,
            successes=1,
            raw_success_rate=sd.raw_rate,
            conservative_success_rate=sd.wilson_lower,
        ),
    }

    def lookup(mid: str, tc: str):
        return evidence.get((mid, tc))

    # quality floors: basic=0.10 so A can qualify empirically if Wilson allows;
    # Use basic floor so A is not filtered solely by floor — ranking decides.
    # Actually A wilson for 2/8 is quite low (~0.07). Set basic=0.05 so A qualifies.
    qcfg = {"basic": 0.05, "capable": 0.15, "strong": 0.50, "frontier": 0.80}

    req = Requirements(
        task_type="debugging",
        context_tokens=1000,
        expected_output_tokens=500,
        requires_tools=True,
        quality_floor="basic",
        max_cost_usd=5.0,
    )
    result = select_model(
        models,
        req,
        capabilities_path=CAPS,
        evidence_lookup=lookup,
        quality_cfg=qcfg,
        minimum_attempts=5,
        preference="economy",
    )
    sel = result["selected"]
    assert sel is not None
    assert sel["model"] == "test/balanced-reliable"
    assert sel["evidence"] == "empirical"
    assert sel["expected_cost_to_success_usd"] is not None

    # Cheaper/call A must have higher expected cost if it survived
    a_cost = None
    b_cost = sel["expected_cost_to_success_usd"]
    for row in [sel, *result["alternatives"]]:
        if row["model"] == "test/cheap-unreliable":
            a_cost = row["expected_cost_to_success_usd"]
    # A may be rejected by empirical floor; either way B wins
    if a_cost is not None:
        assert a_cost > b_cost

    explanation = " ".join(result.get("explanation") or [])
    assert "balanced-reliable" in explanation or "expected cost" in explanation.lower()


def test_local_zero_cost_wins_when_reliable():
    models = [
        {
            "id": "local/qwen",
            "context_length": 32000,
            "supported_parameters": ["tools"],
            "pricing": {"prompt": "0", "completion": "0"},
            "_dots_local": True,
        },
        _model("test/paid", "0.00001", "0.00001"),
    ]
    s = summarize_binomial(10, 10)

    def lookup(mid: str, tc: str):
        if mid == "local/qwen":
            return ModelClassEvidence(
                model_id=mid,
                task_class=tc,
                evidence=EvidenceType.EMPIRICAL,
                attempts=10,
                successes=10,
                raw_success_rate=s.raw_rate,
                conservative_success_rate=s.wilson_lower,
            )
        if mid == "test/paid":
            return ModelClassEvidence(
                model_id=mid,
                task_class=tc,
                evidence=EvidenceType.EMPIRICAL,
                attempts=10,
                successes=10,
                raw_success_rate=s.raw_rate,
                conservative_success_rate=s.wilson_lower,
            )
        return None

    req = Requirements(
        task_type="coding",
        context_tokens=1000,
        expected_output_tokens=200,
        requires_tools=True,
        quality_floor="basic",
        max_cost_usd=1.0,
    )
    result = select_model(
        models,
        req,
        capabilities_path=CAPS,
        evidence_lookup=lookup,
        quality_cfg={"basic": 0.5, "capable": 0.6, "strong": 0.8, "frontier": 0.9},
        minimum_attempts=5,
    )
    assert result["selected"]["model"] == "local/qwen"
    assert result["selected"]["expected_cost_to_success_usd"] == 0.0


def test_formula_matches_spec_example():
    assert abs(expected_cost_to_success(0.02, 0.25) - 0.08) < 1e-12
    b = expected_cost_to_success(0.06, 0.90)
    assert b is not None
    assert abs(b - (0.06 / 0.90)) < 1e-12
