"""CLI handlers for `dots agent eval` and `dots agent route`."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from dots_agent.config import AgentConfig, load_config
from dots_agent.evals.openrouter_bench import fetch_benchmarks
from dots_agent.evals.registry import filter_tasks, load_registry
from dots_agent.evals.runner import (
    EvalRunResult,
    MockSolver,
    ModelIdentity,
    RunOptions,
    run_suite,
)
from dots_agent.evals.storage import EvalStore
from dots_agent.providers import detect_local
from dots_agent.routing.evidence import EvidenceType, load_empirical_evidence
from dots_agent.scout.catalog import fetch_catalog
from dots_agent.scout.select import Requirements, local_satisfies_floor, select_model


def _store(cfg: AgentConfig) -> EvalStore:
    return EvalStore(cfg.evals_dir())


def cmd_eval_list(args: Any) -> int:
    cfg = load_config()
    tasks = load_registry(cfg.eval_registry_path())
    suite = getattr(args, "suite", None)
    if suite:
        tasks = filter_tasks(tasks, suite=suite)
    print("DOTS Agent Evaluations")
    print("─" * 40)
    print()
    print(f"{'ID':<28} {'Class':<18} {'Lang':<10} {'Difficulty'}")
    for t in tasks:
        lang = t.language or "—"
        print(f"{t.id:<28} {t.task_class:<18} {lang:<10} {t.difficulty}")
    print()
    print(f"Total: {len(tasks)}")
    return 0


def cmd_eval_run(args: Any) -> int:
    cfg = load_config()
    tasks = load_registry(cfg.eval_registry_path())
    store = _store(cfg)

    use_local = bool(getattr(args, "local", False)) or str(
        getattr(args, "model", "") or ""
    ).lower() in ("local", "dots/local")
    remote = bool(getattr(args, "remote", False))
    model = getattr(args, "model", None)

    if remote and not model and not use_local:
        print("remote eval requires --model", flush=True)
        return 2
    if remote and getattr(args, "budget", None) is None:
        print("remote eval requires --budget", flush=True)
        return 2
    if model and not use_local and not remote:
        # Explicit remote model without --remote → refuse paid surprise
        if not str(model).startswith("local/") and str(model).lower() != "local":
            print("paid/remote models require --remote (and --budget)", flush=True)
            return 2

    local = detect_local(cfg)
    if use_local or (not model and not remote):
        mid = model if model and model != "local" else (local.model or "local/unknown")
        if not mid.startswith("local/") and use_local:
            mid = f"local/{mid}"
        identity = ModelIdentity(
            model_id=mid,
            provider=local.name or "local",
            backend=local.name or "",
            quantization="",
            temperature=0.0,
        )
        runs = int(getattr(args, "runs", None) or cfg.eval_default_local_runs)
    else:
        identity = ModelIdentity(
            model_id=str(model),
            provider="openrouter",
            temperature=0.0,
        )
        runs = int(getattr(args, "runs", None) or cfg.eval_default_remote_runs)

    # Mock oracle path for CI / default automated runs
    solver_mode = str(getattr(args, "solver", "oracle") or "oracle")
    if os.environ.get("DOTS_AGENT_LIVE_TEST") == "1" and remote:
        print("REMOTE PAID EVAL requested via DOTS_AGENT_LIVE_TEST=1")
        # Still use oracle unless a live solver is wired — Phase 3 keeps mock for safety
        solver_mode = "oracle"
        print("NOTE: live LLM solver not wired; using oracle fixture solver under budget gate")

    solver = MockSolver(mode=solver_mode)
    # Mutation tasks require sandbox; for mock/oracle we treat sandbox as available
    # unless explicitly disabled (tests). Live mutation would check Phase 2.
    sandbox_ok = True
    if getattr(args, "require_sandbox", False):
        from dots_agent.sandbox.status import sandbox_status_report

        sandbox_ok = bool(sandbox_status_report().get("installed"))

    options = RunOptions(
        suite=str(getattr(args, "suite", None) or cfg.eval_default_suite),
        runs_per_task=runs,
        task_class=getattr(args, "task_class", None) or None,
        task_ids=list(getattr(args, "task", None) or []) or None,
        remote=remote,
        budget_usd=getattr(args, "budget", None),
        preserve_workdir=bool(getattr(args, "preserve", False)),
        require_sandbox_for_mutation=True,
        sandbox_available=sandbox_ok,
    )
    result = run_suite(
        tasks,
        repo_root=cfg.root,
        store=store,
        solver=solver,
        identity=identity,
        options=options,
        per_remote_task_estimate=float(getattr(args, "per_task_estimate", 0.05) or 0.05),
    )
    if result.refused:
        print(f"REFUSED: {result.refused}")
        return 2
    _print_run_summary(result)
    return 0


def _print_run_summary(result: EvalRunResult) -> None:
    print(f"Eval run: {result.eval_run_id}")
    passed = sum(1 for a in result.attempts if a.passed)
    failed = sum(1 for a in result.attempts if not a.passed)
    print(f"  attempts  {len(result.attempts)}")
    print(f"  passed    {passed}")
    print(f"  failed    {failed}")
    print(f"  skipped   {len(result.skipped)}")
    for s in result.skipped[:10]:
        print(f"    skip {s.get('task_id')}: {s.get('reason')}")


def cmd_eval_results(args: Any) -> int:
    cfg = load_config()
    store = _store(cfg)
    rows = store.results_table(task_class=getattr(args, "task_class", None) or None)
    print(f"{'Model':<32} {'Class':<16} {'N':>4} {'Pass':>4} {'Raw':>7} {'Conservative':>12}")
    for r in rows:
        raw = "—" if r["raw_success_rate"] is None else f"{100 * r['raw_success_rate']:.1f}%"
        cons = (
            "—"
            if r["conservative_success_rate"] is None
            else f"{100 * r['conservative_success_rate']:.1f}%"
        )
        print(
            f"{r['model']:<32} {r['class']:<16} {r['attempts']:>4} {r['successes']:>4} "
            f"{raw:>7} {cons:>12}"
        )
    if not rows:
        print("(no results yet)")
    return 0


def cmd_eval_compare(args: Any) -> int:
    cfg = load_config()
    store = _store(cfg)
    a, b = args.model_a, args.model_b
    classes = sorted(
        {
            r["class"]
            for r in store.results_table()
            if r["model"] in (a, b)
        }
    )
    print(f"Compare {a} vs {b}")
    print("─" * 50)
    for cls in classes:
        ea = load_empirical_evidence(
            store,
            model_id=a,
            task_class=cls,
            minimum_attempts=cfg.evidence_minimum_attempts,
            max_age_days=cfg.evidence_max_age_days,
            wilson_z=cfg.wilson_z,
        )
        eb = load_empirical_evidence(
            store,
            model_id=b,
            task_class=cls,
            minimum_attempts=cfg.evidence_minimum_attempts,
            max_age_days=cfg.evidence_max_age_days,
            wilson_z=cfg.wilson_z,
        )
        print(f"\n{cls}")
        for label, e in ((a, ea), (b, eb)):
            raw = "—" if e.raw_success_rate is None else f"{100 * e.raw_success_rate:.1f}%"
            cons = (
                "—"
                if e.conservative_success_rate is None
                else f"{100 * e.conservative_success_rate:.1f}%"
            )
            print(f"  {label}: n={e.attempts} raw={raw} cons={cons} lat={e.median_latency}")
    return 0


def cmd_eval_regressions(args: Any) -> int:
    cfg = load_config()
    store = _store(cfg)
    findings = store.detect_regressions(
        current_run_id=getattr(args, "run", None) or None,
        min_attempts=int(getattr(args, "min_attempts", 5) or 5),
    )
    if not findings:
        print("No regressions detected (or no baseline set).")
        print("Promote a baseline with: dots agent eval baseline RUN_ID")
        return 0
    for f in findings:
        print(
            f"{f['model']} / {f['class']}: "
            f"{100 * f['baseline_rate']:.1f}% → {100 * f['current_rate']:.1f}% "
            f"(drop {100 * f['drop']:.1f}%)"
        )
    return 1 if findings else 0


def cmd_eval_baseline(args: Any) -> int:
    cfg = load_config()
    store = _store(cfg)
    store.set_baseline(args.run_id)
    print(f"Baseline set to {args.run_id}")
    return 0


def cmd_eval_calibrate(args: Any) -> int:
    cfg = load_config()
    store = _store(cfg)
    from dots_agent.scout.capabilities import load_capabilities, quality_of

    rules, _tiers = load_capabilities(cfg.capabilities_path())
    rows = store.results_table()
    print("Curated vs empirical calibration")
    print("─" * 50)
    seen: set[str] = set()
    for r in rows:
        mid = r["model"]
        if mid in seen:
            continue
        seen.add(mid)
        curated = quality_of(mid, rules)
        # Pick primary class with most attempts
        class_rows = [x for x in rows if x["model"] == mid]
        class_rows.sort(key=lambda x: -x["attempts"])
        best = class_rows[0]
        cons = best["conservative_success_rate"]
        floors = cfg.quality_floors()
        empirical_tier = "unrated"
        if best["attempts"] >= cfg.evidence_minimum_attempts and cons is not None:
            for tier in ("frontier", "strong", "capable", "basic"):
                if cons >= floors[tier]:
                    empirical_tier = tier
                    break
            else:
                empirical_tier = "below_basic"
        disc = ""
        order = ["unrated", "basic", "capable", "strong", "frontier"]
        if empirical_tier in order and curated in order:
            if order.index(empirical_tier) < order.index(curated):
                disc = "DOWNGRADE SUGGESTED"
            elif order.index(empirical_tier) > order.index(curated):
                disc = "UPGRADE CANDIDATE"
        print(f"{mid}")
        print(f"  curated:   {curated}")
        print(f"  empirical: {empirical_tier} (n={best['attempts']}, class={best['class']})")
        if disc:
            print(f"  discrepancy: {disc}")
    return 0


def cmd_eval_import_openrouter(args: Any) -> int:
    cfg = load_config()
    store = _store(cfg)
    cache = store.external_dir / "openrouter-benchmarks.json"
    allow = not bool(getattr(args, "offline", False))
    payload = fetch_benchmarks(
        cache_path=cache,
        api_key=os.environ.get("OPENROUTER_API_KEY"),
        allow_network=allow,
    )
    print(json.dumps({
        "ok": payload.get("ok"),
        "count": len(payload.get("benchmarks") or []),
        "used_as_task_success_probability": False,
        "cache": str(cache),
        "reason": payload.get("reason"),
    }, indent=2))
    return 0 if payload.get("ok") else 1


def cmd_route(args: Any) -> int:
    cfg = load_config()
    store = _store(cfg)
    simulate = bool(getattr(args, "simulate", False))
    allow_net = not simulate and not bool(getattr(args, "local", False))

    cat = fetch_catalog(
        cache_dir=cfg.cache_dir(),
        catalog_url=cfg.catalog_url,
        catalog_url_public=cfg.catalog_url_public,
        ttl_seconds=cfg.catalog_cache_ttl,
        allow_network=allow_net,
        force_live=False,
    )
    # Optional local model candidate
    models = list(cat.models)
    local = detect_local(cfg)
    if local.model:
        models = [
            {
                "id": f"local/{local.model}",
                "context_length": 32768,
                "supported_parameters": ["tools", "response_format"],
                "pricing": {"prompt": "0", "completion": "0"},
                "_dots_local": True,
            },
            *models,
        ]

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
        task_type=str(args.task),
        languages=[args.language] if getattr(args, "language", "") else [],
        context_tokens=int(args.context),
        expected_output_tokens=int(args.output),
        requires_tools=bool(getattr(args, "tools", False)),
        requires_structured_output=bool(getattr(args, "structured", False)),
        quality_floor=str(args.quality),
        max_cost_usd=float(args.max_cost) if args.max_cost is not None else None,
        latency_preference=str(getattr(args, "preference", None) or cfg.routing_preference),
    )
    result = select_model(
        models,
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
    if cat.stale:
        result.setdefault("warnings", []).append("CATALOG STALE")

    if getattr(args, "json", False):
        print(json.dumps(result, indent=2))
        return 0

    print("Agent Route")
    print("─" * 50)
    print()
    print("Task")
    langs = ", ".join(req.languages) if req.languages else "—"
    print(f"  {req.task_type} · {langs}")
    print(f"  quality floor         {req.quality_floor}")
    print(f"  context               {req.context_tokens:,}")
    if req.max_cost_usd is not None:
        print(f"  max request cost      ${req.max_cost_usd:.2f}")
    if simulate:
        print("  mode                  simulate (no inference)")
    print()
    sel = result.get("selected")
    if not sel:
        print("Selected")
        print("  (none)")
    else:
        print("Selected")
        print(f"  {sel['model']}")
        print()
        print("Evidence")
        print(f"  type                  {sel.get('evidence')}")
        print(f"  attempts              {sel.get('attempts', 0)}")
        raw = sel.get("raw_success_rate")
        cons = sel.get("conservative_success_rate")
        print(f"  raw success           {('—' if raw is None else f'{100*raw:.1f}%')}")
        print(f"  conservative success  {('—' if cons is None else f'{100*cons:.1f}%')}")
        print()
        print("Economics")
        print(f"  request estimate       ${float(sel.get('estimated_attempt_cost_usd') or sel.get('estimated_cost_usd') or 0):.4f}")
        ecs = sel.get("expected_cost_to_success_usd")
        print(f"  expected cost/success  {('—' if ecs is None else f'${ecs:.4f}')}")
    print()
    print("Why")
    for line in result.get("explanation") or []:
        print(f"  {line}")
    if result.get("warnings"):
        print()
        for w in result["warnings"]:
            print(f"WARNING: {w}")
    print()
    print(f"routing_policy_version={result.get('routing', {}).get('policy_version')}")
    return 0


def wire_local_escalation_check(cfg: AgentConfig, task_class: str, quality_floor: str) -> dict[str, Any]:
    """Used by auto run mode — empirical local floor check."""
    store = _store(cfg)
    local = detect_local(cfg)
    mid = f"local/{local.model}" if local.model else "local/unknown"

    def lookup(model_id: str, tc: str):
        return load_empirical_evidence(
            store,
            model_id=model_id,
            task_class=tc,
            minimum_attempts=cfg.evidence_minimum_attempts,
            max_age_days=cfg.evidence_max_age_days,
            wilson_z=cfg.wilson_z,
        )

    return local_satisfies_floor(
        model_id=mid,
        task_class=task_class,
        quality_floor=quality_floor,
        evidence_lookup=lookup,
        quality_cfg=cfg.quality_floors(),
        minimum_attempts=cfg.evidence_minimum_attempts,
    )
