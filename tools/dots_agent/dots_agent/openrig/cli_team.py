"""CLI handlers for `dots agent team`."""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import time
import uuid
from pathlib import Path
from typing import Any

from dots_agent.config import load_config
from dots_agent.openrig.provision import provision_pi_seat
from dots_agent.openrig.queue import list_messages, list_tasks, parse_queue_table, restore_check
from dots_agent.openrig.roles import load_roles, role_names_for_template
from dots_agent.openrig.specs import dry_run_plan, list_templates, render_team_bundle
from dots_agent.openrig.status import (
    append_mapping,
    build_team_status,
    doctor_checks,
    print_team_status,
    team_state_dir,
)
from dots_agent.openrig.team_budget import TeamBudget
from dots_agent.openrig.terminal import (
    herdr_session_name,
    open_view_command,
    preferred_provider,
)
from dots_agent.providers import detect_local
from dots_agent.worktree import create_worktree


def _run_rig(*args: str, check: bool = False) -> tuple[int, str]:
    if not shutil.which("rig"):
        return 127, "rig not installed"
    proc = subprocess.run(
        ["rig", *args], capture_output=True, text=True, check=False
    )
    out = ((proc.stdout or "") + (proc.stderr or "")).strip()
    if check and proc.returncode != 0:
        raise RuntimeError(out or f"rig {' '.join(args)} failed")
    return proc.returncode, out


def cmd_team_status(args: Any) -> int:
    cfg = load_config()
    rep = build_team_status(
        team_id=getattr(args, "team", None),
        cfg=cfg,
        refresh=bool(getattr(args, "refresh", False)),
    )
    if getattr(args, "json", False):
        print(json.dumps(rep, indent=2))
        return 0
    print_team_status(rep)
    # Optional seat routing evidence (cached / stored only)
    if getattr(args, "routing", False):
        print()
        print("Seat routing (stored evidence; no network)")
        print(f"  {'Seat':<22} {'Local Model':<20} Evidence")
        local = detect_local(cfg)
        mid = f"local/{local.model}" if local.model else "local/unknown"
        from dots_agent.evals.storage import EvalStore
        from dots_agent.routing.evidence import load_empirical_evidence

        store = EvalStore(cfg.evals_dir())
        roles, _ = load_roles()
        for name, pol in roles.items():
            ev = load_empirical_evidence(
                store,
                model_id=mid,
                task_class=pol.task_class,
                minimum_attempts=cfg.evidence_minimum_attempts,
                max_age_days=cfg.evidence_max_age_days,
            )
            if ev.adequate(cfg.evidence_minimum_attempts):
                label = "empirical"
            elif ev.attempts:
                label = "insufficient → expert eligible"
            else:
                label = "curated"
            print(f"  {name:<22} {mid:<20} {label}")
    return 0


def cmd_team_list(_: Any) -> int:
    for name in list_templates():
        print(name)
    return 0


def cmd_team_doctor(_: Any) -> int:
    """Read-only diagnostics. Prefer shell desired-state doctor when available."""
    cfg = load_config()
    helper = cfg.root / "helpers" / "openrig.sh"
    fnm_helper = cfg.root / "helpers" / "fnm.sh"
    toml_helper = cfg.root / "helpers" / "toml.sh"
    if helper.is_file() and fnm_helper.is_file():
        root_q = shlex.quote(str(cfg.root))
        toml_q = shlex.quote(str(toml_helper))
        fnm_q = shlex.quote(str(fnm_helper))
        openrig_q = shlex.quote(str(helper))
        script = f"""
set -euo pipefail
DIR={root_q}
# shellcheck disable=SC1091
source {toml_q}
# shellcheck disable=SC1091
source {fnm_q}
# shellcheck disable=SC1091
source {openrig_q}
dots_openrig_doctor
"""
        proc = subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            check=False,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        print(out.rstrip())
        if proc.returncode != 0:
            return 1
        return 0

    rc = 0
    for k, v in doctor_checks(cfg):
        print(f"{k:28} {v}")
        if v.startswith("FAIL"):
            rc = 1
    if rc != 0:
        print("\nRepair:\n  ./dots setup --with openrig")
    return rc


def cmd_team_up(args: Any) -> int:
    cfg = load_config()
    template = args.template
    project = Path(args.project).expanduser().resolve()
    if not project.is_dir():
        print(f"project not found: {project}", flush=True)
        return 2

    local = detect_local(cfg)
    staging = team_state_dir(cfg) / "rendered"
    bundle = render_team_bundle(
        template, project=project, staging_root=staging, repo_root=cfg.root
    )
    bundle["_dry_run"] = bool(args.dry_run)
    model_label = f"local/{local.model}" if local.model else "(none)"
    print(dry_run_plan(bundle, local_model=model_label))
    if args.dry_run:
        return 0

    # Validate prerequisites
    if not shutil.which("rig"):
        print("REFUSED: rig not installed (./setup.sh --with openrig)", flush=True)
        return 2
    if not shutil.which("pi"):
        print("REFUSED: pi not installed (default teams use runtime: pi)", flush=True)
        return 2

    roles, defaults = load_roles()
    team_run_id = time.strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    db = team_state_dir(cfg) / "team_budget.sqlite"
    TeamBudget(db, team_id=team_run_id, budget_usd=defaults.team_budget_usd)

    # Per-role worktrees for mutation seats
    worktrees: dict[str, Path] = {}
    for role_name in role_names_for_template(template, defaults):
        pol = roles[role_name]
        wt = None
        if pol.write and pol.sandbox == "worktree_rw":
            try:
                info = create_worktree(
                    run_id=f"{team_run_id}-{role_name}",
                    primary_cwd=project,
                    cfg=cfg,
                )
                worktrees[role_name] = info.path
            except Exception as exc:  # noqa: BLE001
                print(f"WARN: worktree for {role_name}: {exc}")
                wt = project / ".dots-worktrees" / f"{team_run_id}-{role_name}"
                wt.mkdir(parents=True, exist_ok=True)
                worktrees[role_name] = wt

        provision_pi_seat(
            rig_name=template,
            member_id=role_name,
            role=role_name,
            project=project,
            worktree=worktrees.get(role_name),
            cfg=cfg,
            force=True,
        )

    # Start daemon (idempotent)
    _run_rig("daemon", "start")

    # Launch rig from rendered spec
    code, out = _run_rig("up", bundle["rig_yaml"], "--cwd", str(project))
    if code != 0:
        # Some versions: rig up <name> --cwd
        code, out = _run_rig("up", str(Path(bundle["rig_yaml"]).parent), "--cwd", str(project))
    print(out)
    append_mapping(
        {
            "dots_team_run_id": team_run_id,
            "rig": template,
            "project": str(project),
            "staging": bundle["staging"],
            "worktrees": {k: str(v) for k, v in worktrees.items()},
            "budget_usd": defaults.team_budget_usd,
            "created_at": time.time(),
        },
        cfg,
    )
    print()
    print(f"Team run id: {team_run_id}")
    print("Terminal UI not opened (use: dots agent team open).")
    return 0 if code in (0, 127) or "partial" in out.lower() else code


def cmd_team_down(args: Any) -> int:
    template = args.template
    code, out = _run_rig("down", template)
    print(out or f"rig down {template}")
    print("Persistent queue/snapshots retained (down ≠ delete).")
    return 0 if code in (0, 127) else code


def cmd_team_open(args: Any) -> int:
    provider = preferred_provider()
    target = getattr(args, "target", None) or "saved:kernel"
    if getattr(args, "rig", None):
        # Prefer named session convention when opening project views
        sess = herdr_session_name(args.rig)
        print(f"Herdr session hint: {sess}")
    cmd = open_view_command(target=target, provider=provider, window=bool(args.window))
    if args.dry_run:
        print(" ".join(cmd))
        return 0
    print(f"Opening via {provider}: {' '.join(cmd)}")
    code, out = _run_rig(*cmd[1:])
    print(out)
    return code


def cmd_team_tasks(args: Any) -> int:
    dest = getattr(args, "destination", None)
    result = list_tasks(destination=dest)
    if not result["ok"] and result["exit"] == 127:
        print("rig not installed")
        return 2
    print("Task                         Owner             State")
    rows = parse_queue_table(result["output"])
    if rows:
        for r in rows:
            print(f"{r['task'][:28]:<28} {r['owner']:<17} {r['state']}")
    else:
        print(result["output"] or "(no tasks / unable to parse)")
    return 0 if result["ok"] else 1


def cmd_team_messages(_: Any) -> int:
    result = list_messages()
    print(result["output"] or "(no messages)")
    return 0 if result["ok"] else 1


def cmd_team_restore_check(args: Any) -> int:
    result = restore_check(getattr(args, "target", None))
    print(f"restore-check: {result['state']}")
    if result["output"]:
        print(result["output"])
    return 0 if result["ok"] or result["state"] != "unavailable" else 2


def cmd_team_reconcile(args: Any) -> int:
    """Compare desired DOTS policy vs seat projection; report drift without killing seats."""
    cfg = load_config()
    template = args.template
    roles, defaults = load_roles()
    from dots_agent.openrig.provision import pi_seat_agent_dir, seat_session_name

    print(f"Reconcile {template}")
    print("─" * 40)
    for role_name in role_names_for_template(template, defaults):
        session = seat_session_name(pod_id="team", member_id=role_name, rig_name=template)
        agent_dir = pi_seat_agent_dir(session)
        state = "MISSING"
        if agent_dir.is_dir() and (agent_dir / "dots-seat.json").is_file():
            meta = json.loads((agent_dir / "dots-seat.json").read_text(encoding="utf-8"))
            pol = roles[role_name]
            if meta.get("sandbox") == pol.sandbox and meta.get("role") == role_name:
                state = "SATISFIED"
            else:
                state = "DRIFT"
        print(f"  {role_name:<16} {state}")
        if state == "DRIFT" and getattr(args, "apply", False):
            print("    (apply not performed on running seats — reprovision explicitly)")
    print()
    print("No active seats were restarted.")
    return 0


def cmd_team_run(args: Any) -> int:
    """Create top-level work via OpenRig send/queue — does not block until done."""
    team = args.team
    text = " ".join(args.task)
    dest = f"team-lead@{team}"
    # Common address shape: team-lead@dots-triad
    from dots_agent.openrig.queue import create_task

    if args.detach or not args.follow:
        result = create_task(destination=dest, text=text)
        print(result["output"] or f"queued to {dest}")
        print(f"destination: {dest}")
        return 0 if result["ok"] else 1
    result = create_task(destination=dest, text=text)
    print(result["output"])
    print("--follow: watching summarized events (Ctrl-C to detach)")
    # Minimal follow: poll queue list a few times
    for _ in range(5):
        tasks = list_tasks(destination=dest)
        print(tasks["output"][:500] if tasks["output"] else "…")
        time.sleep(2)
    return 0


def cmd_team_diff(args: Any) -> int:
    """Show worktree diffs for a team run mapping."""
    cfg = load_config()
    path = team_state_dir(cfg) / "team_runs.jsonl"
    if not path.is_file():
        print("no team runs recorded")
        return 1
    rows = [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
    match = None
    for r in reversed(rows):
        if r.get("rig") == args.rig or r.get("dots_team_run_id") == args.rig:
            match = r
            break
    if not match:
        print("team run not found")
        return 1
    for role, wt in (match.get("worktrees") or {}).items():
        print(f"=== {role} ({wt}) ===")
        if Path(wt).is_dir():
            proc = subprocess.run(
                ["git", "-C", wt, "diff", "--stat"],
                capture_output=True,
                text=True,
                check=False,
            )
            print(proc.stdout or "(clean)")
    print("Primary checkout not modified (apply explicitly).")
    return 0
