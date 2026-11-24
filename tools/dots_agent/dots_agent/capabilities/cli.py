"""CLI for skills, MCP, runtime, and the capability inventory."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from dots_agent.capabilities.inventory import build_inventory, doctor_lines, render_human
from dots_agent.capabilities.load import dots_root, known_mcp_ids, known_skill_ids, mcp_rows, skill_rows
from dots_agent.capabilities.mcp_plane import audit_registry, doctor_row, permissions, search_registry
from dots_agent.capabilities.runtime import resolve_node, satisfies_constraint
from dots_agent.capabilities.skills import (
    apply_update,
    audit_skill,
    installed_skill_dir,
    manifest_errors,
    source_for,
    update_plan,
)


def _print_secret_safe(text: str) -> None:
    for name in ("OPENROUTER_API_KEY", "GITHUB_TOKEN"):
        value = os.environ.get(name)
        if value and value in text:
            text = text.replace(value, "SET")
    print(text, end="" if text.endswith("\n") else "\n")


def cmd_capabilities(json_out: bool) -> int:
    doc = build_inventory()
    if json_out:
        _print_secret_safe(json.dumps(doc, indent=2) + "\n")
    else:
        _print_secret_safe(render_human(doc))
    return 0


def cmd_runtimes() -> int:
    consumers = {part.strip() for part in os.environ.get("DOTS_CAPABILITY_COMPONENTS", "skills,pi,openrig").split(",") if part.strip()}
    result = resolve_node(consumers, current=os.environ.get("DOTS_NODE_VERSION") or None)
    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


def cmd_skills(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="dots skills")
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("list")
    sub.add_parser("status")
    show = sub.add_parser("show")
    show.add_argument("name")
    find = sub.add_parser("find")
    find.add_argument("query")
    sub.add_parser("check")
    audit = sub.add_parser("audit")
    audit.add_argument("name", nargs="?")
    audit.add_argument("--strict", action="store_true")
    update = sub.add_parser("update")
    update.add_argument("name", nargs="?")
    update.add_argument("--plan", action="store_true")
    update.add_argument("--yes", action="store_true")
    update.add_argument("--candidate", default="")
    known = sub.add_parser("known")
    known.add_argument("name")
    args = parser.parse_args(argv)
    rows = skill_rows()
    if args.action == "known":
        return 0 if args.name in known_skill_ids() else 1
    if args.action == "list":
        for row in rows:
            print(f"{row['name']}\t{row.get('group')}\t{row.get('source') or row.get('source_id')}")
        return 0
    if args.action == "status":
        for row in rows:
            name = str(row["name"])
            installed = installed_skill_dir(name)
            state = "installed" if installed else "missing"
            if installed and name not in os.environ.get("DOTS_CAPABILITY_SKILLS", name):
                state = "installed/inactive"
            print(f"{name}\t{state}")
        return 0
    if args.action == "show":
        row = next((r for r in rows if r.get("name") == args.name), None)
        if row is None:
            print(f"unknown skill: {args.name}", file=sys.stderr)
            return 1
        src = source_for(row)
        print(args.name)
        print(f"  source   {src.get('repo') or row.get('source')}")
        print(f"  ref      {src.get('ref') or '(unpinned)'}")
        print(f"  license  {src.get('license') or '(see source)'}")
        print(f"  group    {row.get('group')}")
        return 0
    if args.action == "find":
        for row in rows:
            blob = json.dumps(row).lower()
            if args.query.lower() in blob:
                print(row["name"])
        return 0
    if args.action == "check":
        errors = manifest_errors()
        for err in errors:
            print(err)
        return 1 if errors else 0
    if args.action == "audit":
        names = [args.name] if args.name else [str(r["name"]) for r in rows]
        errors = manifest_errors()
        warnings: list[str] = []
        for name in names:
            report = audit_skill(name)
            errors.extend(f"{name}: {item}" for item in report["errors"])
            warnings.extend(f"{name}: {item}" for item in report["warnings"])
        for item in errors:
            print(f"ERROR {item}")
        for item in warnings:
            print(f"WARN {item}")
        print(f"errors={len(errors)} warnings={len(warnings)}")
        if errors or (args.strict and warnings):
            return 1
        return 0
    if args.action == "update":
        candidate = Path(args.candidate or os.environ.get("DOTS_SKILL_CANDIDATE", ""))
        if not args.name or not candidate.is_dir():
            print("update requires NAME and --candidate DIR (staged; not a blind npx update)", file=sys.stderr)
            return 2
        if args.yes and not args.plan:
            result = apply_update(args.name, candidate)
        else:
            result = update_plan(args.name, candidate)
            result["apply"] = False
        print(f"Skill: {result['name']}")
        print("Current:")
        print(f"  source ref: {result.get('current_ref')}")
        print(f"  hash: {result.get('current_hash')}")
        print("Candidate:")
        print(f"  source ref: {result.get('candidate_ref')}")
        print(f"  hash: {result.get('candidate_hash')}")
        print("Changed:")
        for rel in result.get("changed") or []:
            print(f"  {rel}")
        review = result.get("review") or []
        print("Security review:")
        print("  CLEAN" if not review else "  FINDINGS")
        for item in review:
            print(f"  {item}")
        if result.get("errors"):
            print("Validation failed. Current skill was not replaced.")
            return 1
        if not args.yes:
            print("[update only after --yes]")
        return 0 if result.get("applied") or not args.yes else 1
    return 2


def cmd_mcp(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="dots mcp")
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("list")
    sub.add_parser("status")
    sub.add_parser("doctor")
    show = sub.add_parser("show")
    show.add_argument("server")
    search = sub.add_parser("search")
    search.add_argument("query")
    inspect = sub.add_parser("inspect")
    inspect.add_argument("server")
    for name in ("enable", "disable"):
        cmd = sub.add_parser(name)
        cmd.add_argument("server")
        cmd.add_argument("--profile", default="")
        cmd.add_argument("--dry-run", action="store_true")
        cmd.add_argument("--yes", action="store_true")
    plan = sub.add_parser("plan")
    plan.add_argument("--profile", default="")
    plan.add_argument("--dry-run", action="store_true")
    sync = sub.add_parser("sync")
    sync.add_argument("--profile", default="")
    sync.add_argument("--dry-run", action="store_true")
    audit_p = sub.add_parser("audit")
    audit_p.add_argument("--strict", action="store_true")
    known = sub.add_parser("known")
    known.add_argument("server")
    # The first audit parser was not added. audit_p is the real one.
    args = parser.parse_args(argv)
    rows = mcp_rows()
    if args.action == "known":
        return 0 if args.server in known_mcp_ids() else 1
    if args.action == "list":
        for row in rows:
            print(f"{row['id']}\t{row.get('transport') or 'stdio'}\t{row.get('trust')}")
        return 0
    if args.action == "show":
        row = next((r for r in rows if r.get("id") == args.server), None)
        if row is None:
            print(f"unknown mcp: {args.server}", file=sys.stderr)
            print("Discovery does not make a server curated. Review it into configs/agents/mcp-trust.toml.")
            return 1
        _print_mcp(row)
        return 0
    if args.action == "status":
        for row in rows:
            doc = doctor_row(row)
            auth = "AUTH REQUIRED" if doc["auth_required"] else "auth ok"
            print(f"{row['id']}\t{row.get('trust')}\t{auth}")
            for name, state in doc["auth"]["env"].items():
                print(f"  {name} {state}")
        return 0
    if args.action == "doctor":
        for row in rows:
            doc = doctor_row(row)
            print(row["id"])
            for check in doc["checks"]:
                print(f"  {check['check']}: {check['status']}")
        return 0
    if args.action == "search":
        result = search_registry(args.query)
        if result.get("error"):
            print(result["error"], file=sys.stderr)
            return 1
        print("Discovered servers are not trusted and were not installed.")
        for row in result["servers"]:
            print(f"{row['state']}\t{row['id']}\t{row.get('description')}")
        return 0
    if args.action == "inspect":
        result = search_registry(args.server)
        matches = [row for row in result.get("servers") or [] if row["id"] == args.server]
        curated = next((r for r in rows if r.get("id") == args.server), None)
        if curated:
            print("CURATED")
            _print_mcp(curated)
            return 0
        if not matches:
            print(f"not found: {args.server}", file=sys.stderr)
            return 1
        print("DISCOVERED")
        print(json.dumps(matches[0], indent=2))
        print("Inspect does not enable this server.")
        return 0
    if args.action in {"enable", "disable"}:
        if args.server not in known_mcp_ids():
            print(f"unknown mcp: {args.server}", file=sys.stderr)
            print("Only curated registry ids can be enabled.")
            return 1
        flag = "--add-mcp" if args.action == "enable" else "--remove-mcp"
        cmd = [str(dots_root() / "dots"), "profile", "mutate", flag, args.server]
        if args.profile:
            cmd.extend(["--profile", args.profile])
        if args.dry_run:
            cmd.append("--dry-run")
        if args.yes or args.dry_run:
            cmd.append("--yes")
        if os.environ.get("DOTS_MCP_MUTATE_ECHO") == "1":
            print(" ".join(cmd))
            return 0
        import subprocess

        proc = subprocess.run(cmd, check=False)
        return proc.returncode
    if args.action in {"plan", "sync"}:
        from dots_agent.capabilities.clients import sync_clients

        desired = [r for r in rows if r.get("safe_default") or r.get("id") in os.environ.get("DOTS_CAPABILITY_MCP", "").split(",")]
        result = sync_clients(desired, dry_run=args.dry_run or args.action == "plan")
        print(json.dumps(result, indent=2))
        return 0 if result.get("ok") else 1
    if args.action == "audit":
        report = audit_registry(rows)
        for item in report["errors"]:
            print(f"ERROR {item}")
        for item in report["warnings"]:
            print(f"WARN {item}")
        print(f"errors={len(report['errors'])} warnings={len(report['warnings'])}")
        if report["errors"] or (args.strict and report["warnings"]):
            return 1
        return 0
    return 2


def _print_mcp(row: dict) -> None:
    perms = permissions(row)
    print(row.get("label") or row["id"])
    print(f"  transport        {row.get('transport') or 'stdio'}")
    print(f"  trust            {row.get('trust')}")
    print("Trust")
    print(f"  network          {'yes' if perms['network'] else 'no'}")
    print(f"  filesystem read  {'yes' if perms['filesystem_read'] else 'no'}")
    print(f"  filesystem write {'yes' if perms['filesystem_write'] else 'no'}")
    print(f"  shell            {'yes' if perms['shell'] else 'no'}")
    print(f"  remote writes    {'yes' if perms['remote_write'] else 'no'}")
    print(f"  billable         {'yes' if perms['billable'] else 'no'}")
    print(f"  credentials      {row.get('auth_mode') or 'none'}")
    for name, state in doctor_row(row)["auth"]["env"].items():
        print(f"  {name} {state}")


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        return cmd_capabilities(False)
    head = argv[0]
    if head in {"-h", "--help"}:
        print("usage: dots agent capabilities | dots skills | dots mcp | dots check runtimes")
        return 0
    if head == "capabilities":
        return cmd_capabilities("--json" in argv[1:])
    if head == "runtimes":
        return cmd_runtimes()
    if head == "doctor":
        for key, value in doctor_lines():
            print(f"{key:28} {value}")
        return 0
    if head == "skills":
        return cmd_skills(argv[1:])
    if head == "mcp":
        return cmd_mcp(argv[1:])
    if head == "satisfies":
        return 0 if satisfies_constraint(argv[1], argv[2]) else 1
    print(f"unknown capabilities command: {head}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
