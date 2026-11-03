"""CLI handlers for inspect/timeline/failures/attention/metrics/cancel/replay/resume."""

from __future__ import annotations

import json
from typing import Any

from dots_agent.autonomy.observability import (
    cancel_run,
    inspect_run,
    list_attention,
    list_failures,
    metrics,
    timeline,
)
from dots_agent.autonomy.replay import replay_run
from dots_agent.autonomy.resume import ResumeError, resume_run
from dots_agent.config import load_config


def cmd_inspect(args: Any) -> int:
    cfg = load_config()
    data = inspect_run(cfg.runs_dir(), args.run_id)
    if getattr(args, "json", False) or True:
        print(json.dumps(data, indent=2, default=str))
    return 0 if data.get("ok") else 1


def cmd_timeline(args: Any) -> int:
    cfg = load_config()
    rows = timeline(cfg.runs_dir(), args.run_id)
    if getattr(args, "json", False):
        print(json.dumps(rows, indent=2))
        return 0
    print(f"Timeline {args.run_id}")
    print("─" * 40)
    for r in rows:
        print(f"  {r.get('ts', ''):<28} {r.get('kind', ''):<18} {r.get('summary', '')}")
    if not rows:
        print("  (empty)")
    return 0


def cmd_failures(args: Any) -> int:
    cfg = load_config()
    rows = list_failures(cfg.runs_dir(), limit=int(getattr(args, "limit", 50) or 50))
    if getattr(args, "json", False):
        print(json.dumps(rows, indent=2))
        return 0
    print(f"{'Run':<28} {'Domain':<20} Fingerprint")
    for r in rows:
        print(
            f"{r.get('run_id', ''):<28} {str(r.get('domain', '')):<20} {r.get('fingerprint', '')}"
        )
    if not rows:
        print("(no failures recorded)")
    return 0


def cmd_attention(args: Any) -> int:
    cfg = load_config()
    rows = list_attention(cfg.runs_dir(), limit=int(getattr(args, "limit", 50) or 50))
    if getattr(args, "json", False):
        print(json.dumps(rows, indent=2))
        return 0
    print("Human attention")
    print("─" * 40)
    for r in rows:
        print(f"  {r.get('run_id')}: {r.get('reason')}")
    if not rows:
        print("  (none)")
    return 0


def cmd_metrics(_: Any) -> int:
    cfg = load_config()
    m = metrics(cfg.runs_dir())
    print("DOTS Agent Metrics")
    print("─" * 40)
    print(f"  runs              {m['runs']}")
    print(f"  attention events  {m['attention_events']}")
    print("  outcomes")
    for k, v in (m.get("outcomes") or {}).items():
        print(f"    {k}: {v}")
    print("  failure domains")
    for k, v in (m.get("failure_domains") or {}).items():
        print(f"    {k}: {v}")
    print("  recovery actions")
    for k, v in (m.get("recovery_actions") or {}).items():
        print(f"    {k}: {v}")
    return 0


def cmd_cancel(args: Any) -> int:
    cfg = load_config()
    result = cancel_run(cfg.runs_dir(), args.run_id)
    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


def cmd_replay(args: Any) -> int:
    cfg = load_config()
    result = replay_run(cfg.runs_dir(), args.run_id)
    print("DOTS Agent Replay (offline)")
    print("─" * 40)
    print(f"  run               {result.run_id}")
    print(f"  model calls       {result.model_calls}")
    print(f"  network calls     {result.network_calls}")
    print(f"  billable calls    {result.billable_calls}")
    print(f"  mutations         {result.mutations}")
    print(f"  decisions         {len(result.decisions)}")
    if getattr(args, "json", False):
        print(json.dumps(result.to_dict(), indent=2))
    else:
        for d in result.decisions[:20]:
            print(
                f"    {d.get('domain')} → {d.get('action')} (fp={d.get('fingerprint')})"
            )
    # Hard guarantee
    assert result.model_calls == 0
    assert result.network_calls == 0
    assert result.billable_calls == 0
    assert result.mutations == 0
    return 0


def cmd_resume(args: Any) -> int:
    cfg = load_config()
    try:
        resumed = resume_run(cfg.runs_dir(), args.run_id)
    except ResumeError as exc:
        print(f"REFUSED: {exc}")
        return 2
    print("Resume")
    print("─" * 40)
    print(f"  run               {resumed.run_id}")
    print(f"  autonomy          {resumed.autonomy_mode.value}")
    print(f"  policy_version    {resumed.policy_version}")
    snap = resumed.budget.snapshot()
    print(f"  budget spent      ${snap['spent_usd']:.4f}")
    print(f"  budget remaining  ${snap['remaining_usd']:.4f}")
    print(f"  remote calls      {snap['remote_call_count']}/{snap['max_remote_calls']}")
    print(f"  retries           {resumed.counters.transient_retries}")
    print(f"  replans           {resumed.counters.local_replans}")
    print(f"  expert escalations {resumed.counters.expert_escalations}")
    if resumed.pending_billable:
        print("  pending billable  RECONCILIATION may be required")
    print("  (allowances NOT refreshed)")
    if getattr(args, "json", False):
        print(
            json.dumps(
                {
                    "run_id": resumed.run_id,
                    "budget": snap,
                    "counters": resumed.counters.to_dict(),
                    "pending_billable": resumed.pending_billable,
                },
                indent=2,
            )
        )
    return 0
