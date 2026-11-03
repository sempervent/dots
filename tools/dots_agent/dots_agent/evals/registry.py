"""Declarative eval task registry loader."""

from __future__ import annotations

import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


TASK_CLASSES = (
    "coding",
    "debugging",
    "reasoning",
    "tool_use",
    "structured_output",
    "repo_navigation",
    "architecture",
    "general",
)


@dataclass(frozen=True)
class EvalTask:
    id: str
    task_class: str
    language: str
    difficulty: str
    timeout_seconds: int
    max_output_tokens: int
    sandbox: bool
    suites: tuple[str, ...]
    fixture: str
    prompt: str
    prerequisites: tuple[str, ...]
    scorer: dict[str, Any]
    expected: dict[str, Any]
    tags: tuple[str, ...] = ()
    context_tokens: int = 4000

    @property
    def requires_tools(self) -> bool:
        return self.task_class in ("coding", "debugging", "tool_use", "repo_navigation")

    @property
    def requires_structured_output(self) -> bool:
        return self.task_class in ("structured_output", "reasoning", "repo_navigation")


def _as_tuple(v: Any) -> tuple[str, ...]:
    if v is None:
        return ()
    if isinstance(v, str):
        return (v,)
    return tuple(str(x) for x in v)


def load_registry(path: Path) -> list[EvalTask]:
    if not path.is_file():
        raise FileNotFoundError(f"eval registry missing: {path}")
    with path.open("rb") as fh:
        data = tomllib.load(fh)
    tasks: list[EvalTask] = []
    for row in data.get("tasks") or []:
        if not isinstance(row, dict):
            continue
        tid = str(row.get("id") or "").strip()
        if not tid:
            continue
        suites = _as_tuple(row.get("suite") or ("standard", "full"))
        tasks.append(
            EvalTask(
                id=tid,
                task_class=str(row.get("class") or "general"),
                language=str(row.get("language") or ""),
                difficulty=str(row.get("difficulty") or "basic"),
                timeout_seconds=int(row.get("timeout_seconds") or 60),
                max_output_tokens=int(row.get("max_output_tokens") or 1500),
                sandbox=bool(row.get("sandbox", True)),
                suites=suites,
                fixture=str(row.get("fixture") or ""),
                prompt=str(row.get("prompt") or "").strip(),
                prerequisites=_as_tuple(row.get("prerequisites")),
                scorer=dict(row.get("scorer") or {}),
                expected=dict(row.get("expected") or {}),
                tags=_as_tuple(row.get("tags")),
                context_tokens=int(row.get("context_tokens") or 4000),
            )
        )
    return tasks


def filter_tasks(
    tasks: list[EvalTask],
    *,
    suite: str | None = None,
    task_class: str | None = None,
    task_ids: list[str] | None = None,
) -> list[EvalTask]:
    out = list(tasks)
    if task_ids:
        want = set(task_ids)
        out = [t for t in out if t.id in want]
    if task_class:
        out = [t for t in out if t.task_class == task_class]
    if suite and suite != "full":
        out = [t for t in out if suite in t.suites]
    return out


def fixtures_root(repo_root: Path) -> Path:
    return repo_root / "tools" / "dots_agent" / "dots_agent" / "evals" / "fixtures"


def registry_path(repo_root: Path, rel: str | None = None) -> Path:
    rel = rel or "configs/agents/evals/registry.toml"
    return repo_root / rel
