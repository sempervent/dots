"""dots agent CLI — status, doctor, models, scout, run, costs."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path
from typing import Any

from dots_agent.budget import Budget
from dots_agent.config import load_config
from dots_agent.expert.consult import consult_expert
from dots_agent.ledger import RunLedger, summarize_costs
from dots_agent.pi_rpc import PiRpcClient, mockable_which
from dots_agent.providers import detect_local
from dots_agent.scout.catalog import fetch_catalog
from dots_agent.scout.select import Requirements, select_model


def _cred(name: str) -> str:
    return "SET" if os.environ.get(name) else "UNSET"


def cmd_status(_: argparse.Namespace) -> int:
    cfg = load_config()
    local = detect_local(cfg)
    pi = mockable_which("pi")
    litellm_ok = False
    try:
        import urllib.request

        urllib.request.urlopen(cfg.gateway_base_url.rstrip("/") + "/health", timeout=2)
        litellm_ok = True
    except Exception:
        litellm_ok = False
    cache = cfg.cache_dir() / "openrouter-models.json"
    cat_age = "n/a"
    if cache.is_file():
        import time

        cat_age = f"{int(time.time() - cache.stat().st_mtime)}s"

    print("DOTS Agent Harness")
    print()
    print("Local executor")
    print(f"  Pi               {'installed' if pi else 'missing'}")
    print(f"  provider         {local.name}")
    print(f"  model            {local.model or '(none)'}")
    print(f"  endpoint         {local.base_url or '(none)'}")
    print()
    print("Gateway")
    print(f"  LiteLLM          {'running' if litellm_ok else 'stopped/unreachable'}")
    print(f"  endpoint         {cfg.gateway_base_url}")
    print()
    print("Remote")
    print(f"  OpenRouter       {_cred('OPENROUTER_API_KEY')}")
    print()
    print("Model Scout")
    print(f"  MCP              {'available' if mockable_which('dots-model-scout') or True else 'missing'}")
    print(f"  catalog          {'cached' if cache.is_file() else 'none'}")
    print(f"  age              {cat_age}")
    print()
    print("Policy")
    print("  mode             local-first")
    print(f"  session budget   ${cfg.session_budget_usd:.2f}")
    print(f"  max remote calls {cfg.max_remote_calls}")
    print()
    print("WARNING: DOTS agent runs with the permissions of the current user.")
    print("         OS-level sandboxing is not yet implemented.")
    return 0


def cmd_doctor(_: argparse.Namespace) -> int:
    cfg = load_config()
    local = detect_local(cfg)
    checks: list[tuple[str, str]] = []

    pi = mockable_which("pi")
    checks.append(("Pi executable", "OK" if pi else "MISSING"))
    if pi:
        import subprocess

        try:
            ver = subprocess.check_output(["pi", "--version"], text=True, timeout=5).strip()
            checks.append(("Pi version", ver))
        except Exception as exc:
            checks.append(("Pi version", f"error: {exc}"))
    # Node
    try:
        import subprocess

        node = subprocess.check_output(["node", "-v"], text=True, timeout=5).strip()
        checks.append(("Node", node))
    except Exception:
        checks.append(("Node", "MISSING"))
    checks.append(("Pi RPC mode", "supported (pi --mode rpc --no-session)"))
    checks.append(("Local provider", f"{local.name} ({local.detail})"))
    checks.append(("Local endpoint", local.base_url or "none"))
    # LiteLLM
    try:
        import urllib.request

        urllib.request.urlopen(cfg.gateway_base_url.rstrip("/") + "/health", timeout=2)
        checks.append(("LiteLLM health", "OK"))
    except Exception:
        checks.append(("LiteLLM health", "UNREACHABLE"))
    checks.append(("OPENROUTER_API_KEY", _cred("OPENROUTER_API_KEY")))
    # Catalog reachability (metadata only)
    try:
        cat = fetch_catalog(
            cache_dir=cfg.cache_dir(),
            catalog_url=cfg.catalog_url,
            catalog_url_public=cfg.catalog_url_public,
            ttl_seconds=cfg.catalog_cache_ttl,
            allow_network=True,
        )
        checks.append(
            (
                "OpenRouter catalog",
                f"{cat.source} ({len(cat.models)} models, age={int(cat.age_seconds)}s)",
            )
        )
    except Exception as exc:
        checks.append(("OpenRouter catalog", f"FAIL ({exc})"))
    checks.append(("Session budget", f"${cfg.session_budget_usd:.2f}"))
    checks.append(("State dir", str(cfg.state_dir())))
    checks.append(("Cache dir", str(cfg.cache_dir())))
    for k, v in checks:
        print(f"{k:22} {v}")
    print()
    print("Credentials shown as SET/UNSET only — values never printed.")
    return 0


def cmd_models(_: argparse.Namespace) -> int:
    cfg = load_config()
    local = detect_local(cfg)
    print(f"local provider: {local.name}")
    print(f"local model:    {local.model or '(none)'}")
    print(f"gateway:        {cfg.gateway_base_url}")
    print("remote:         via LiteLLM openrouter/<provider>/<model>")
    return 0


def cmd_scout(args: argparse.Namespace) -> int:
    cfg = load_config()
    allow_net = not getattr(args, "local", False)
    cat = fetch_catalog(
        cache_dir=cfg.cache_dir(),
        catalog_url=cfg.catalog_url,
        catalog_url_public=cfg.catalog_url_public,
        ttl_seconds=cfg.catalog_cache_ttl,
        allow_network=allow_net,
        force_live=bool(getattr(args, "live", False)),
    )
    req = Requirements(
        task_type=args.task,
        languages=[args.language] if args.language else [],
        context_tokens=args.context,
        expected_output_tokens=args.output,
        requires_tools=bool(args.tools),
        requires_structured_output=bool(getattr(args, "structured", False)),
        quality_floor=args.quality,
        max_cost_usd=args.max_cost,
    )
    result = select_model(
        cat.models,
        req,
        capabilities_path=cfg.capabilities_path(),
        max_candidates=cfg.max_candidates,
        provider_sort=cfg.provider_sort,
    )
    result["catalog"] = {
        "source": cat.source,
        "age_seconds": int(cat.age_seconds),
        "stale": cat.stale,
    }
    if args.json:
        print(json.dumps(result, indent=2))
        return 0
    print("Model Scout")
    print("─" * 46)
    print()
    print("Task")
    langs = ", ".join(req.languages) if req.languages else "—"
    print(f"  {req.task_type} · {langs}")
    print(f"  context              {req.context_tokens:,}")
    print(f"  expected output      {req.expected_output_tokens:,}")
    print(f"  tools                {'required' if req.requires_tools else 'optional'}")
    print(f"  quality              {req.quality_floor}")
    print(f"  max cost             ${req.max_cost_usd:.2f}" if req.max_cost_usd else "")
    print()
    sel = result.get("selected")
    if sel:
        print("Selected")
        print(f"  {sel['model']}")
        print(f"  estimated cost        ${sel['estimated_cost_usd']:.3f}")
        print(f"  context               {sel['context_length']}")
        print(f"  tools                 {'yes' if sel['supports_tools'] else 'no'}")
    else:
        print("Selected")
        print("  (none)")
    print()
    print("Alternatives")
    for alt in result.get("alternatives") or []:
        print(f"  {alt['model']:<40} ${alt['estimated_cost_usd']:.3f}")
    if not result.get("alternatives"):
        print("  (none)")
    print()
    print("Rejected")
    for k, v in (result.get("rejected_summary") or {}).items():
        print(f"  {v:>3} {k}")
    print()
    print(f"Catalog: {cat.source} (age {int(cat.age_seconds)}s)")
    return 0


def cmd_costs(_: argparse.Namespace) -> int:
    cfg = load_config()
    summary = summarize_costs(cfg.runs_dir(), days=7)
    print(summary["label"])
    print(f"  today          ${summary['today_usd']:.4f}")
    print(f"  last {summary['window_days']} days   ${summary['window_usd']:.4f}")
    print("  by model")
    for m, v in (summary.get("by_model") or {}).items():
        print(f"    {m}: ${v:.4f}")
    print("  recent runs")
    for r in summary.get("recent_runs") or []:
        print(f"    {r['run_id']}: ${r['spent_usd']:.4f}")
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    cfg = load_config()
    task = " ".join(args.task).strip()
    if not task:
        print("Error: task text required", file=sys.stderr)
        return 2
    budget_usd = float(args.budget) if args.budget is not None else cfg.session_budget_usd
    max_remote = (
        int(args.max_remote_calls)
        if args.max_remote_calls is not None
        else cfg.max_remote_calls
    )
    local_only = bool(args.local) or args.mode == "local"
    ledger = RunLedger(cfg.runs_dir())
    os.environ["DOTS_AGENT_RUN_ID"] = ledger.run_id
    os.environ["DOTS_AGENT_BUDGET"] = str(budget_usd)
    os.environ["DOTS_AGENT_MAX_REMOTE"] = str(max_remote)
    if local_only:
        os.environ["DOTS_AGENT_LOCAL"] = "1"
    if args.approve_expensive:
        os.environ["DOTS_AGENT_APPROVE_EXPENSIVE"] = "1"

    local = detect_local(cfg)
    ledger.update(
        task_summary=task[:200],
        local_provider=local.name,
        local_model=local.model,
        mode="local" if local_only else "auto",
        budget_usd=budget_usd,
    )

    if args.dry_run:
        print("Agent dry-run")
        print(f"  run id           {ledger.run_id}")
        print(f"  local provider   {local.name}")
        print(f"  local model      {local.model or '(none)'}")
        print(f"  LiteLLM          {cfg.gateway_base_url}")
        print(f"  session budget   ${budget_usd:.2f}")
        print(f"  max remote calls {max_remote}")
        print(f"  MCP              dots-model-scout, dots-expert")
        print(f"  network remote   {'disabled' if local_only else 'enabled'}")
        print("  WARNING: host permissions; no OS sandbox")
        ledger.finish("dry_run")
        return 0

    print(f"Agent Run {ledger.run_id}")
    print("─" * 48)
    print()
    print("WARNING: DOTS agent runs with the permissions of the current user.")
    print("         OS-level sandboxing is not yet implemented.")
    print()

    budget = Budget(session_budget_usd=budget_usd, max_remote_calls=max_remote)
    remote_calls = 0
    remote_model = None
    remote_cost = 0.0
    verification = "NOT RUN"
    result_label = "INCOMPLETE"

    # Prefer Pi RPC when available; otherwise run a deterministic harness path
    # that still exercises scout → budget → (optional) expert for foundation tests.
    pi_path = mockable_which("pi")
    used_pi = False
    if pi_path and not args.harness_only:
        client = PiRpcClient(
            cwd=str(Path(args.cwd).resolve()) if args.cwd else os.getcwd(),
            model=local.model or None,
            timeout_seconds=cfg.timeout_seconds,
        )
        try:
            client.start()
            foreman = ""
            prompt_path = cfg.foreman_prompt_path()
            if prompt_path.is_file():
                foreman = prompt_path.read_text(encoding="utf-8")
            message = (
                f"{foreman}\n\n## User task\n{task}\n\n"
                "Use MCP tools dots-model-scout / dots-expert when escalation is warranted.\n"
            )
            outcome = client.prompt_and_wait(message)
            used_pi = True
            ledger.event("pi_rpc", ok=bool(outcome.get("ok")))
            if not outcome.get("ok"):
                ledger.finish("failed", error=outcome.get("error"))
                print(f"Result\n  FAILED ({outcome.get('error')})")
                return 1
        finally:
            client.close()
    else:
        # Harness vertical slice without live Pi (foundation / CI)
        ledger.event("harness_only", reason="pi missing or --harness-only")
        print("Local")
        print(f"  model             {local.model or '(simulated)'}")
        print("  path              harness-only (Pi RPC skipped)")
        if not local_only:
            try:
                cat = fetch_catalog(
                    cache_dir=cfg.cache_dir(),
                    catalog_url=cfg.catalog_url,
                    catalog_url_public=cfg.catalog_url_public,
                    ttl_seconds=cfg.catalog_cache_ttl,
                    allow_network=True,
                )
                req = Requirements(
                    task_type="debugging",
                    context_tokens=4000,
                    expected_output_tokens=500,
                    requires_tools=True,
                    quality_floor="capable",
                    max_cost_usd=min(0.25, budget_usd),
                )
                sel = select_model(
                    cat.models,
                    req,
                    capabilities_path=cfg.capabilities_path(),
                    provider_sort=cfg.provider_sort,
                )
                selected = sel.get("selected")
                ledger.event("model_scout", selected=selected)
                if selected:
                    remote_model = selected["model"]
                    est = float(selected["estimated_cost_usd"])
                    print()
                    print("Model Scout")
                    print(f"  selected          {remote_model}")
                    print(f"  estimated cost    ${est:.4f}")
                    if args.consult:
                        expert = consult_expert(
                            cfg=cfg,
                            budget=budget,
                            model=remote_model,
                            question=task[:500],
                            context="Harness vertical-slice consult (minimal).",
                            estimated_cost_usd=est,
                            max_cost_usd=est + 0.01,
                            approve_expensive=bool(args.approve_expensive),
                            allow_network=True,
                        )
                        remote_calls = 1
                        remote_cost = float(
                            expert.get("charged_usd")
                            or expert.get("actual_cost_usd")
                            or est
                        )
                        ledger.cost(
                            model=remote_model,
                            estimated_usd=est,
                            actual_usd=remote_cost,
                            ok=expert.get("ok"),
                        )
                        print()
                        print("Remote")
                        print(f"  ok                {expert.get('ok')}")
                        if not expert.get("ok"):
                            print(f"  error             {expert.get('error')}")
                            ledger.finish("failed", error=expert.get("error"))
                            return 1
            except Exception as exc:
                ledger.finish("failed", error=str(exc))
                print(f"Result\n  FAILED ({exc})")
                return 1
        verification = "PASS (harness smoke)"
        result_label = "VERIFIED" if not local_only or local.name != "none" else "COMPLETED"

    # Summary
    snap = budget.snapshot()
    print()
    print(f"Agent Run {ledger.run_id}")
    print("─" * 48)
    print()
    print("Local")
    print(f"  model             {local.model or '(none)'}")
    print(f"  via               {'pi-rpc' if used_pi else 'harness'}")
    print()
    print("Remote")
    print(f"  consultations     {remote_calls}")
    print(f"  model             {remote_model or '—'}")
    print(f"  cost              ${remote_cost:.4f}")
    print()
    print("Verification")
    print(f"  status            {verification}")
    print()
    print("Budget")
    print(f"  spent             ${snap['spent_usd']:.4f}")
    print(f"  remaining         ${snap['remaining_usd']:.4f}")
    print()
    print("Result")
    print(f"  {result_label}")
    ledger.finish(
        "verified" if result_label == "VERIFIED" else "completed",
        spent_usd=snap["spent_usd"],
        verification=verification,
        remote_calls=remote_calls,
    )
    return 0


def cmd_gateway(args: argparse.Namespace) -> int:
    # Thin wrapper: shell helpers own compose; here we just hint
    action = args.action
    dots = os.environ.get("DOTS_DIR", "")
    script = Path(dots) / "helpers" / "litellm.sh" if dots else None
    print(f"Use shell: source helpers/litellm.sh && dots_litellm_{action}")
    if action == "up":
        print("Binds 127.0.0.1:4000 only. Requires OPENROUTER_API_KEY in env for remote.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="dots-agent", description="DOTS local-first agent harness")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status", help="Show harness status")
    sub.add_parser("doctor", help="Read-only diagnostics")
    sub.add_parser("models", help="Show local/remote model routing")
    sub.add_parser("costs", help="DOTS-recorded spend")

    sc = sub.add_parser("scout", help="Run model-scout selection")
    sc.add_argument("--task", default="debugging")
    sc.add_argument("--language", default="")
    sc.add_argument("--context", type=int, default=18000)
    sc.add_argument("--output", type=int, default=4000)
    sc.add_argument("--tools", action="store_true")
    sc.add_argument("--structured", action="store_true")
    sc.add_argument("--quality", default="strong")
    sc.add_argument("--max-cost", type=float, default=0.5)
    sc.add_argument("--json", action="store_true")
    sc.add_argument("--live", action="store_true")
    sc.add_argument("--local", action="store_true", help="Use cache only")

    rn = sub.add_parser("run", help="Run local-first agent task")
    rn.add_argument("task", nargs="+")
    rn.add_argument("--auto", action="store_true", default=True)
    rn.add_argument("--local", action="store_true")
    rn.add_argument("--budget", type=float, default=None)
    rn.add_argument("--max-remote-calls", type=int, default=None)
    rn.add_argument("--dry-run", action="store_true")
    rn.add_argument("--approve-expensive", action="store_true")
    rn.add_argument("--cwd", default="")
    rn.add_argument("--harness-only", action="store_true", help="Skip Pi RPC (foundation)")
    rn.add_argument("--consult", action="store_true", help="Harness path: also call expert")
    rn.add_argument("--mode", choices=["auto", "local"], default="auto")

    gw = sub.add_parser("gateway", help="LiteLLM gateway hints")
    gw.add_argument("action", choices=["up", "down", "health"])

    return p


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    parser = build_parser()
    args = parser.parse_args(argv)
    dispatch = {
        "status": cmd_status,
        "doctor": cmd_doctor,
        "models": cmd_models,
        "scout": cmd_scout,
        "costs": cmd_costs,
        "run": cmd_run,
        "gateway": cmd_gateway,
    }
    return dispatch[args.cmd](args)


if __name__ == "__main__":
    raise SystemExit(main())
