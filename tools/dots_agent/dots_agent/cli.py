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
from dots_agent.mcp_trust import inspector_cli_cmd, load_mcp_trust, safe_server_ids
from dots_agent.pi_models import merge_local_provider, resolve_pi_selection
from dots_agent.pi_rpc import PiRpcClient
from dots_agent.providers import detect_local
from dots_agent import results as R
from dots_agent.run_session import (
    IN_PLACE,
    SAFE,
    UNSAFE_HOST,
    UNSAFE_WARNING,
    finish_session,
    prepare_run_session,
    resolve_execution_mode,
)
from dots_agent.sandbox.policy import global_sandbox_path, merge_global_sandbox_policy
from dots_agent.sandbox.status import doctor_sandbox_checks, sandbox_status_report
from dots_agent.scout.catalog import fetch_catalog
from dots_agent.scout.select import Requirements, select_model
from dots_agent.secrets import litellm_master_key_status
from dots_agent.worktree import (
    apply_to_primary,
    diff_text,
    discard_worktree,
    files_changed,
    list_worktrees,
    load_meta,
)


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
    sb = sandbox_status_report()
    print("Policy")
    print("  mode             local-first")
    print(f"  execution        {sb['execution_mode_default']} (default)")
    print(f"  session budget   ${cfg.session_budget_usd:.2f}")
    print(f"  max remote calls {cfg.max_remote_calls}")
    print(f"  agent venv       {'OK' if rep['venv'] else 'MISSING'}")
    print()
    print("Sandbox")
    print(f"  provider         {sb['provider']}")
    print(f"  installed        {'yes' if sb['installed'] else 'no'}")
    print(f"  worktree         {'enabled' if sb['worktree_enabled'] else 'disabled'}")
    print(f"  unsafe fallback  {sb['unsafe_fallback']}")
    print()
    from dots_agent.autonomy.policy import load_autonomy_policy

    ap = load_autonomy_policy()
    print("Autonomy")
    print(f"  mode             {ap.mode.value} (default)")
    print(f"  policy version   {ap.policy_version}")
    print(
        "  ladder           "
        + " → ".join(a.value for a in ap.ladder)
    )
    print()
    print("Default runs use sandboxed safe mode. Bypass only with --unsafe-host.")
    return 0


def cmd_doctor(_: argparse.Namespace) -> int:
    cfg = load_config()
    for k, v in doctor_checks(cfg):
        print(f"{k:28} {v}")
    print()
    print("Sandbox / trust")
    for k, v in doctor_sandbox_checks():
        print(f"{k:28} {v}")
    print()
    print("OpenRig / teams")
    from dots_agent.openrig.status import doctor_checks as openrig_doctor

    for k, v in openrig_doctor(cfg):
        print(f"{k:28} {v}")
    print()
    print()
    print("Autonomy / recovery")
    from dots_agent.autonomy.policy import load_autonomy_policy

    ap = load_autonomy_policy()
    print(f"{'autonomy_mode':28} {ap.mode.value}")
    print(f"{'policy_version':28} {ap.policy_version}")
    print(f"{'max_transient_retries':28} {ap.bounds.max_transient_retries}")
    print(f"{'max_local_replans':28} {ap.bounds.max_local_replans}")
    print(f"{'max_expert_escalations':28} {ap.bounds.max_expert_escalations}")
    print(f"{'forbidden_ops':28} {len(ap.forbidden)} gated")
    print()
    print("Credentials shown as SET/UNSET only — values never printed.")
    print("MCP Inspector: dots agent mcp inspect <dots-model-scout|dots-expert>")
    print("Team doctor: dots agent team doctor")
    print("Observability: dots agent inspect|timeline|failures|attention|metrics|replay")
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
    from dots_agent.evals.storage import EvalStore
    from dots_agent.routing.evidence import load_empirical_evidence

    store = EvalStore(cfg.evals_dir())

    def evidence_lookup(model_id: str, task_class: str):
        return load_empirical_evidence(
            store,
            model_id=model_id,
            task_class=task_class,
            minimum_attempts=cfg.evidence_minimum_attempts,
            max_age_days=cfg.evidence_max_age_days,
            wilson_z=cfg.wilson_z,
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
        evidence_lookup=evidence_lookup,
        quality_cfg=cfg.quality_floors(),
        minimum_attempts=cfg.evidence_minimum_attempts,
        preference=cfg.routing_preference,
        routing_policy_version=cfg.routing_policy_version,
    )
    result["catalog"] = {
        "source": cat.source,
        "age_seconds": int(cat.age_seconds),
        "stale": cat.stale,
    }
    if cat.stale:
        result.setdefault("warnings", []).append("CATALOG STALE")
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
        print(f"  evidence              {sel.get('evidence', 'curated')}")
        print(f"  estimated cost        ${sel.get('estimated_cost_usd', 0):.3f}")
        ecs = sel.get("expected_cost_to_success_usd")
        if ecs is not None:
            print(f"  expected success      ${ecs:.3f}")
        print(f"  context               {sel['context_length']}")
        print(f"  tools                 {'yes' if sel['supports_tools'] else 'no'}")
    else:
        print("Selected")
        print("  (none)")
    print()
    print("Why")
    for line in result.get("explanation") or []:
        print(f"  {line}")
    print()
    print("Alternatives")
    for alt in result.get("alternatives") or []:
        extra = ""
        if alt.get("expected_cost_to_success_usd") is not None:
            extra = f"  ecs=${alt['expected_cost_to_success_usd']:.3f}"
        print(f"  {alt['model']:<40} ${alt['estimated_cost_usd']:.3f}{extra}")
    if not result.get("alternatives"):
        print("  (none)")
    print()
    print("Rejected")
    for k, v in (result.get("rejected_summary") or {}).items():
        print(f"  {v:>3} {k}")
    print()
    print(f"Catalog: {cat.source} (age {int(cat.age_seconds)}s)")
    if result.get("warnings"):
        for w in result["warnings"]:
            print(f"WARNING: {w}")
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
    execution_mode = resolve_execution_mode(
        None,
        unsafe=bool(getattr(args, "unsafe_host", False)),
        in_place=bool(getattr(args, "in_place", False)),
    )
    # --safe is default; explicit flag wins only if set without conflict
    if getattr(args, "safe", False) and not args.unsafe_host and not args.in_place:
        execution_mode = SAFE
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
    os.environ["DOTS_AGENT_EXECUTION_MODE"] = execution_mode
    if local_only:
        os.environ["DOTS_AGENT_LOCAL"] = "1"
        os.environ.pop("OPENROUTER_API_KEY", None)
    if args.approve_expensive:
        os.environ["DOTS_AGENT_APPROVE_EXPENSIVE"] = "1"

    primary_cwd = Path(args.cwd).resolve() if args.cwd else Path.cwd()
    local = detect_local(cfg)
    sel = resolve_pi_selection(local)

    if args.dry_run:
        print("Agent dry-run")
        print(f"  run id           {ledger.run_id}")
        print(f"  execution mode   {execution_mode}")
        print(f"  sandbox          {'enabled' if execution_mode != UNSAFE_HOST else 'DISABLED'}")
        print(f"  worktree         {'yes (git repos)' if execution_mode == SAFE else 'no'}")
        print(f"  cwd              {primary_cwd}")
        print(f"  local provider   {local.name}")
        print(f"  local model      {local.model or '(none)'}")
        print(f"  MCP              {', '.join(safe_server_ids(cfg))}")
        if execution_mode == UNSAFE_HOST:
            print("  bash network     unrestricted (host)")
            print(f"  ! {UNSAFE_WARNING}")
        else:
            print("  bash network     localhost/127.0.0.1 only (safe)")
        ledger.update(
            task_summary=task[:200],
            execution_mode=execution_mode,
            sandbox_enabled=execution_mode != UNSAFE_HOST,
        )
        ledger.finish(R.DRY_RUN.lower())
        return 0

    try:
        session = prepare_run_session(
            run_id=ledger.run_id,
            primary_cwd=primary_cwd,
            execution_mode=execution_mode,
            cfg=cfg,
            interactive=bool(getattr(args, "interactive", False)),
            harness_only=bool(args.harness_only),
        )
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        ledger.finish(R.FAILED.lower(), error=str(exc), execution_mode=execution_mode)
        return 1

    ledger.update(
        task_summary=task[:200],
        local_provider=local.name,
        local_model=local.model,
        mode="local" if local_only else "auto",
        budget_usd=budget_usd,
        execution_mode=execution_mode,
        sandbox_provider="pi-sandbox" if session.sandbox_enabled else "none",
        sandbox_enabled=session.sandbox_enabled,
        worktree_path=str(session.worktree.path) if session.worktree else None,
        base_commit=session.worktree.base_commit if session.worktree else None,
        network_policy=session.network_policy,
        mcp_servers=session.mcp_servers,
    )

    print(f"Agent Run {ledger.run_id}")
    print("─" * 48)
    print()
    print(f"Execution mode: {execution_mode}")
    if execution_mode == UNSAFE_HOST:
        print(UNSAFE_WARNING)
    else:
        print("Sandbox: enabled (fail-closed)")
    for w in session.warnings:
        print(f"Note: {w}")

    # Phase 3: pre-task local empirical floor (explicit task-class; default general)
    task_class = str(getattr(args, "task_class", None) or "general")
    quality_floor = str(getattr(args, "quality", None) or "capable")
    from dots_agent.evals.cli_eval import wire_local_escalation_check

    local_ev = wire_local_escalation_check(cfg, task_class, quality_floor)
    ledger.event(
        "route_decision",
        routing_policy_version=cfg.routing_policy_version,
        task_class=task_class,
        quality_floor=quality_floor,
        local_empirical=local_ev,
        evidence_source=local_ev.get("evidence"),
        selected_executor="local",
        remote_eligible_early=(
            not local_only
            and not local_ev.get("ok")
            and local_ev.get("reason") in ("below_floor", "insufficient_empirical")
        ),
    )
    print(f"Task class: {task_class} (quality floor {quality_floor})")
    if local_ev.get("ok"):
        print(
            f"Local empirical: meets floor "
            f"(n={local_ev.get('attempts')}, "
            f"conservative={local_ev.get('conservative_success_rate')})"
        )
    else:
        print(
            f"Local empirical: {local_ev.get('reason')} "
            f"(n={local_ev.get('attempts', 0)}) — remote expert eligible earlier in auto"
        )
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
        if local.healthy and local.name in ("ollama", "llamacpp"):
            merge_local_provider(local)
        if not sel.get("provider") or not sel.get("model"):
            print("Local provider not resolvable for Pi RPC; falling back to harness.")
            ledger.event("pi_rpc_skip", reason="unresolvable local model")
        else:
            client = PiRpcClient(
                cwd=str(session.cwd),
                provider=str(sel["provider"]),
                model=str(sel["model"]),
                timeout_seconds=cfg.timeout_seconds,
                env=session.pi_env,
                extra_args=list(session.pi_extra_args),
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
                    execution_mode=execution_mode,
                )
                if not outcome.get("ok"):
                    err = str(outcome.get("error") or "pi failed")
                    state = R.TIMED_OUT if "timeout" in err.lower() else R.FAILED
                    ledger.finish(state.lower(), error=err)
                    print(f"Result\n  {state} ({err})")
                    return 1
                outcome_text = str(outcome.get("assistant_text") or "")[:2000]
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
    finish_session(session)

    from dots_agent.autonomy.checkpoint import save_checkpoint
    from dots_agent.autonomy.events import emit_checkpoint
    from dots_agent.autonomy.policy import RecoveryCounters, load_autonomy_policy
    from dots_agent.autonomy.progress import ProgressState

    autonomy_mode = getattr(args, "autonomy", None)
    apolicy = load_autonomy_policy(mode_override=autonomy_mode)
    counters = RecoveryCounters()
    progress = ProgressState()
    ckpt_path = save_checkpoint(
        ledger.dir,
        autonomy_mode=apolicy.mode,
        policy_version=apolicy.policy_version,
        budget_spent_usd=float(snap["spent_usd"]),
        budget_reserved_usd=float(snap["reserved_usd"]),
        budget_remaining_usd=float(snap["remaining_usd"]),
        session_budget_usd=float(snap["session_budget_usd"]),
        remote_call_count=int(snap["remote_call_count"]),
        max_remote_calls=int(snap["max_remote_calls"]),
        counters=counters,
        progress=progress,
        outcome=result_state,
        worktree_path=str(session.worktree.path) if session.worktree else None,
    )
    emit_checkpoint(ledger, path=str(ckpt_path))

    print()
    print(f"Agent Run {ledger.run_id}")
    print("─" * 48)
    print()
    print("Local")
    print(f"  model             {local.model or '(none)'}")
    print(f"  via               {'pi-rpc' if used_pi else 'harness'}")
    print(f"  execution         {execution_mode}")
    print(f"  sandbox           {'yes' if session.sandbox_enabled else 'no'}")
    print(f"  autonomy          {apolicy.mode.value}")
    if used_pi and sel.get("provider"):
        print(f"  Pi provider       {sel['provider']}")
        print(f"  endpoint          {sel.get('endpoint')}")
    if session.worktree:
        changed = files_changed(session.worktree)
        print()
        print("Worktree")
        print(f"  path              {session.worktree.path}")
        print(f"  base commit       {session.worktree.base_commit[:12]}")
        print(f"  files changed     {len(changed)}")
        print("  (primary checkout untouched — use: dots agent apply/diff/discard)")
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
        execution_mode=execution_mode,
        sandbox_enabled=session.sandbox_enabled,
        autonomy_mode=apolicy.mode.value,
        policy_version=apolicy.policy_version,
    )
    return 0 if result_state in (R.COMPLETED, R.VERIFIED, R.DRY_RUN) else 1


def cmd_gateway(args: argparse.Namespace) -> int:
    action = args.action
    print(f"Use shell: source helpers/litellm.sh && dots_litellm_{action}")
    if action == "up":
        print("Binds 127.0.0.1:4000 only. Requires OPENROUTER_API_KEY in env for remote.")
        print("LITELLM_MASTER_KEY must be SET (setup generates ~/.config/dots/secrets/...).")
    return 0


def cmd_sandbox(args: argparse.Namespace) -> int:
    action = args.sandbox_cmd
    if action == "status":
        sb = sandbox_status_report()
        print("Agent Sandbox")
        print("─" * 32)
        print()
        print("Provider")
        print(f"  pi-sandbox          {'installed' if sb['installed'] else 'missing'}")
        print(f"  detail              {sb['install_detail']}")
        print(f"  enabled             yes (safe default)")
        print()
        print("Execution")
        print(f"  default mode        {sb['execution_mode_default']}")
        print(f"  worktree            {'enabled' if sb['worktree_enabled'] else 'disabled'}")
        print(f"  shell network       {', '.join(sb['bash_allowed_domains'])} only")
        print(f"  unsafe fallback     {sb['unsafe_fallback']}")
        print()
        print("OS backend")
        for k, v in (sb.get("os_backend") or {}).items():
            print(f"  {k:18}  {v}")
        print()
        print("Filesystem (policy intent)")
        print("  project read        yes")
        print("  project write       yes")
        print("  home read           no (default deny)")
        print("  secret paths        denied")
        print()
        print("MCP")
        print(f"  allowed             {', '.join(sb['mcp_safe_servers'])}")
        print()
        print(f"Config               {sb['config']}")
        return 0 if sb["installed"] else 1
    if action == "policy":
        path = global_sandbox_path()
        if not path.is_file():
            print(f"No global policy at {path}")
            print("Run: ./dots setup --with agent-sandbox")
            return 1
        print(path.read_text(encoding="utf-8"))
        return 0
    if action == "doctor":
        for k, v in doctor_sandbox_checks():
            print(f"{k:28} {v}")
        return 0
    if action == "merge-policy":
        result = merge_global_sandbox_policy()
        print(json.dumps(result, indent=2))
        return 0 if result.get("ok") else 1
    return 2


def cmd_worktrees(_: argparse.Namespace) -> int:
    items = list_worktrees()
    if not items:
        print("No agent worktrees.")
        return 0
    for info in items:
        print(f"{info.run_id}  {info.status:10}  {info.path}")
    return 0


def cmd_diff(args: argparse.Namespace) -> int:
    info = load_meta(args.run_id)
    if not info:
        print(f"Unknown run: {args.run_id}", file=sys.stderr)
        return 1
    sys.stdout.write(diff_text(info))
    return 0


def cmd_apply(args: argparse.Namespace) -> int:
    info = load_meta(args.run_id)
    if not info:
        print(f"Unknown run: {args.run_id}", file=sys.stderr)
        return 1
    result = apply_to_primary(info)
    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


def cmd_discard(args: argparse.Namespace) -> int:
    info = load_meta(args.run_id)
    if not info:
        print(f"Unknown run: {args.run_id}", file=sys.stderr)
        return 1
    result = discard_worktree(info)
    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


def cmd_mcp(args: argparse.Namespace) -> int:
    action = args.mcp_cmd
    if action == "status":
        print("Trusted MCP (safe harness allowlist)")
        print("─" * 40)
        for row in load_mcp_trust():
            print(f"  {row.get('id')}")
            print(f"    trust       {row.get('trust')}")
            print(f"    filesystem  {row.get('filesystem')}")
            print(f"    shell       {row.get('shell')}")
            print(f"    billable    {row.get('billable')}")
        print()
        print(f"Allowlist: {', '.join(safe_server_ids())}")
        print("Interactive `pi` keeps the user's full MCP configuration.")
        return 0
    if action == "inspect":
        import subprocess

        name = args.server
        root = Path(os.environ.get("DOTS_DIR") or load_config().root)
        if name == "dots-model-scout":
            cmd_path = which("dots-model-scout") or str(root / "scripts" / "dots-model-scout")
        elif name == "dots-expert":
            cmd_path = which("dots-expert") or str(root / "scripts" / "dots-expert")
        else:
            print(f"Unknown server (safe allowlist only): {name}", file=sys.stderr)
            return 2
        cmd = inspector_cli_cmd(cmd_path)
        print("Running:", " ".join(cmd))
        try:
            proc = subprocess.run(cmd, timeout=120)
            return proc.returncode
        except FileNotFoundError:
            print("npx not found — install Node to use MCP Inspector", file=sys.stderr)
            return 1
        except subprocess.TimeoutExpired:
            print("Inspector timed out", file=sys.stderr)
            return 1
    return 2


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

    rn = sub.add_parser("run", help="Run local-first agent task (default: safe)")
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
    rn.add_argument(
        "--task-class",
        default="general",
        help="Task class for routing evidence (default: general)",
    )
    rn.add_argument("--quality", default="capable", help="Quality floor for auto routing")
    rn.add_argument("--expect", default="", help="Token that must appear for VERIFIED")
    rn.add_argument(
        "--mark-verified",
        action="store_true",
        help="Harness-only: treat explicit proof hook as VERIFIED (tests)",
    )
    rn.add_argument("--safe", action="store_true", help="Sandboxed safe mode (default)")
    rn.add_argument(
        "--in-place",
        action="store_true",
        help="Sandbox enabled; write to current checkout (no worktree)",
    )
    rn.add_argument(
        "--unsafe-host",
        action="store_true",
        help="Explicit unrestricted host execution (consent flag)",
    )
    rn.add_argument(
        "--interactive",
        action="store_true",
        help="Allow longer sandbox permission prompts",
    )
    rn.add_argument(
        "--autonomy",
        choices=["manual", "guarded", "auto"],
        default=None,
        help="Autonomy mode override (default: guarded from autonomy.toml)",
    )

    sb = sub.add_parser("sandbox", help="Sandbox status / policy")
    sb_sub = sb.add_subparsers(dest="sandbox_cmd", required=True)
    sb_sub.add_parser("status", help="Show sandbox status")
    sb_sub.add_parser("policy", help="Print global sandbox.json")
    sb_sub.add_parser("doctor", help="Sandbox-focused diagnostics")
    sb_sub.add_parser("merge-policy", help="Merge DOTS global sandbox policy")

    sub.add_parser("worktrees", help="List agent worktrees")
    df = sub.add_parser("diff", help="Show worktree diff for a run")
    df.add_argument("run_id")
    ap = sub.add_parser("apply", help="Cherry-pick worktree commits onto primary")
    ap.add_argument("run_id")
    dc = sub.add_parser("discard", help="Remove worktree and agent branch")
    dc.add_argument("run_id")

    mcp = sub.add_parser("mcp", help="Trusted MCP status / Inspector")
    mcp_sub = mcp.add_subparsers(dest="mcp_cmd", required=True)
    mcp_sub.add_parser("status", help="Show MCP trust allowlist")
    insp = mcp_sub.add_parser("inspect", help="Inspector tools/list (CLI; no browser)")
    insp.add_argument("server", choices=["dots-model-scout", "dots-expert"])

    gw = sub.add_parser("gateway", help="LiteLLM gateway hints")
    gw.add_argument("action", choices=["up", "down", "health"])

    ev = sub.add_parser("eval", help="Deterministic model evaluations")
    ev_sub = ev.add_subparsers(dest="eval_cmd", required=True)
    ev_list = ev_sub.add_parser("list", help="List eval tasks")
    ev_list.add_argument("--suite", choices=["smoke", "standard", "full"], default=None)
    ev_run = ev_sub.add_parser("run", help="Run eval suite")
    ev_run.add_argument("--local", action="store_true", help="Evaluate configured local model")
    ev_run.add_argument("--remote", action="store_true", help="Opt-in paid remote eval")
    ev_run.add_argument("--model", default=None)
    ev_run.add_argument("--suite", choices=["smoke", "standard", "full"], default=None)
    ev_run.add_argument("--runs", type=int, default=None)
    ev_run.add_argument("--budget", type=float, default=None)
    ev_run.add_argument("--task-class", default=None)
    ev_run.add_argument("--task", action="append", default=[])
    ev_run.add_argument("--solver", default="oracle", choices=["oracle", "fail", "noop"])
    ev_run.add_argument("--preserve", action="store_true")
    ev_run.add_argument("--require-sandbox", action="store_true")
    ev_res = ev_sub.add_parser("results", help="Summarize stored eval results")
    ev_res.add_argument("--task-class", default=None)
    ev_cmp = ev_sub.add_parser("compare", help="Compare two models")
    ev_cmp.add_argument("model_a")
    ev_cmp.add_argument("model_b")
    ev_reg = ev_sub.add_parser("regressions", help="Detect regressions vs baseline")
    ev_reg.add_argument("--run", default=None)
    ev_reg.add_argument("--min-attempts", type=int, default=5)
    ev_base = ev_sub.add_parser("baseline", help="Promote an eval run as baseline")
    ev_base.add_argument("run_id")
    ev_sub.add_parser("calibrate", help="Compare curated tiers vs empirical")
    ev_imp = ev_sub.add_parser(
        "import-openrouter",
        help="Fetch OpenRouter benchmark metadata (secondary evidence)",
    )
    ev_imp.add_argument("--offline", action="store_true")

    rt = sub.add_parser("route", help="Inspect evidence-based model routing")
    rt.add_argument("--task", default="debugging")
    rt.add_argument("--language", default="")
    rt.add_argument("--context", type=int, default=12000)
    rt.add_argument("--output", type=int, default=3000)
    rt.add_argument("--quality", default="strong")
    rt.add_argument("--max-cost", type=float, default=0.50)
    rt.add_argument("--tools", action="store_true")
    rt.add_argument("--structured", action="store_true")
    rt.add_argument("--simulate", action="store_true", help="No inference; cache+evidence only")
    rt.add_argument("--local", action="store_true", help="Cache-only catalog")
    rt.add_argument("--json", action="store_true")

    tm = sub.add_parser("team", help="OpenRig persistent agent teams")
    tm_sub = tm.add_subparsers(dest="team_cmd", required=True)
    tm_st = tm_sub.add_parser("status", help="OpenRig + team policy status")
    tm_st.add_argument("--team", default=None, help="Team run id for budget snapshot")
    tm_st.add_argument("--json", action="store_true")
    tm_st.add_argument("--routing", action="store_true", help="Show stored routing evidence")
    tm_st.add_argument("--refresh", action="store_true")
    tm_sub.add_parser("list", help="List DOTS team templates")
    tm_sub.add_parser("doctor", help="OpenRig / seat / terminal diagnostics")
    tm_up = tm_sub.add_parser("up", help="Render policy, provision seats, start rig")
    tm_up.add_argument("template", choices=["dots-pair", "dots-triad", "dots-investigate"])
    tm_up.add_argument("--project", required=True)
    tm_up.add_argument("--dry-run", action="store_true")
    tm_dn = tm_sub.add_parser("down", help="Stop team (preserve state)")
    tm_dn.add_argument("template")
    tm_op = tm_sub.add_parser("open", help="Open Herdr/tmux OpenRig view")
    tm_op.add_argument("--rig", default=None)
    tm_op.add_argument("--target", default="saved:kernel")
    tm_op.add_argument("--window", action="store_true")
    tm_op.add_argument("--dry-run", action="store_true")
    tm_tasks = tm_sub.add_parser("tasks", help="Summarize OpenRig queue")
    tm_tasks.add_argument("--destination", default=None)
    tm_sub.add_parser("messages", help="Summarize OpenRig messages/stream")
    tm_rc = tm_sub.add_parser("restore-check", help="OpenRig restore-check")
    tm_rc.add_argument("target", nargs="?", default=None)
    tm_rec = tm_sub.add_parser("reconcile", help="Compare desired seat policy vs projection")
    tm_rec.add_argument("template", choices=["dots-pair", "dots-triad", "dots-investigate"])
    tm_rec.add_argument("--apply", action="store_true")
    tm_run = tm_sub.add_parser("run", help="Queue work to a team via OpenRig")
    tm_run.add_argument("--team", default="dots-triad")
    tm_run.add_argument("task", nargs="+")
    tm_run.add_argument("--detach", action="store_true", default=True)
    tm_run.add_argument("--follow", action="store_true")
    tm_diff = tm_sub.add_parser("diff", help="Show isolated team worktree diffs")
    tm_diff.add_argument("rig")

    # Phase 5 — observability / resume / replay
    insp = sub.add_parser("inspect", help="Inspect a run ledger + checkpoint")
    insp.add_argument("run_id")
    insp.add_argument("--json", action="store_true")

    tl = sub.add_parser("timeline", help="Show structured run timeline")
    tl.add_argument("run_id")
    tl.add_argument("--json", action="store_true")

    fl = sub.add_parser("failures", help="List recorded structural failures")
    fl.add_argument("--limit", type=int, default=50)
    fl.add_argument("--json", action="store_true")

    att = sub.add_parser("attention", help="List human-attention events")
    att.add_argument("--limit", type=int, default=50)
    att.add_argument("--json", action="store_true")

    sub.add_parser("metrics", help="Aggregate local run metrics")

    cn = sub.add_parser("cancel", help="Cancel a run (marker + ledger)")
    cn.add_argument("run_id")

    rp = sub.add_parser("replay", help="Offline policy replay (zero network/mutations)")
    rp.add_argument("run_id")
    rp.add_argument("--json", action="store_true")

    rs = sub.add_parser("resume", help="Resume a run without refreshing allowances")
    rs.add_argument("run_id")
    rs.add_argument("--json", action="store_true")

    return p


def cmd_eval(args: argparse.Namespace) -> int:
    from dots_agent.evals import cli_eval as E

    dispatch = {
        "list": E.cmd_eval_list,
        "run": E.cmd_eval_run,
        "results": E.cmd_eval_results,
        "compare": E.cmd_eval_compare,
        "regressions": E.cmd_eval_regressions,
        "baseline": E.cmd_eval_baseline,
        "calibrate": E.cmd_eval_calibrate,
        "import-openrouter": E.cmd_eval_import_openrouter,
    }
    return dispatch[args.eval_cmd](args)


def cmd_route(args: argparse.Namespace) -> int:
    from dots_agent.evals.cli_eval import cmd_route as _route

    return _route(args)


def cmd_team(args: argparse.Namespace) -> int:
    from dots_agent.openrig import cli_team as T

    dispatch = {
        "status": T.cmd_team_status,
        "list": T.cmd_team_list,
        "doctor": T.cmd_team_doctor,
        "up": T.cmd_team_up,
        "down": T.cmd_team_down,
        "open": T.cmd_team_open,
        "tasks": T.cmd_team_tasks,
        "messages": T.cmd_team_messages,
        "restore-check": T.cmd_team_restore_check,
        "reconcile": T.cmd_team_reconcile,
        "run": T.cmd_team_run,
        "diff": T.cmd_team_diff,
    }
    return dispatch[args.team_cmd](args)


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    parser = build_parser()
    args = parser.parse_args(argv)
    from dots_agent.autonomy import cli_obs as O

    dispatch = {
        "status": cmd_status,
        "doctor": cmd_doctor,
        "models": cmd_models,
        "scout": cmd_scout,
        "costs": cmd_costs,
        "run": cmd_run,
        "gateway": cmd_gateway,
        "sandbox": cmd_sandbox,
        "worktrees": cmd_worktrees,
        "diff": cmd_diff,
        "apply": cmd_apply,
        "discard": cmd_discard,
        "mcp": cmd_mcp,
        "eval": cmd_eval,
        "route": cmd_route,
        "team": cmd_team,
        "inspect": O.cmd_inspect,
        "timeline": O.cmd_timeline,
        "failures": O.cmd_failures,
        "attention": O.cmd_attention,
        "metrics": O.cmd_metrics,
        "cancel": O.cmd_cancel,
        "replay": O.cmd_replay,
        "resume": O.cmd_resume,
    }
    return dispatch[args.cmd](args)


if __name__ == "__main__":
    raise SystemExit(main())
