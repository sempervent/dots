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

## What LiteLLM does **not** own in Phase 1

Persistent DB-backed budget enforcement. DOTS implements a hard session budget
in the harness/`dots-expert` path. LiteLLM spend logs are additional telemetry.

## Credentials

```text
OPENROUTER_API_KEY   # required for remote experts; never committed
LITELLM_MASTER_KEY   # optional local gateway key (default sk-dots-litellm-local)
```

Doctor reports `SET` / `UNSET` only.
