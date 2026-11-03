"""Inspect / timeline / failures / attention / metrics over local ledgers."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any


def _load_run(run_dir: Path) -> dict[str, Any]:
    meta: dict[str, Any] = {}
    mp = run_dir / "run.json"
    if mp.is_file():
        meta = json.loads(mp.read_text(encoding="utf-8"))
    events = []
    ep = run_dir / "events.jsonl"
    if ep.is_file():
        for line in ep.read_text(encoding="utf-8").splitlines():
            if line.strip():
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    ckpt = None
    cp = run_dir / "checkpoint.json"
    if cp.is_file():
        ckpt = json.loads(cp.read_text(encoding="utf-8"))
    return {"meta": meta, "events": events, "checkpoint": ckpt, "run_dir": str(run_dir)}


def inspect_run(runs_dir: Path, run_id: str) -> dict[str, Any]:
    d = runs_dir / run_id
    if not d.is_dir():
        return {"ok": False, "error": "not_found", "run_id": run_id}
    data = _load_run(d)
    data["ok"] = True
    data["run_id"] = run_id
    return data


def timeline(runs_dir: Path, run_id: str) -> list[dict[str, Any]]:
    data = inspect_run(runs_dir, run_id)
    if not data.get("ok"):
        return []
    rows = []
    for ev in data.get("events") or []:
        rows.append(
            {
                "ts": ev.get("ts"),
                "kind": ev.get("kind"),
                "summary": _summarize(ev),
            }
        )
    return rows


def _summarize(ev: dict[str, Any]) -> str:
    kind = str(ev.get("kind") or "")
    if kind == "failure":
        return f"failure domain={ev.get('domain')} fp={ev.get('fingerprint')}"
    if kind == "recovery_decision":
        return f"recovery action={ev.get('action')} applied={ev.get('applied')}"
    if kind == "attention":
        return f"attention: {ev.get('reason')}"
    if kind == "route_decision":
        return f"route evidence={ev.get('evidence_source')}"
    return kind


def list_failures(runs_dir: Path, *, limit: int = 50) -> list[dict[str, Any]]:
    out = []
    if not runs_dir.is_dir():
        return out
    for run_dir in sorted(runs_dir.iterdir(), reverse=True):
        if not run_dir.is_dir():
            continue
        ep = run_dir / "events.jsonl"
        if not ep.is_file():
            continue
        for line in ep.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if ev.get("kind") == "failure":
                out.append({"run_id": run_dir.name, **ev})
                if len(out) >= limit:
                    return out
    return out


def list_attention(runs_dir: Path, *, limit: int = 50) -> list[dict[str, Any]]:
    out = []
    if not runs_dir.is_dir():
        return out
    for run_dir in sorted(runs_dir.iterdir(), reverse=True):
        if not run_dir.is_dir():
            continue
        ep = run_dir / "events.jsonl"
        if not ep.is_file():
            continue
        for line in ep.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if ev.get("kind") == "attention":
                out.append({"run_id": run_dir.name, **ev})
                if len(out) >= limit:
                    return out
    return out


def metrics(runs_dir: Path) -> dict[str, Any]:
    domains: Counter[str] = Counter()
    actions: Counter[str] = Counter()
    outcomes: Counter[str] = Counter()
    attention = 0
    runs = 0
    if runs_dir.is_dir():
        for run_dir in runs_dir.iterdir():
            if not run_dir.is_dir():
                continue
            runs += 1
            meta_p = run_dir / "run.json"
            if meta_p.is_file():
                try:
                    meta = json.loads(meta_p.read_text(encoding="utf-8"))
                    outcomes[str(meta.get("status") or "unknown")] += 1
                except json.JSONDecodeError:
                    pass
            ep = run_dir / "events.jsonl"
            if not ep.is_file():
                continue
            for line in ep.read_text(encoding="utf-8").splitlines():
                if not line.strip():
                    continue
                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if ev.get("kind") == "failure":
                    domains[str(ev.get("domain") or "unknown")] += 1
                if ev.get("kind") == "recovery_decision":
                    actions[str(ev.get("action") or "unknown")] += 1
                if ev.get("kind") == "attention":
                    attention += 1
    return {
        "runs": runs,
        "outcomes": dict(outcomes),
        "failure_domains": dict(domains),
        "recovery_actions": dict(actions),
        "attention_events": attention,
    }


def cancel_run(runs_dir: Path, run_id: str) -> dict[str, Any]:
    d = runs_dir / run_id
    if not d.is_dir():
        return {"ok": False, "error": "not_found"}
    meta_p = d / "run.json"
    meta = {}
    if meta_p.is_file():
        meta = json.loads(meta_p.read_text(encoding="utf-8"))
    meta["status"] = "cancelled"
    meta["cancelled"] = True
    meta_p.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    ep = d / "events.jsonl"
    with ep.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps({"kind": "cancel", "ts": meta.get("finished_at")}) + "\n")
    # Marker for watchers
    (d / "CANCEL").write_text("1\n", encoding="utf-8")
    return {"ok": True, "run_id": run_id, "status": "cancelled"}
