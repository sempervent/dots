"""Atomic team budget concurrency tests."""

from __future__ import annotations

import threading
from pathlib import Path

import pytest

from dots_agent.openrig.team_budget import TeamBudget


def test_reserve_settle_and_attribution(tmp_path: Path):
    db = tmp_path / "b.sqlite"
    tb = TeamBudget(db, team_id="t1", budget_usd=1.0)
    r = tb.reserve(seat="team-builder@t", role="builder", amount_usd=0.4)
    snap = tb.snapshot()
    assert abs(snap["reserved_usd"] - 0.4) < 1e-9
    tb.settle(r, actual_usd=0.25, model="test/m", task_ref="q1")
    snap = tb.snapshot()
    assert abs(snap["spent_usd"] - 0.25) < 1e-9
    assert abs(snap["reserved_usd"]) < 1e-9
    by = tb.by_seat()
    assert by[0]["seat"] == "team-builder@t"
    assert abs(by[0]["spent_usd"] - 0.25) < 1e-9


def test_cannot_overspend(tmp_path: Path):
    tb = TeamBudget(tmp_path / "b.sqlite", team_id="t1", budget_usd=0.5)
    tb.reserve(seat="a", role="lead", amount_usd=0.4)
    with pytest.raises(RuntimeError):
        tb.reserve(seat="b", role="builder", amount_usd=0.2)


def test_concurrent_reserves_do_not_overspend(tmp_path: Path):
    tb = TeamBudget(tmp_path / "b.sqlite", team_id="t1", budget_usd=1.0)
    errors: list[str] = []
    ok = []

    def worker(seat: str) -> None:
        try:
            tb.reserve(seat=seat, role="builder", amount_usd=0.6)
            ok.append(seat)
        except RuntimeError as exc:
            errors.append(str(exc))

    threads = [threading.Thread(target=worker, args=(f"s{i}",)) for i in range(3)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert len(ok) == 1
    assert len(errors) == 2
    snap = tb.snapshot()
    assert snap["reserved_usd"] <= 1.0 + 1e-9
