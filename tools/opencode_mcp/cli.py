#!/usr/bin/env python3
"""CLI entry for ~/.local/bin/opencode-agent."""

from __future__ import annotations

import argparse
import json
import sys

from adapter import list_agents, list_models, run_opencode, status_info


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="opencode-agent",
        description="DOTS OpenCode execution adapter (stable CLI over `opencode run`).",
    )
    sub = p.add_subparsers(dest="command", required=True)

    run_p = sub.add_parser("run", help="Run a coding task via OpenCode")
    run_p.add_argument(
        "--dir",
        required=True,
        help="Working directory (required; must exist)",
    )
    run_p.add_argument("--prompt", required=True, help="Task / prompt text")
    run_p.add_argument("--model", default=None, help="Override provider/model")
    run_p.add_argument("--agent", default=None, help="Override agent (e.g. build, plan)")
    run_p.add_argument(
        "--timeout",
        type=int,
        default=None,
        help="Timeout seconds (default from execution.toml)",
    )
    run_p.add_argument(
        "--auto",
        action="store_true",
        help="Pass opencode --auto (auto-approve allowed permissions)",
    )
    run_p.add_argument(
        "--attach",
        default=None,
        help="Attach to opencode serve URL (optional server mode)",
    )
    run_p.add_argument(
        "--no-json-format",
        action="store_true",
        help="Do not pass --format json to opencode",
    )
    run_p.add_argument(
        "--raw",
        action="store_true",
        help="Include raw JSON events in output",
    )

    sub.add_parser("status", help="Adapter / OpenCode status")
    sub.add_parser("list-models", help="List OpenCode models")
    sub.add_parser("list-agents", help="List OpenCode agents")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "status":
        print(json.dumps(status_info(), indent=2))
        return 0
    if args.command == "list-models":
        data = list_models()
        print(json.dumps(data, indent=2))
        return 0 if data.get("ok") else 1
    if args.command == "list-agents":
        data = list_agents()
        print(json.dumps(data, indent=2))
        return 0 if data.get("ok") else 1
    if args.command == "run":
        try:
            result = run_opencode(
                prompt=args.prompt,
                cwd=args.dir,
                model=args.model,
                agent=args.agent,
                timeout_seconds=args.timeout,
                auto_approve=True if args.auto else None,
                attach=args.attach,
                format_json=not args.no_json_format,
            )
        except ValueError as exc:
            print(json.dumps({"success": False, "error": str(exc)}, indent=2))
            return 2
        except RuntimeError as exc:
            print(json.dumps({"success": False, "error": str(exc)}, indent=2))
            return 127
        payload = result.to_dict()
        if not args.raw:
            payload.pop("raw_events", None)
        print(json.dumps(payload, indent=2))
        if result.success:
            return 0
        if result.timed_out:
            return 124
        return result.exit_code if result.exit_code > 0 else 1
    return 2


if __name__ == "__main__":
    sys.exit(main())
