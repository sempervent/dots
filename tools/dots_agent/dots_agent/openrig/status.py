"""OpenRig / team status and doctor probes (read-only; no network scout)."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any

from dots_agent.config import AgentConfig, load_config
from dots_agent.openrig.roles import load_roles
from dots_agent.openrig.team_budget import TeamBudget
from dots_agent.openrig.terminal import terminal_status_report
from dots_agent.providers import detect_local


def _run(cmd: list[str], *, timeout: float = 15.0) -> tuple[int, str]:
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, check=False
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        return proc.returncode, out.strip()
    except FileNotFoundError:
        return 127, "not found"
    except subprocess.TimeoutExpired:
        return 124, "timeout"


def openrig_home() -> Path:
    return Path(os.environ.get("OPENRIG_HOME", str(Path.home() / ".openrig"))).expanduser()


def team_state_dir(cfg: AgentConfig | None = None) -> Path:
    cfg = cfg or load_config()
    p = cfg.state_dir() / "openrig"
    p.mkdir(parents=True, exist_ok=True)
    return p


def mapping_path(cfg: AgentConfig | None = None) -> Path:
    return team_state_dir(cfg) / "team_runs.jsonl"


def append_mapping(record: dict[str, Any], cfg: AgentConfig | None = None) -> None:
    path = mapping_path(cfg)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, sort_keys=True) + "\n")


def build_team_status(
    *,
    team_id: str | None = None,
    cfg: AgentConfig | None = None,
    refresh: bool = False,
) -> dict[str, Any]:
    """Assemble status. Never queries OpenRouter unless refresh=True (still catalog only)."""
    _ = refresh  # reserved for future catalog refresh; status stays offline by default
    cfg = cfg or load_config()
    roles, defaults = load_roles(cfg.root / "configs" / "agents" / "openrig" / "roles.toml")
    local = detect_local(cfg)
    term = terminal_status_report()

    rig_bin = shutil.which("rig")
    version = ""
    daemon = "unknown"
    kernel = "unknown"
    if rig_bin:
        code, out = _run([rig_bin, "--version"])
        version = out.split("\n")[0] if out else ""
        code, st = _run([rig_bin, "status"])
        daemon = "ok" if code == 0 else "degraded"
        if "Kernel" in st or "kernel" in st.lower():
            kernel = "present"
        else:
            kernel = "unknown"

    budget_info: dict[str, Any] | None = None
    if team_id:
        db = team_state_dir(cfg) / "team_budget.sqlite"
        tb = TeamBudget(db, team_id=team_id, budget_usd=defaults.team_budget_usd)
        budget_info = tb.snapshot()

    return {
        "openrig": {
            "installed": bool(rig_bin),
            "version": version,
            "daemon": daemon,
            "kernel": kernel,
            "state_root": str(openrig_home()),
            "reviewed": "0.7.7",
        },
        "terminal": term,
        "agent_policy": {
            "sandbox": "enabled",
            "routing": "eval-driven",
            "gateway": "LiteLLM",
        },
        "local": {
            "provider": local.name,
            "model": local.model or "(none)",
        },
        "roles": {
            name: {
                "task_class": r.task_class,
                "quality": r.quality,
                "sandbox": r.sandbox,
                "write": r.write,
            }
            for name, r in roles.items()
        },
        "budget": budget_info
        or {
            "team_budget_usd": defaults.team_budget_usd,
            "note": "no active team_id — defaults only",
        },
        "templates": list(defaults.templates.keys()),
        "attention": [],  # filled when rig ps available
        "warnings": [],
    }


def print_team_status(rep: dict[str, Any]) -> None:
    o = rep["openrig"]
    t = rep["terminal"]
    print("DOTS Agent Team Status")
    print("─" * 40)
    print()
    print("OpenRig")
    print(f"  installed       {'yes' if o['installed'] else 'no'}")
    print(f"  version         {o['version'] or '—'}")
    print(f"  daemon          {o['daemon']}")
    print(f"  kernel          {o['kernel']}")
    print(f"  state root      {o['state_root']}")
    print()
    print("Terminal")
    print(f"  provider        {t['preferred']}")
    print(f"  herdr           {'yes' if t['herdr_installed'] else 'no'}")
    print(f"  tmux            {'yes' if t['tmux_installed'] else 'no'}")
    print()
    print("Agent policy")
    ap = rep["agent_policy"]
    print(f"  sandbox         {ap['sandbox']}")
    print(f"  routing         {ap['routing']}")
    print(f"  gateway         {ap['gateway']}")
    print()
    print("Local")
    print(f"  provider        {rep['local']['provider']}")
    print(f"  model           {rep['local']['model']}")
    print()
    print("Budget")
    b = rep["budget"]
    if "remaining_usd" in b:
        print(f"  team budget     ${b['budget_usd']:.2f}")
        print(f"  spent           ${b['spent_usd']:.4f}")
        print(f"  reserved        ${b['reserved_usd']:.4f}")
        print(f"  remaining       ${b['remaining_usd']:.4f}")
    else:
        print(f"  team budget     ${b.get('team_budget_usd', 3.0):.2f}")
        print(f"  note            {b.get('note', '')}")
    print()
    print("Templates")
    for name in rep.get("templates") or []:
        print(f"  {name}")


def doctor_checks(cfg: AgentConfig | None = None) -> list[tuple[str, str]]:
    """Lightweight read-only probes (no installs). Prefer helpers/openrig.sh doctor in CLI."""
    cfg = cfg or load_config()
    rows: list[tuple[str, str]] = []
    rows.append(("fnm", "OK" if shutil.which("fnm") else "FAIL missing"))
    node = shutil.which("node")
    npm = shutil.which("npm")
    if node:
        code, ver = _run([node, "-v"])
        major = (ver or "").lstrip("v").split(".", 1)[0]
        if major in ("22", "24"):
            rows.append(("node", f"OK {ver} (accepted OpenRig major)"))
        else:
            rows.append(("node", f"FAIL {ver} (need 22 or 24)"))
    else:
        rows.append(("node", "FAIL missing"))
    if npm:
        rows.append(("npm", f"OK {shutil.which('npm')}"))
    else:
        rows.append(("npm", "FAIL missing"))
    if shutil.which("rig"):
        code, ver = _run(["rig", "--version"])
        rows.append(("openrig_cli", f"OK {ver.splitlines()[0] if ver else ''}"))
        code, _ = _run(["rig", "doctor"])
        rows.append(("openrig_doctor", "OK" if code == 0 else "WARN"))
    else:
        rows.append(("openrig_cli", "FAIL missing — ./dots setup --with openrig"))
    rows.append(("tmux", "OK" if shutil.which("tmux") else "FAIL"))
    rows.append(("herdr", "OK" if shutil.which("herdr") else "WARN missing (tmux fallback)"))
    rows.append(("pi", "OK" if shutil.which("pi") else "WARN missing"))
    rows.append(("codex", "OK" if shutil.which("codex") else "WARN optional"))
    conf = Path.home() / ".tmux.conf"
    if conf.is_file() and "BEGIN DOTS-OPENRIG" in conf.read_text(encoding="utf-8", errors="ignore"):
        frag = conf.read_text(encoding="utf-8", errors="ignore")
        if "set -g prefix" in frag.split("BEGIN DOTS-OPENRIG")[-1].split("END DOTS-OPENRIG")[0]:
            rows.append(("tmux_fragment", "FAIL sets prefix"))
        else:
            rows.append(("tmux_fragment", "OK"))
    else:
        rows.append(("tmux_fragment", "WARN not merged"))
    root = cfg.root / "configs" / "agents" / "openrig"
    for t in ("dots-pair", "dots-triad", "dots-investigate"):
        ok = (root / "rigs" / f"{t}.yaml").is_file()
        rows.append((f"rigspec_{t}", "OK" if ok else "FAIL"))
    rows.append(("runtime_policy", "OK" if (root / "runtime.toml").is_file() else "FAIL"))
    return rows
