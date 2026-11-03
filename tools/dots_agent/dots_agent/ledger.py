"""Run ledger — metadata only; never stores secrets or full prompts by default."""

from __future__ import annotations

import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_SECRET_RE = re.compile(
    r"(?i)(api[_-]?key|token|password|secret|authorization|bearer)\s*[:=]\s*\S+"
)


def new_run_id() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]


def redact_text(text: str) -> str:
    return _SECRET_RE.sub(r"\1=***", text)


class RunLedger:
    def __init__(self, runs_dir: Path, run_id: str | None = None) -> None:
        self.run_id = run_id or new_run_id()
        self.dir = runs_dir / self.run_id
        self.dir.mkdir(parents=True, exist_ok=True)
        self.run_path = self.dir / "run.json"
        self.events_path = self.dir / "events.jsonl"
        self.costs_path = self.dir / "costs.jsonl"
        self._meta: dict[str, Any] = {
            "run_id": self.run_id,
            "started_at": datetime.now(timezone.utc).isoformat(),
            "status": "running",
        }
        self._write_meta()

    def _write_meta(self) -> None:
        self.run_path.write_text(json.dumps(self._meta, indent=2) + "\n", encoding="utf-8")

    def update(self, **kwargs: Any) -> None:
        for k, v in kwargs.items():
            if isinstance(v, str):
                v = redact_text(v)
            self._meta[k] = v
        self._write_meta()

    def event(self, kind: str, **payload: Any) -> None:
        row = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "kind": kind,
            **{k: (redact_text(v) if isinstance(v, str) else v) for k, v in payload.items()},
        }
        with self.events_path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(row) + "\n")

    def cost(self, **payload: Any) -> None:
        row = {
            "ts": datetime.now(timezone.utc).isoformat(),
            **{k: (redact_text(v) if isinstance(v, str) else v) for k, v in payload.items()},
        }
        # Never persist key-like fields
        for ban in ("api_key", "authorization", "token", "OPENROUTER_API_KEY"):
            row.pop(ban, None)
        with self.costs_path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(row) + "\n")

    def finish(self, status: str, **kwargs: Any) -> None:
        self.update(
            status=status,
            finished_at=datetime.now(timezone.utc).isoformat(),
            **kwargs,
        )


def summarize_costs(runs_dir: Path, *, days: int = 7) -> dict[str, Any]:
    """Aggregate DOTS-recorded spend from local ledgers."""
    from datetime import timedelta

    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    today = datetime.now(timezone.utc).date().isoformat()
    total = 0.0
    today_total = 0.0
    by_model: dict[str, float] = {}
    recent: list[dict[str, Any]] = []
    if not runs_dir.is_dir():
        return {
            "label": "DOTS-recorded spend",
            "today_usd": 0.0,
            "window_days": days,
            "window_usd": 0.0,
            "by_model": {},
            "recent_runs": [],
        }
    for run_dir in sorted(runs_dir.iterdir(), reverse=True):
        costs = run_dir / "costs.jsonl"
        meta_path = run_dir / "run.json"
        run_spend = 0.0
        model = None
        if costs.is_file():
            for line in costs.read_text(encoding="utf-8").splitlines():
                if not line.strip():
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                amt = float(row.get("actual_usd") or row.get("estimated_usd") or 0)
                run_spend += amt
                m = row.get("model")
                if m:
                    by_model[m] = by_model.get(m, 0.0) + amt
                    model = m
                ts = row.get("ts", "")
                if ts.startswith(today):
                    today_total += amt
                try:
                    dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                    if dt >= cutoff:
                        total += amt
                except Exception:
                    total += amt
        elif meta_path.is_file():
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
                run_spend = float(meta.get("spent_usd") or 0)
                total += run_spend
            except Exception:
                pass
        recent.append(
            {
                "run_id": run_dir.name,
                "spent_usd": round(run_spend, 6),
                "model": model,
            }
        )
        if len(recent) >= 10:
            break
    return {
        "label": "DOTS-recorded spend",
        "today_usd": round(today_total, 6),
        "window_days": days,
        "window_usd": round(total, 6),
        "by_model": {k: round(v, 6) for k, v in sorted(by_model.items(), key=lambda x: -x[1])},
        "recent_runs": recent,
    }
