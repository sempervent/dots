"""Eval registry loading tests."""

from __future__ import annotations

from pathlib import Path

from dots_agent.evals.registry import filter_tasks, load_registry

ROOT = Path(__file__).resolve().parents[3]
REG = ROOT / "configs" / "agents" / "evals" / "registry.toml"


def test_registry_loads_and_counts():
    tasks = load_registry(REG)
    assert 20 <= len(tasks) <= 40
    by = {}
    for t in tasks:
        by[t.task_class] = by.get(t.task_class, 0) + 1
    for cls in (
        "coding",
        "debugging",
        "reasoning",
        "tool_use",
        "structured_output",
        "repo_navigation",
    ):
        assert by.get(cls, 0) >= 3, cls


def test_smoke_filter():
    tasks = load_registry(REG)
    smoke = filter_tasks(tasks, suite="smoke")
    assert 1 <= len(smoke) <= 12
    assert all("smoke" in t.suites for t in smoke)


def test_task_ids_unique():
    tasks = load_registry(REG)
    ids = [t.id for t in tasks]
    assert len(ids) == len(set(ids))


def test_scorers_deterministic_types():
    tasks = load_registry(REG)
    allowed = {"command", "filesystem", "json_exact", "json_schema"}
    for t in tasks:
        assert t.scorer.get("type") in allowed
