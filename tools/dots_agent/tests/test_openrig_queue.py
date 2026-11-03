"""Queue wrapper tests (mocked subprocess — no paid providers)."""

from __future__ import annotations

from dots_agent.openrig import queue as Q


def test_parse_queue_table():
    text = """Task Owner State
implement parser fix builder@triad working
review parser fix reviewer@triad blocked
"""
    rows = Q.parse_queue_table(text)
    assert len(rows) >= 2
    assert rows[0]["state"] == "working"


def test_list_tasks_without_rig(monkeypatch):
    monkeypatch.setattr(Q.shutil, "which", lambda _: None)
    result = Q.list_tasks()
    assert result["exit"] == 127
    assert result["ok"] is False


def test_restore_check_unavailable(monkeypatch):
    monkeypatch.setattr(Q.shutil, "which", lambda _: None)
    result = Q.restore_check()
    assert result["state"] == "unavailable"
