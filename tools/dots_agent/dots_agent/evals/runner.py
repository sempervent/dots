"""Eval runner — isolated fixtures, deterministic scorers, mock-friendly solvers."""

from __future__ import annotations

import json
import os
import shutil
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Protocol

from dots_agent.budget import Budget
from dots_agent.evals.registry import EvalTask, filter_tasks, fixtures_root
from dots_agent.evals.scorers import score_task
from dots_agent.evals.storage import AttemptRecord, EvalStore, SCHEMA_VERSION
from dots_agent.evals.types import AttemptStatus


class Solver(Protocol):
    def solve(self, task: EvalTask, work_dir: Path) -> dict[str, Any]:
        """Mutate work_dir toward a solution. Return metadata."""


@dataclass
class MockSolver:
    """Applies known-good patches from fixture `_oracle/` when present."""

    mode: str = "oracle"  # oracle | fail | noop | raise_harness
    delay_seconds: float = 0.0

    def solve(self, task: EvalTask, work_dir: Path) -> dict[str, Any]:
        if self.delay_seconds:
            time.sleep(self.delay_seconds)
        if self.mode == "raise_harness":
            raise RuntimeError("mock harness failure")
        if self.mode == "noop":
            return {"iterations": 0, "tool_calls": 0, "input_tokens": 0, "output_tokens": 0}
        if self.mode == "fail":
            # Leave broken / write wrong answer
            bad = work_dir / "answer.json"
            if task.scorer.get("type") in ("json_exact", "json_schema"):
                bad.write_text('{"wrong": true}\n', encoding="utf-8")
            return {
                "iterations": 1,
                "tool_calls": 0,
                "input_tokens": 10,
                "output_tokens": 10,
            }
        oracle = work_dir / "_oracle"
        # Oracle may live beside fixture source — copied into work_dir by runner
        if oracle.is_dir():
            for src in oracle.rglob("*"):
                if src.is_file():
                    rel = src.relative_to(oracle)
                    dest = work_dir / rel
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(src, dest)
            # Honour expected.missing (e.g. rename tasks)
            for rel in task.expected.get("missing") or []:
                p = work_dir / str(rel)
                if p.exists():
                    p.unlink() if p.is_file() else shutil.rmtree(p)
            # Remove oracle from agent-visible tree after apply
            shutil.rmtree(oracle, ignore_errors=True)
            marker = work_dir / ".renamed"
            if marker.is_file():
                marker.unlink()
            return {
                "iterations": 1,
                "tool_calls": 1,
                "input_tokens": 100,
                "output_tokens": 50,
                "estimated_cost_usd": 0.0,
            }
        # Heuristic: if expected equals present for json tasks, write it
        if task.scorer.get("type") in ("json_exact", "json_schema"):
            path = work_dir / str(task.scorer.get("path") or "answer.json")
            if "equals" in task.expected:
                path.write_text(
                    json.dumps(task.expected["equals"], indent=2) + "\n",
                    encoding="utf-8",
                )
                return {
                    "iterations": 1,
                    "tool_calls": 0,
                    "input_tokens": 50,
                    "output_tokens": 20,
                }
        return {"iterations": 0, "tool_calls": 0}


@dataclass
class ModelIdentity:
    model_id: str
    provider: str = "mock"
    quantization: str = ""
    backend: str = ""
    context_config: str = ""
    temperature: float | None = 0.0
    seed: int | None = None


@dataclass
class RunOptions:
    suite: str = "standard"
    runs_per_task: int = 1
    task_class: str | None = None
    task_ids: list[str] | None = None
    remote: bool = False
    budget_usd: float | None = None
    preserve_workdir: bool = False
    require_sandbox_for_mutation: bool = True
    sandbox_available: bool = True


@dataclass
class EvalRunResult:
    eval_run_id: str
    attempts: list[AttemptRecord] = field(default_factory=list)
    skipped: list[dict[str, Any]] = field(default_factory=list)
    refused: str | None = None


def _prereq_missing(task: EvalTask) -> str | None:
    for name in task.prerequisites:
        if name in ("python3", "python"):
            if shutil.which("python3") or shutil.which("python"):
                continue
            return name
        if name == "bash":
            if shutil.which("bash"):
                continue
            return name
        if name in ("cargo", "rustc", "go"):
            if shutil.which(name):
                continue
            return name
        if not shutil.which(name):
            return name
    return None


def _estimate_suite_cost_upper(
    tasks: list[EvalTask],
    *,
    runs: int,
    per_task_estimate: float,
) -> float:
    return len(tasks) * runs * max(0.0, per_task_estimate)


def prepare_workdir(fixture_src: Path, dest: Path) -> Path | None:
    """Copy fixture into dest. Returns hidden_dir if `_hidden` sibling exists."""
    if not fixture_src.is_dir():
        raise FileNotFoundError(fixture_src)
    shutil.copytree(fixture_src, dest, dirs_exist_ok=True)
    # Strip answers that must stay hidden from agent
    for name in ("_hidden",):
        p = dest / name
        if p.exists():
            shutil.rmtree(p)
    hidden_src = fixture_src / "_hidden"
    hidden_dir: Path | None = None
    if hidden_src.is_dir():
        hidden_dir = dest.parent / (dest.name + ".hidden")
        shutil.copytree(hidden_src, hidden_dir)
    return hidden_dir


def run_suite(
    tasks: list[EvalTask],
    *,
    repo_root: Path,
    store: EvalStore,
    solver: Solver,
    identity: ModelIdentity,
    options: RunOptions,
    per_remote_task_estimate: float = 0.05,
) -> EvalRunResult:
    selected = filter_tasks(
        tasks,
        suite=options.suite,
        task_class=options.task_class,
        task_ids=options.task_ids,
    )
    # Smoke: at most smoke_tasks_per_class (caller may pre-filter); keep as-is
    if options.suite == "smoke":
        by_class: dict[str, list[EvalTask]] = {}
        for t in selected:
            by_class.setdefault(t.task_class, []).append(t)
        selected = []
        for rows in by_class.values():
            selected.extend(rows[:1])

    run_id = store.new_run_id()
    result = EvalRunResult(eval_run_id=run_id)

    if options.remote:
        if options.budget_usd is None:
            result.refused = "remote eval requires --budget"
            return result
        upper = _estimate_suite_cost_upper(
            selected,
            runs=options.runs_per_task,
            per_task_estimate=per_remote_task_estimate,
        )
        if upper > float(options.budget_usd) + 1e-12:
            result.refused = (
                f"estimated upper bound ${upper:.4f} exceeds budget "
                f"${options.budget_usd:.4f}"
            )
            return result
        budget = Budget(
            session_budget_usd=float(options.budget_usd),
            max_remote_calls=len(selected) * options.runs_per_task,
        )
    else:
        budget = None

    fixtures = fixtures_root(repo_root)

    for task in selected:
        missing = _prereq_missing(task)
        if missing:
            result.skipped.append(
                {
                    "task_id": task.id,
                    "status": AttemptStatus.SKIPPED_PREREQUISITE.value,
                    "reason": missing,
                }
            )
            continue
        if task.sandbox and options.require_sandbox_for_mutation:
            if not options.sandbox_available:
                result.skipped.append(
                    {
                        "task_id": task.id,
                        "status": AttemptStatus.HARNESS_ERROR.value,
                        "reason": "sandbox_unavailable_fail_closed",
                    }
                )
                continue

        for _rep in range(options.runs_per_task):
            if budget is not None:
                try:
                    budget.reserve(per_remote_task_estimate)
                except RuntimeError:
                    rec = _attempt(
                        task,
                        identity,
                        run_id,
                        status=AttemptStatus.BUDGET_BLOCKED,
                        reason="budget exhausted",
                        duration=0.0,
                    )
                    store.append_attempt(rec)
                    result.attempts.append(rec)
                    continue

            tmp_root = Path(
                tempfile.mkdtemp(prefix="dots-eval-", dir=tempfile.gettempdir())
            )
            work = tmp_root / "work"
            fixture_src = fixtures / task.fixture
            started = time.time()
            status = AttemptStatus.HARNESS_ERROR
            reason = ""
            meta: dict[str, Any] = {}
            scorer_summary = ""
            try:
                hidden = prepare_workdir(fixture_src, work)
                # Never evaluate against the live checkout path
                assert work.resolve() != repo_root.resolve()
                meta = solver.solve(task, work) or {}
                scored = score_task(
                    work,
                    task.scorer,
                    task.expected,
                    hidden_dir=hidden,
                )
                scorer_summary = str(scored.get("summary") or "")
                st = str(scored.get("status") or "MODEL_FAIL")
                status = AttemptStatus(st)
                if not scored.get("passed") and status is AttemptStatus.PASS:
                    status = AttemptStatus.MODEL_FAIL
                reason = "" if status is AttemptStatus.PASS else scorer_summary
            except TimeoutError:
                status = AttemptStatus.TIMEOUT
                reason = "timeout"
            except Exception as exc:  # noqa: BLE001 — classify harness vs model
                status = AttemptStatus.HARNESS_ERROR
                reason = str(exc)
            duration = time.time() - started
            # Soft timeout classification when solver exceeds task budget
            if duration > task.timeout_seconds and status is AttemptStatus.PASS:
                status = AttemptStatus.TIMEOUT
                reason = "TIMEOUT"

            est = meta.get("estimated_cost_usd")
            actual = meta.get("actual_cost_usd")
            if identity.provider in ("local", "mock", "ollama", "llamacpp"):
                cost_source = "local_zero"
                if est is None:
                    est = 0.0
                if actual is None:
                    actual = 0.0
            elif actual is not None:
                cost_source = "actual"
            else:
                cost_source = "estimated"

            if budget is not None:
                charged = float(actual if actual is not None else (est or 0.0))
                budget.settle(per_remote_task_estimate, charged)

            rec = _attempt(
                task,
                identity,
                run_id,
                status=status,
                reason=reason,
                duration=duration,
                started=started,
                meta=meta,
                scorer_summary=scorer_summary,
                estimated=est if est is not None else None,
                actual=actual if actual is not None else None,
                cost_source=cost_source,
            )
            store.append_attempt(rec)
            result.attempts.append(rec)

            if not options.preserve_workdir:
                shutil.rmtree(tmp_root, ignore_errors=True)
            else:
                rec.model_config["workdir"] = str(work)

    return result


def _attempt(
    task: EvalTask,
    identity: ModelIdentity,
    run_id: str,
    *,
    status: AttemptStatus,
    reason: str,
    duration: float,
    started: float | None = None,
    meta: dict[str, Any] | None = None,
    scorer_summary: str = "",
    estimated: float | None = None,
    actual: float | None = None,
    cost_source: str = "estimated",
) -> AttemptRecord:
    meta = meta or {}
    return AttemptRecord(
        schema_version=SCHEMA_VERSION,
        eval_run_id=run_id,
        task_id=task.id,
        model_id=identity.model_id,
        provider=identity.provider,
        task_class=task.task_class,
        language=task.language,
        difficulty=task.difficulty,
        started_at=started or time.time(),
        duration_seconds=duration,
        status=status.value,
        passed=status is AttemptStatus.PASS,
        failure_reason=reason,
        input_tokens=int(meta.get("input_tokens") or 0),
        output_tokens=int(meta.get("output_tokens") or 0),
        estimated_cost_usd=estimated,
        actual_cost_usd=actual,
        cost_source=cost_source,
        tool_calls=int(meta.get("tool_calls") or 0),
        iterations=int(meta.get("iterations") or 0),
        scorer_summary=scorer_summary or reason,
        temperature=identity.temperature,
        seed=identity.seed,
        quantization=identity.quantization,
        backend=identity.backend,
        context_config=identity.context_config,
        model_config={},
    )


def oracle_available(task: EvalTask, repo_root: Path) -> bool:
    root = fixtures_root(repo_root) / task.fixture / "_oracle"
    return root.is_dir() or task.scorer.get("type") in ("json_exact", "json_schema")
