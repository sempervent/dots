"""Wilson interval and expected-cost unit tests."""

from __future__ import annotations

import math

from dots_agent.stats import (
    bounded_expected_spend,
    expected_cost_to_success,
    summarize_binomial,
    wilson_interval,
)


def test_wilson_zero_attempts():
    lo, hi = wilson_interval(0, 0)
    assert lo is None and hi is None


def test_wilson_zero_successes():
    lo, hi = wilson_interval(0, 10)
    assert lo is not None and hi is not None
    assert lo < 0.05
    assert hi > 0.0


def test_wilson_all_successes():
    lo, hi = wilson_interval(10, 10)
    assert lo is not None
    # Known reference: Wilson lower for 10/10 at z=1.96 is ~0.7225
    assert 0.70 < lo < 0.75
    assert hi == 1.0 or hi > 0.99


def test_wilson_large_sample_near_raw():
    lo, hi = wilson_interval(900, 1000)
    assert lo is not None and hi is not None
    assert abs((lo + hi) / 2 - 0.9) < 0.02
    assert lo < 0.9 < hi


def test_wilson_small_sample_not_overconfident():
    s = summarize_binomial(1, 1)
    assert s.raw_rate == 1.0
    assert s.wilson_lower is not None
    assert s.wilson_lower < 0.8  # must not treat 1/1 as reliable


def test_expected_cost_basic():
    # A: 0.02 / 0.25 = 0.08; B: 0.06 / 0.90 ≈ 0.0667
    a = expected_cost_to_success(0.02, 0.25)
    b = expected_cost_to_success(0.06, 0.90)
    assert a is not None and b is not None
    assert abs(a - 0.08) < 1e-9
    assert b < a


def test_expected_cost_zero_p():
    assert expected_cost_to_success(0.05, 0.0) is None
    assert expected_cost_to_success(0.05, None) is None


def test_bounded_spend_certain():
    assert bounded_expected_spend(0.1, 1.0, max_attempts=3) == 0.1


def test_bounded_spend_truncated():
    # p=0.5, N=2, c=1 → E[attempts] = 1*0.5 + 2*0.5*0.5 + 2*(0.5)^2 = 0.5+0.5+0.5 = 1.5
    e = bounded_expected_spend(1.0, 0.5, max_attempts=2)
    assert e is not None
    assert abs(e - 1.5) < 1e-9
