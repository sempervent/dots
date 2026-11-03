# Agent Harness

DOTS local-first agent orchestration (Phases 1–2):

```text
Pi (sandboxed) → worktree → model-scout MCP → budget → LiteLLM → OpenRouter → verify
```

## Commands

```bash
./dots agent status
./dots agent doctor
./dots agent sandbox status
./dots agent models
./dots agent scout --task debugging --tools --quality strong --max-cost 0.50
./dots agent run "Diagnose and fix the failing test."          # safe default
./dots agent run --in-place "…"
./dots agent run --unsafe-host "…"                             # explicit bypass
./dots agent worktrees
./dots agent mcp status
./dots agent costs
```

## Components

| Id | Role |
|----|------|
| `pi` | Local coding-agent runtime (npm; Node ≥22.19) |
| `litellm` | Localhost gateway (Compose binds `127.0.0.1:4000`) |
| `agent-sandbox` | Sandbox policy + OS backends (provider: pi-sandbox) |

Selecting `pi` alone does **not** authorize OpenRouter.

## Safety

- Default runs are **sandboxed** (fail-closed). See [Agent Security](agent-security.md).
- Remote expert tools have **no filesystem/shell access**.
- DOTS enforces a hard session budget before every billable call.
- Credentials appear as `SET` / `UNSET` only in doctor/status.
