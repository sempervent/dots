"""Eval runner classification tests (mock solver; no paid APIs)."""

from __future__ import annotations

from pathlib import Path

from dots_agent.evals.registry import load_registry
from dots_agent.evals.runner import MockSolver, ModelIdentity, RunOptions, run_suite
from dots_agent.evals.storage import EvalStore
from dots_agent.evals.types import AttemptStatus

ROOT = Path(__file__).resolve().parents[3]
REG = ROOT / "configs" / "agents" / "evals" / "registry.toml"


def test_oracle_smoke_passes(tmp_path: Path):
    tasks = load_registry(REG)
    store = EvalStore(tmp_path / "evals")
    result = run_suite(
        tasks,
        repo_root=ROOT,
        store=store,
        solver=MockSolver(mode="oracle"),
        identity=ModelIdentity(model_id="mock/oracle", provider="mock"),
        options=RunOptions(suite="smoke", runs_per_task=1, sandbox_available=True),
    )
    assert result.refused is None
    assert result.attempts
    # Most smoke tasks should pass with oracle
    passed = sum(1 for a in result.attempts if a.passed)
    assert passed >= max(1, len(result.attempts) // 2)


def test_fail_solver_model_fail(tmp_path: Path):
    tasks = [t for t in load_registry(REG) if t.id == "json-person"]
    store = EvalStore(tmp_path / "evals")
    result = run_suite(
        tasks,
        repo_root=ROOT,
        store=store,
        solver=MockSolver(mode="fail"),
        identity=ModelIdentity(model_id="mock/fail", provider="mock"),
        options=RunOptions(suite="full", runs_per_task=1, task_ids=["json-person"]),
    )
    assert result.attempts
    assert result.attempts[0].status == AttemptStatus.MODEL_FAIL.value


def test_harness_error(tmp_path: Path):
    tasks = [t for t in load_registry(REG) if t.id == "json-person"]
    store = EvalStore(tmp_path / "evals")
    result = run_suite(
        tasks,
        repo_root=ROOT,
        store=store,
        solver=MockSolver(mode="raise_harness"),
        identity=ModelIdentity(model_id="mock/h", provider="mock"),
        options=RunOptions(suite="full", task_ids=["json-person"]),
    )
    assert result.attempts[0].status == AttemptStatus.HARNESS_ERROR.value


def test_remote_budget_refuse(tmp_path: Path):
    tasks = load_registry(REG)
    store = EvalStore(tmp_path / "evals")
    result = run_suite(
        tasks,
        repo_root=ROOT,
        store=store,
        solver=MockSolver(mode="oracle"),
        identity=ModelIdentity(model_id="openrouter/x", provider="openrouter"),
        options=RunOptions(
            suite="standard",
            runs_per_task=1,
            remote=True,
            budget_usd=0.001,
        ),
        per_remote_task_estimate=0.05,
    )
    assert result.refused is not None
    assert "budget" in result.refused.lower() or "exceeds" in result.refused.lower()


def test_sandbox_fail_closed(tmp_path: Path):
    tasks = [t for t in load_registry(REG) if t.id == "python-off-by-one"]
    store = EvalStore(tmp_path / "evals")
    result = run_suite(
        tasks,
        repo_root=ROOT,
        store=store,
        solver=MockSolver(mode="oracle"),
        identity=ModelIdentity(model_id="mock/x", provider="mock"),
        options=RunOptions(
            suite="full",
            task_ids=["python-off-by-one"],
            sandbox_available=False,
            require_sandbox_for_mutation=True,
        ),
    )
    assert result.attempts == []
    assert result.skipped
    assert result.skipped[0]["reason"] == "sandbox_unavailable_fail_closed"


def test_workdir_not_repo(tmp_path: Path):
    tasks = [t for t in load_registry(REG) if t.id == "json-person"]
    store = EvalStore(tmp_path / "evals")
    result = run_suite(
        tasks,
        repo_root=ROOT,
        store=store,
        solver=MockSolver(mode="oracle"),
        identity=ModelIdentity(model_id="mock/x", provider="mock"),
        options=RunOptions(suite="full", task_ids=["json-person"], preserve_workdir=True),
    )
    assert result.attempts
    wd = result.attempts[0].model_config.get("workdir")
    if wd:
        assert Path(wd).resolve() != ROOT.resolve()
