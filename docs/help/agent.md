# Agent Harness

DOTS local-first agent orchestration (v1.6):

```text
OpenRig team → Pi seats (sandboxed) → eval routing → guarded autonomy
  → LiteLLM experts → verify → resume/replay/observe
```

## Commands

```bash
./dots agent status
./dots agent doctor
./dots agent sandbox status
./dots agent models
./dots agent scout --task debugging --tools --quality strong --max-cost 0.50
./dots agent route --task debugging --language python --quality strong --simulate
./dots agent eval list
./dots agent eval run --local --suite smoke
./dots agent eval results
./dots agent team status
./dots agent team up dots-triad --project . --dry-run
./dots agent team open
./dots agent run --task-class debugging "Diagnose and fix the failing test."
./dots agent run --in-place "…"
./dots agent run --unsafe-host "…"                             # explicit bypass
./dots agent failures
./dots agent metrics
./dots agent inspect RUN_ID
./dots agent timeline RUN_ID
./dots agent resume RUN_ID
./dots agent replay RUN_ID
./dots agent worktrees
./dots agent mcp status
./dots agent costs
```

## Agent Evaluations

See [evals](../agents/evals.md). Deterministic scorers only; no LLM-as-judge.

## Model Routing

See [model-scout](../agents/model-scout.md). Expected cost-to-success when
empirical evidence is adequate; curated capability registry otherwise.

## Autonomy

See [autonomy](../agents/autonomy.md). Default mode is **guarded**. Replay is
offline (zero network / mutations / billable calls).

## Components

| Id | Role |
|----|------|
| `pi` | Local coding-agent runtime (npm; Node ≥22.19) |
| `litellm` | Localhost gateway (Compose binds `127.0.0.1:4000`) |
| `agent-sandbox` | Sandbox policy + OS backends (provider: pi-sandbox) |
| `openrig` | Persistent multi-agent teams — `./dots setup --with openrig` converges fnm, Node, `@openrig/cli`, and ABI |

Selecting `pi` alone does **not** authorize OpenRouter. See [OpenRig teams](../agents/openrig.md).
DOTS uses **fnm** (never nvm) for the Node that installs OpenRig.

## Safety

- Default runs are **sandboxed** (fail-closed). See [Agent Security](agent-security.md).
- Remote expert tools have **no filesystem/shell access**.
- DOTS enforces a hard session budget before every billable call.
- Credentials appear as `SET` / `UNSET` only in doctor/status.
- Autonomy never overrides sandbox, budget, credentials, or unsafe-host consent.
