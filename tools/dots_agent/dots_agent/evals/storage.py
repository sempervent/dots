"""Persist eval attempts under XDG state."""

from __future__ import annotations

import json
import time
import uuid
from collections import defaultdict
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Iterator

from dots_agent.evals.types import AttemptStatus, counts_toward_success, is_success
from dots_agent.stats import summarize_binomial


SCHEMA_VERSION = 1


@dataclass
class AttemptRecord:
    schema_version: int
    eval_run_id: str
    task_id: str
    model_id: str
    provider: str
    task_class: str
    language: str
    difficulty: str
    started_at: float
    duration_seconds: float
    status: str
    passed: bool
    failure_reason: str
    input_tokens: int
    output_tokens: int
    estimated_cost_usd: float | None
    actual_cost_usd: float | None
    cost_source: str  # actual | estimated | local_zero
    tool_calls: int
    iterations: int
    scorer_summary: str
    temperature: float | None
    seed: int | None
    quantization: str
    backend: str
    context_config: str
    model_config: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> AttemptRecord:
        return cls(
            schema_version=int(d.get("schema_version") or SCHEMA_VERSION),
            eval_run_id=str(d.get("eval_run_id") or ""),
            task_id=str(d.get("task_id") or ""),
            model_id=str(d.get("model_id") or ""),
            provider=str(d.get("provider") or ""),
            task_class=str(d.get("task_class") or ""),
            language=str(d.get("language") or ""),
            difficulty=str(d.get("difficulty") or ""),
            started_at=float(d.get("started_at") or 0),
            duration_seconds=float(d.get("duration_seconds") or 0),
            status=str(d.get("status") or AttemptStatus.HARNESS_ERROR.value),
            passed=bool(d.get("passed")),
            failure_reason=str(d.get("failure_reason") or ""),
            input_tokens=int(d.get("input_tokens") or 0),
            output_tokens=int(d.get("output_tokens") or 0),
            estimated_cost_usd=d.get("estimated_cost_usd"),
            actual_cost_usd=d.get("actual_cost_usd"),
            cost_source=str(d.get("cost_source") or "estimated"),
            tool_calls=int(d.get("tool_calls") or 0),
            iterations=int(d.get("iterations") or 0),
            scorer_summary=str(d.get("scorer_summary") or ""),
            temperature=d.get("temperature"),
            seed=d.get("seed"),
            quantization=str(d.get("quantization") or ""),
            backend=str(d.get("backend") or ""),
            context_config=str(d.get("context_config") or ""),
            model_config=dict(d.get("model_config") or {}),
        )


def model_evidence_key(
    model_id: str,
    *,
    quantization: str = "",
    backend: str = "",
) -> str:
    """Exact identity bucket — do not merge families or quant variants."""
    parts = [model_id.strip()]
    if quantization:
        parts.append(f"q={quantization}")
    if backend:
        parts.append(f"b={backend}")
    return "|".join(parts)


class EvalStore:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.runs_dir = root / "runs"
        self.summary_dir = root / "summary"
        self.baseline_path = root / "baseline.json"
        self.external_dir = root / "external"
        self.runs_dir.mkdir(parents=True, exist_ok=True)
        self.summary_dir.mkdir(parents=True, exist_ok=True)
        self.external_dir.mkdir(parents=True, exist_ok=True)

    def new_run_id(self) -> str:
        return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + "-" + uuid.uuid4().hex[:8]

    def append_attempt(self, record: AttemptRecord) -> Path:
        path = self.runs_dir / f"{record.eval_run_id}.jsonl"
        with path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(record.to_dict(), sort_keys=True) + "\n")
        self._update_summary(record)
        return path

    def _update_summary(self, record: AttemptRecord) -> None:
        key = model_evidence_key(
            record.model_id,
            quantization=record.quantization,
            backend=record.backend,
        )
        safe = key.replace("/", "__")
        path = self.summary_dir / f"{safe}.json"
        data: dict[str, Any]
        if path.is_file():
            data = json.loads(path.read_text(encoding="utf-8"))
        else:
            data = {
                "schema_version": SCHEMA_VERSION,
                "model_id": record.model_id,
                "quantization": record.quantization,
                "backend": record.backend,
                "by_class": {},
                "updated_at": 0,
            }
        by = data.setdefault("by_class", {})
        row = by.setdefault(
            record.task_class,
            {
                "attempts": 0,
                "successes": 0,
                "latencies": [],
                "costs": [],
            },
        )
        if counts_toward_success(record.status):
            row["attempts"] = int(row.get("attempts") or 0) + 1
            if is_success(record.status):
                row["successes"] = int(row.get("successes") or 0) + 1
            row.setdefault("latencies", []).append(record.duration_seconds)
            cost = record.actual_cost_usd
            if cost is None:
                cost = record.estimated_cost_usd
            if cost is not None:
                row.setdefault("costs", []).append(float(cost))
            # Cap stored lists
            row["latencies"] = list(row["latencies"])[-200:]
            row["costs"] = list(row["costs"])[-200:]
            summary = summarize_binomial(int(row["successes"]), int(row["attempts"]))
            row["raw_success_rate"] = summary.raw_rate
            row["conservative_success_rate"] = summary.wilson_lower
        data["updated_at"] = time.time()
        path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    def iter_attempts(self, run_id: str | None = None) -> Iterator[AttemptRecord]:
        paths: list[Path]
        if run_id:
            paths = [self.runs_dir / f"{run_id}.jsonl"]
        else:
            paths = sorted(self.runs_dir.glob("*.jsonl"))
        for path in paths:
            if not path.is_file():
                continue
            for line in path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line:
                    continue
                yield AttemptRecord.from_dict(json.loads(line))

    def results_table(
        self,
        *,
        task_class: str | None = None,
        max_age_days: float | None = None,
    ) -> list[dict[str, Any]]:
        now = time.time()
        agg: dict[tuple[str, str], dict[str, Any]] = {}
        for rec in self.iter_attempts():
            if task_class and rec.task_class != task_class:
                continue
            if max_age_days is not None and rec.started_at:
                age_days = (now - rec.started_at) / 86400.0
                if age_days > max_age_days:
                    continue
            if not counts_toward_success(rec.status):
                continue
            key = (rec.model_id, rec.task_class)
            row = agg.setdefault(
                key,
                {
                    "model": rec.model_id,
                    "class": rec.task_class,
                    "attempts": 0,
                    "successes": 0,
                    "latencies": [],
                },
            )
            row["attempts"] += 1
            if is_success(rec.status):
                row["successes"] += 1
            row["latencies"].append(rec.duration_seconds)
        out = []
        for row in agg.values():
            s = summarize_binomial(row["successes"], row["attempts"])
            lats = sorted(row["latencies"])
            median = lats[len(lats) // 2] if lats else None
            p90 = lats[int(0.9 * (len(lats) - 1))] if len(lats) >= 5 else None
            out.append(
                {
                    "model": row["model"],
                    "class": row["class"],
                    "attempts": row["attempts"],
                    "successes": row["successes"],
                    "raw_success_rate": s.raw_rate,
                    "conservative_success_rate": s.wilson_lower,
                    "median_latency": median,
                    "p90_latency": p90,
                }
            )
        out.sort(key=lambda r: (r["class"], r["model"]))
        return out

    def set_baseline(self, run_id: str) -> None:
        path = self.runs_dir / f"{run_id}.jsonl"
        if not path.is_file():
            raise FileNotFoundError(run_id)
        self.baseline_path.write_text(
            json.dumps({"run_id": run_id, "set_at": time.time()}, indent=2) + "\n",
            encoding="utf-8",
        )

    def get_baseline_run_id(self) -> str | None:
        if not self.baseline_path.is_file():
            return None
        data = json.loads(self.baseline_path.read_text(encoding="utf-8"))
        return str(data.get("run_id") or "") or None

    def detect_regressions(
        self,
        *,
        current_run_id: str | None = None,
        min_attempts: int = 5,
        drop_threshold: float = 0.2,
    ) -> list[dict[str, Any]]:
        baseline_id = self.get_baseline_run_id()
        if not baseline_id:
            return []
        if current_run_id is None:
            runs = sorted(self.runs_dir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime)
            if not runs:
                return []
            current_run_id = runs[-1].stem

        def by_model_class(run_id: str) -> dict[tuple[str, str], tuple[int, int]]:
            counts: dict[tuple[str, str], list[int]] = defaultdict(lambda: [0, 0])
            for rec in self.iter_attempts(run_id):
                if not counts_toward_success(rec.status):
                    continue
                key = (rec.model_id, rec.task_class)
                counts[key][0] += 1
                if is_success(rec.status):
                    counts[key][1] += 1
            return {k: (v[0], v[1]) for k, v in counts.items()}

        base = by_model_class(baseline_id)
        cur = by_model_class(current_run_id)
        findings: list[dict[str, Any]] = []
        for key, (b_n, b_ok) in base.items():
            if b_n < min_attempts:
                continue
            c_n, c_ok = cur.get(key, (0, 0))
            if c_n < min_attempts:
                continue
            b_rate = b_ok / b_n
            c_rate = c_ok / c_n
            if b_rate - c_rate >= drop_threshold:
                findings.append(
                    {
                        "model": key[0],
                        "class": key[1],
                        "baseline_run": baseline_id,
                        "current_run": current_run_id,
                        "baseline_rate": b_rate,
                        "current_rate": c_rate,
                        "drop": b_rate - c_rate,
                        "baseline_n": b_n,
                        "current_n": c_n,
                    }
                )
        return findings
