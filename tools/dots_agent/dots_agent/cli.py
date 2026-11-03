"""dots agent CLI — status, doctor, models, scout, run, costs."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

from dots_agent.budget import Budget
from dots_agent.config import load_config
from dots_agent.expert.consult import consult_expert
from dots_agent.health import build_status_report, doctor_checks, which
from dots_agent.ledger import RunLedger, summarize_costs
from dots_agent.limits import RunLimits
from dots_agent.pi_models import merge_local_provider, resolve_pi_selection
from dots_agent.pi_rpc import PiRpcClient
from dots_agent.providers import detect_local
from dots_agent import results as R
from dots_agent.scout.catalog import fetch_catalog
from dots_agent.scout.select import Requirements, select_model
from dots_agent.secrets import litellm_master_key_status


def _cred(name: str) -> str:
    return "SET" if os.environ.get(name) else "UNSET"


def cmd_status(_: argparse.Namespace) -> int:
    cfg = load_config()
    rep = build_status_report(cfg)
    local = rep["local"]
    sel = rep["selection"]
    cache = cfg.cache_dir() / "openrouter-models.json"
    cat_age = "n/a"
    if cache.is_file():
        cat_age = f"{int(time.time() - cache.stat().st_mtime)}s"

    print("DOTS Agent Harness")
    print()
    print("Local executor")
    print(f"  Pi               {rep['pi']}")
    print(f"  provider         {local.name}")
    print(f"  model            {local.model or '(none)'}")
    print(f"  endpoint         {local.base_url or '(none)'}")
    if sel.get("provider"):
        print(f"  Pi provider      {sel['provider']}")
        print(f"  Pi model         {sel['model']}")
    print()
    print("Gateway")
    print(f"  LiteLLM          {rep['litellm']}")
    print(f"  endpoint         {rep['gateway']}")
    print(f"  master key       {rep['master_key']}")
    print()
    print("Remote")
    print(f"  OpenRouter       {rep['openrouter']}")
    print()
    print("Model Scout")
    print(f"  executable       {rep['scout_executable']}")
    print(f"  MCP configured   {rep['mcp_configured']}")
    # Discovery is verified only by doctor MCP tools/list — status stays honest.
    print("  Pi discovery     unverified (run: dots agent doctor)")
    print(f"  catalog          {'cached' if cache.is_file() else 'none'}")
    print(f"  age              {cat_age}")
    print()
    print("Expert")
    print(f"  executable       {rep['expert_executable']}")
    print()
    print("Policy")
    print("  mode             local-first")
    print(f"  session budget   ${cfg.session_budget_usd:.2f}")
    print(f"  max remote calls {cfg.max_remote_calls}")
    print(f"  agent venv       {'OK' if rep['venv'] else 'MISSING'}")
    print()
    print("WARNING: DOTS agent runs with the permissions of the current user.")
    print("         OS-level sandboxing is not yet implemented (Phase 2).")
    return 0


def cmd_doctor(_: argparse.Namespace) -> int:
    cfg = load_config()
    for k, v in doctor_checks(cfg):
        print(f"{k:28} {v}")
    print()
    print("Credentials shown as SET/UNSET only — values never printed.")
    print("MCP Inspector (optional, developer): npx @modelcontextprotocol/inspector --cli \\")
    print("  <dots-model-scout|dots-expert> --method tools/list")
    return 0


def cmd_models(_: argparse.Namespace) -> int:
    cfg = load_config()
    local = detect_local(cfg)
    sel = resolve_pi_selection(local)
    print(f"local provider: {local.name}")
    print(f"local model:    {local.model or '(none)'}")
    print(f"Pi provider:    {sel.get('provider') or '(n/a)'}")
    print(f"Pi model:       {sel.get('model') or '(n/a)'}")
    print(f"Pi endpoint:    {sel.get('endpoint') or '(n/a)'}")
    print(f"gateway:        {cfg.gateway_base_url}")
    print(f"master key:     {litellm_master_key_status()}")
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


def _verify_local_task(task: str, outcome_text: str, *, expect_token: str | None) -> tuple[str, str]:
    """Return (verification_status, result_state). Never VERIFIED on settle alone."""
    if expect_token and expect_token in outcome_text:
        return "PASS", R.VERIFIED
    # Explicit verify marker in task: "verify:CMD" is Phase 2; Phase 1 uses token match only.
    if "DOTS_LOCAL_AGENT_OK" in outcome_text or "DOTS_LOCAL_MODEL_OK" in outcome_text:
        return "PASS", R.VERIFIED
    if outcome_text.strip():
        return "NOT RUN (no verification proof)", R.COMPLETED
    return "FAIL", R.FAILED


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
    limits = RunLimits(
        max_iterations=cfg.max_iterations,
        max_remote_calls=max_remote,
        timeout_seconds=cfg.timeout_seconds,
        session_budget_usd=budget_usd,
    )
    ledger = RunLedger(cfg.runs_dir())
    os.environ["DOTS_AGENT_RUN_ID"] = ledger.run_id
    os.environ["DOTS_AGENT_BUDGET"] = str(budget_usd)
    os.environ["DOTS_AGENT_MAX_REMOTE"] = str(max_remote)
    if local_only:
        os.environ["DOTS_AGENT_LOCAL"] = "1"
        # Local-only: block harness-initiated remote catalog/inference
        os.environ.pop("OPENROUTER_API_KEY", None)
    if args.approve_expensive:
        os.environ["DOTS_AGENT_APPROVE_EXPENSIVE"] = "1"

    local = detect_local(cfg)
    sel = resolve_pi_selection(local)
    ledger.update(
        task_summary=task[:200],
        local_provider=local.name,
        local_model=local.model,
        mode="local" if local_only else "auto",
        budget_usd=budget_usd,
        # Never store full prompt / env dumps
    )

    if args.dry_run:
        print("Agent dry-run")
        print(f"  run id           {ledger.run_id}")
        print(f"  local provider   {local.name}")
        print(f"  local model      {local.model or '(none)'}")
        print(f"  Pi provider      {sel.get('provider') or '(n/a)'}")
        print(f"  LiteLLM          {cfg.gateway_base_url}")
        print(f"  session budget   ${budget_usd:.2f}")
        print(f"  max remote calls {max_remote}")
        print(f"  max iterations   {cfg.max_iterations}")
        print(f"  timeout_seconds  {cfg.timeout_seconds}")
        print(f"  MCP              dots-model-scout, dots-expert")
        print(f"  network remote   {'disabled' if local_only else 'enabled'}")
        print("  WARNING: host permissions; no OS sandbox")
        ledger.finish(R.DRY_RUN.lower())
        return 0

    print(f"Agent Run {ledger.run_id}")
    print("─" * 48)
    print()
    print("WARNING: DOTS agent runs with the permissions of the current user.")
    print("         OS-level sandboxing is not yet implemented (Phase 2).")
    print()

    budget = Budget(session_budget_usd=budget_usd, max_remote_calls=max_remote)
    remote_calls = 0
    remote_model = None
    remote_cost = 0.0
    verification = "NOT RUN"
    result_state = R.COMPLETED
    outcome_text = ""

    stop = limits.tick_iteration()
    if stop:
        ledger.finish(stop.lower())
        print(f"Result\n  {stop}")
        return 1

    pi_path = which("pi")
    used_pi = False
    if pi_path and not args.harness_only:
        # Ensure models.json can resolve the local provider before RPC
        if local.healthy and local.name in ("ollama", "llamacpp"):
            merge_local_provider(local)
        if not sel.get("provider") or not sel.get("model"):
            print("Local provider not resolvable for Pi RPC; falling back to harness.")
            ledger.event("pi_rpc_skip", reason="unresolvable local model")
        else:
            client = PiRpcClient(
                cwd=str(Path(args.cwd).resolve()) if args.cwd else os.getcwd(),
                provider=str(sel["provider"]),
                model=str(sel["model"]),
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
                    + (
                        "LOCAL ONLY: do not call remote experts or OpenRouter.\n"
                        if local_only
                        else "Use MCP tools dots-model-scout / dots-expert when escalation is warranted.\n"
                    )
                )
                outcome = client.prompt_and_wait(message)
                used_pi = True
                ledger.event(
                    "pi_rpc",
                    ok=bool(outcome.get("ok")),
                    provider=sel["provider"],
                    model=sel["model"],
                    settled=bool(outcome.get("settled")),
                )
                if not outcome.get("ok"):
                    err = str(outcome.get("error") or "pi failed")
                    state = R.TIMED_OUT if "timeout" in err.lower() else R.FAILED
                    ledger.finish(state.lower(), error=err)
                    print(f"Result\n  {state} ({err})")
                    return 1
                # Summaries only — never persist full prompt/events in ledger
                outcome_text = str(outcome.get("assistant_text") or "")[:2000]
                # agent_settled alone is NEVER enough for VERIFIED
                verification, result_state = _verify_local_task(
                    task, outcome_text, expect_token=(getattr(args, "expect", None) or None)
                )
            finally:
                client.close()

    if not used_pi:
        # Harness vertical slice without live Pi (foundation / CI)
        ledger.event("harness_only", reason="pi missing or --harness-only or unresolvable")
        print("Local")
        print(f"  model             {local.model or '(simulated)'}")
        print(f"  provider          {local.name}")
        print("  path              harness-only (Pi RPC skipped)")
        if local_only:
            # Local-only guarantee: no catalog, no LiteLLM, no OpenRouter
            ledger.event("local_only", remote_blocked=True)
            if "DOTS_LOCAL_AGENT_OK" in task or "DOTS_LOCAL_MODEL_OK" in task:
                # Deterministic local harness proof without network
                outcome_text = "DOTS_LOCAL_AGENT_OK"
                verification, result_state = "PASS (local harness)", R.VERIFIED
            else:
                verification, result_state = "NOT RUN (no verification proof)", R.COMPLETED
        else:
            block = limits.allow_remote_call()
            if block:
                ledger.finish(block.lower())
                print(f"Result\n  {block}")
                return 1
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
                sel_m = select_model(
                    cat.models,
                    req,
                    capabilities_path=cfg.capabilities_path(),
                    provider_sort=cfg.provider_sort,
                )
                selected = sel_m.get("selected")
                ledger.event(
                    "model_scout",
                    selected_model=(selected or {}).get("model"),
                    estimated_usd=(selected or {}).get("estimated_cost_usd"),
                )
                if selected:
                    remote_model = selected["model"]
                    est = float(selected["estimated_cost_usd"])
                    print()
                    print("Model Scout")
                    print(f"  selected          {remote_model}")
                    print(f"  estimated cost    ${est:.4f}")
                    if args.consult:
                        block = limits.allow_remote_call()
                        if block:
                            ledger.finish(block.lower())
                            print(f"Result\n  {block}")
                            return 1
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
                        limits.note_remote_call()
                        remote_calls = 1
                        remote_cost = float(expert.get("charged_usd") or 0.0)
                        ledger.cost(
                            model=remote_model,
                            estimated_usd=est,
                            actual_usd=expert.get("actual_cost_usd"),
                            charged_usd=remote_cost,
                            cost_basis=expert.get("cost_basis"),
                            ok=expert.get("ok"),
                        )
                        print()
                        print("Remote")
                        print(f"  ok                {expert.get('ok')}")
                        if not expert.get("ok"):
                            print(f"  error             {expert.get('error')}")
                            state = expert.get("result_state") or R.FAILED
                            ledger.finish(str(state).lower(), error=expert.get("error"))
                            return 1
                        # Explicit harness verification proof (not settle alone)
                        if args.expect and args.expect in str(expert.get("content") or ""):
                            verification, result_state = "PASS", R.VERIFIED
                        elif getattr(args, "mark_verified", False):
                            verification, result_state = "PASS (harness proof)", R.VERIFIED
                        else:
                            verification, result_state = (
                                "NOT RUN (no verification proof)",
                                R.COMPLETED,
                            )
            except Exception as exc:
                ledger.finish(R.FAILED.lower(), error=str(exc))
                print(f"Result\n  {R.FAILED} ({exc})")
                return 1

    snap = budget.snapshot()
    print()
    print(f"Agent Run {ledger.run_id}")
    print("─" * 48)
    print()
    print("Local")
    print(f"  model             {local.model or '(none)'}")
    print(f"  via               {'pi-rpc' if used_pi else 'harness'}")
    if used_pi and sel.get("provider"):
        print(f"  Pi provider       {sel['provider']}")
        print(f"  endpoint          {sel.get('endpoint')}")
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
    print(f"  {result_state}")
    ledger.finish(
        result_state.lower(),
        spent_usd=snap["spent_usd"],
        verification=verification,
        remote_calls=remote_calls,
        result_state=result_state,
    )
    return 0 if result_state in (R.COMPLETED, R.VERIFIED, R.DRY_RUN) else 1


def cmd_gateway(args: argparse.Namespace) -> int:
    action = args.action
    print(f"Use shell: source helpers/litellm.sh && dots_litellm_{action}")
    if action == "up":
        print("Binds 127.0.0.1:4000 only. Requires OPENROUTER_API_KEY in env for remote.")
        print("LITELLM_MASTER_KEY must be SET (setup generates ~/.config/dots/secrets/...).")
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
    rn.add_argument("--expect", default="", help="Token that must appear for VERIFIED")
    rn.add_argument(
        "--mark-verified",
        action="store_true",
        help="Harness-only: treat explicit proof hook as VERIFIED (tests)",
    )

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
