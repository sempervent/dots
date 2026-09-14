#!/usr/bin/env python3
"""CLI entry: agent-telemetry / agent-stats."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Allow running from repo without install
_ROOT = Path(__file__).resolve().parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from dots_telemetry.config import db_path, load_config, telemetry_enabled  # noqa: E402
from dots_telemetry.db import connect, doctor  # noqa: E402
from dots_telemetry.record import (  # noqa: E402
    finish_execution,
    prune,
    record_route,
    reset_database,
    start_execution,
)
from dots_telemetry.stats import format_human, recent, stats_summary  # noqa: E402


def cmd_doctor(_: argparse.Namespace) -> int:
    info = doctor()
    print(json.dumps(info, indent=2))
    return 0 if info.get("ok") else 1


def cmd_route(args: argparse.Namespace) -> int:
    eid = record_route(
        category=args.category,
        destination=args.destination,
        reason=args.reason,
        user_override=args.override,
        degraded=args.degraded,
        escalation=args.escalation,
        note=args.note,
    )
    print(eid or "")
    return 0 if eid else 1


def cmd_start(args: argparse.Namespace) -> int:
    eid = start_execution(
        backend=args.backend,
        task_kind=args.kind,
        task_label=args.label,
        model=args.model,
        cwd=args.cwd,
        tool=args.tool,
        agent=args.agent,
        local_or_cloud=args.local_or_cloud,
    )
    print(eid or "")
    return 0 if eid else 1


def cmd_finish(args: argparse.Namespace) -> int:
    ok = finish_execution(
        args.id,
        success=args.success,
        result_status=args.status,
        exit_code=args.exit_code,
        timed_out=args.timeout,
        model=args.model,
        input_tokens=args.input_tokens,
        output_tokens=args.output_tokens,
        total_tokens=args.total_tokens,
        reported_cost_usd=args.reported_cost,
        estimated_cost_usd=args.estimated_cost,
        escalated=args.escalated,
        escalation_from=args.escalation_from,
        escalation_to=args.escalation_to,
        escalation_reason=args.escalation_reason,
    )
    return 0 if ok else 1


def cmd_prune(args: argparse.Namespace) -> int:
    result = prune(args.days)
    print(json.dumps(result, indent=2))
    return 0


def cmd_reset(args: argparse.Namespace) -> int:
    if not args.yes:
        print("Refusing to reset without --yes", file=sys.stderr)
        return 2
    ok = reset_database()
    print("reset" if ok else "failed")
    return 0 if ok else 1


def cmd_recent(args: argparse.Namespace) -> int:
    rows = recent(args.limit)
    print(json.dumps(rows, indent=2))
    return 0


def cmd_stats(args: argparse.Namespace) -> int:
    days = None
    if args.today:
        days = 1
    elif args.week:
        days = 7
    elif args.days is not None:
        days = args.days
    summary = stats_summary(
        days=days,
        backend=args.backend,
        failures_only=args.failures,
        escalations_only=args.escalations,
    )
    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print(format_human(summary))
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="agent-telemetry",
        description="DOTS private local agent telemetry (no cloud transmission).",
    )
    sub = p.add_subparsers(dest="command", required=True)

    sub.add_parser("doctor", help="Validate config + DB").set_defaults(func=cmd_doctor)

    rp = sub.add_parser("route", help="Record a routing decision")
    rp.add_argument("--category", required=True)
    rp.add_argument("--destination", required=True)
    rp.add_argument("--reason", required=True)
    rp.add_argument("--override", action="store_true")
    rp.add_argument("--degraded", action="store_true")
    rp.add_argument("--escalation", default=None)
    rp.add_argument("--note", default=None)
    rp.set_defaults(func=cmd_route)

    sp = sub.add_parser("record-start", help="Start an execution record")
    sp.add_argument("--backend", required=True)
    sp.add_argument("--kind", default=None)
    sp.add_argument("--label", default=None)
    sp.add_argument("--model", default=None)
    sp.add_argument("--cwd", default=None)
    sp.add_argument("--tool", default=None)
    sp.add_argument("--agent", default=None)
    sp.add_argument("--local-or-cloud", default=None)
    sp.set_defaults(func=cmd_start)

    fp = sub.add_parser("record-finish", help="Finish an execution record")
    fp.add_argument("--id", required=True)
    fp.add_argument("--success", type=lambda s: s.lower() in {"1", "true", "yes"}, default=None)
    fp.add_argument("--status", default=None)
    fp.add_argument("--exit-code", type=int, default=None)
    fp.add_argument("--timeout", action="store_true")
    fp.add_argument("--model", default=None)
    fp.add_argument("--input-tokens", type=int, default=None)
    fp.add_argument("--output-tokens", type=int, default=None)
    fp.add_argument("--total-tokens", type=int, default=None)
    fp.add_argument("--reported-cost", type=float, default=None)
    fp.add_argument("--estimated-cost", type=float, default=None)
    fp.add_argument("--escalated", action="store_true")
    fp.add_argument("--escalation-from", default=None)
    fp.add_argument("--escalation-to", default=None)
    fp.add_argument("--escalation-reason", default=None)
    fp.set_defaults(func=cmd_finish)

    pp = sub.add_parser("prune", help="Delete records older than retention")
    pp.add_argument("--days", type=int, default=None)
    pp.set_defaults(func=cmd_prune)

    zp = sub.add_parser("reset", help="Delete local telemetry database")
    zp.add_argument("--yes", action="store_true")
    zp.set_defaults(func=cmd_reset)

    rp2 = sub.add_parser("recent", help="Recent executions (JSON)")
    rp2.add_argument("--limit", type=int, default=20)
    rp2.set_defaults(func=cmd_recent)

    st = sub.add_parser("stats", help="Human summary (same as agent-stats)")
    st.add_argument("--today", action="store_true")
    st.add_argument("--week", action="store_true")
    st.add_argument("--days", type=int, default=None)
    st.add_argument("--backend", default=None)
    st.add_argument("--failures", action="store_true")
    st.add_argument("--escalations", action="store_true")
    st.add_argument("--json", action="store_true")
    st.set_defaults(func=cmd_stats)

    return p


def main(argv: list[str] | None = None) -> int:
    # Support being invoked as agent-stats
    prog = Path(sys.argv[0]).name if argv is None else "agent-telemetry"
    if prog == "agent-stats" or (argv and argv[:1] == ["stats"]):
        # agent-stats → stats subcommand
        if argv is None:
            argv = ["stats", *sys.argv[1:]]
        elif argv[:1] != ["stats"]:
            argv = ["stats", *argv]
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
