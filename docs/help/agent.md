# Agent Harness

DOTS Phase 1 local-first agent orchestration:

```text
Pi (local) → model-scout MCP → budget → LiteLLM → OpenRouter → local verify
```

## Commands

```bash
./dots agent status
./dots agent doctor
./dots agent models
./dots agent scout --task debugging --tools --quality strong --max-cost 0.50
./dots agent run --auto --budget 1.00 "Diagnose and fix the failing test."
./dots agent costs
```

## Components

| Id | Role |
|----|------|
| `pi` | Local coding-agent runtime (npm; Node ≥22.19) |
| `litellm` | Localhost gateway (Compose binds `127.0.0.1:4000`) |

Selecting `pi` alone does **not** authorize OpenRouter.

## Safety

- Remote expert tools have **no filesystem/shell access**.
- DOTS enforces a hard session budget before every billable call.
- OS-level sandboxing is **not** implemented — agent runs as your user.
- Credentials appear as `SET` / `UNSET` only in doctor/status.
