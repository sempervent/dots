# Model Scout (evidence-based)

Model Scout selects a **model**. LiteLLM/OpenRouter still select provider
deployment for that model. DOTS budget controls spend. Pi executes locally.
The eval subsystem supplies empirical quality evidence.

## Selection order

```text
1. hard API capability constraints
2. quality / reliability floor
3. context requirement
4. budget
5. minimize expected cost-to-success (empirical) else request cost (curated)
6. latency tie-breaker (balanced preference)
7. model ID deterministic final tie-break
```

## Formulas

```text
estimated_attempt_cost = input_tokens * prompt_price + output_tokens * completion_price

conservative_success_probability = Wilson_lower(successes, attempts)

expected_cost_to_success = estimated_attempt_cost / conservative_success_probability
```

Local models use API cost `$0`. With adequate empirical reliability they win
under economy preference — local-first as an empirical result.

## Evidence hierarchy

| Rank | Source | Role |
|------|--------|------|
| 1 | Exact-model DOTS eval evidence | Authoritative when `attempts ≥ minimum` and not stale |
| 2 | Imported external benchmarks | Tie-break / bootstrap only — **not** task success probability |
| 3 | Curated `model-capabilities.toml` | Bootstrap prior |
| 4 | Unrated | Never satisfies an explicit quality floor above `unrated` |

Popularity rankings are informational only.

## Inspect routing

```bash
./dots agent route \
  --task debugging \
  --language python \
  --context 12000 \
  --output 3000 \
  --quality strong \
  --max-cost 0.50 \
  --simulate
```

`--simulate` uses cached catalog + stored evidence; no inference calls.

`routing_policy_version` is recorded with decisions (currently `1`).
