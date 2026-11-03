# LiteLLM gateway

Component id: `litellm`.

## Layout

```text
services/litellm/
  compose.yml     # publishes 127.0.0.1:4000 only
  config.yaml     # model_list + OpenRouter pass-through
```

## Purpose

- Provider abstraction for remote experts
- OpenRouter requests (`openrouter/<provider>/<model>`)
- Retries / routing (LiteLLM)
- Cost metadata telemetry

## Host vs container bind

- **Host exposure (required):** Docker publishes `127.0.0.1:4000` only.
- **Inside the container:** LiteLLM may listen on `0.0.0.0:4000` on the
  container network namespace. That is normal and is **not** the same as
  publishing the port on all host interfaces.

## What LiteLLM does **not** own in Phase 1

Persistent DB-backed budget enforcement. DOTS implements a hard session budget
in the harness/`dots-expert` path. LiteLLM spend logs are additional telemetry.

## Credentials

```text
OPENROUTER_API_KEY   # required for remote experts; never committed
LITELLM_MASTER_KEY   # required for gateway auth; never a shared default
```

`./dots setup --with litellm` generates a random key at:

```text
~/.config/dots/secrets/litellm-master-key   # mode 0600
```

Honor an explicitly provided `LITELLM_MASTER_KEY` if already set. Compose
requires the variable (no predictable fallback such as `sk-dots-litellm-local`).

Doctor reports `LiteLLM master key SET|UNSET` only — the value is never printed,
logged, or written to the ledger.
