# Agent evaluations

Phase 3 adds a small, deterministic eval suite so Model Scout can prefer the
model with the lowest **expected cost of successfully completing** a task class
— not merely the cheapest API request.

## Philosophy

```text
small · repeatable · locally verifiable · task-specific
```

No LLM-as-judge primary path. Scorers are command exit codes, filesystem
outcomes, JSON exact match, or JSON Schema.

## Task classes

`coding` · `debugging` · `reasoning` · `tool_use` · `structured_output` ·
`repo_navigation`

Registry: `configs/agents/evals/registry.toml`  
Fixtures: `tools/dots_agent/dots_agent/evals/fixtures/`

## Commands

```bash
./dots agent eval list
./dots agent eval run --local --suite smoke
./dots agent eval results
./dots agent eval compare MODEL_A MODEL_B
./dots agent eval regressions
./dots agent eval baseline RUN_ID
./dots agent eval calibrate
./dots agent eval import-openrouter   # optional secondary evidence only
```

Remote/paid evals require explicit `--remote` and `--budget`. Normal CI uses
mock/oracle solvers only.

## Evidence storage

```text
$XDG_STATE_HOME/dots/agents/evals/
  runs/<eval-run-id>.jsonl
  summary/<model>.json
  baseline.json
  external/openrouter-benchmarks.json
```

## Statistics

- Success estimator: binomial pass/fail
- Confidence: **Wilson lower bound** (stdlib; no SciPy)
- Minimum evidence: `routing.evidence.minimum_attempts` (default 5)
- Staleness: `routing.evidence.max_age_days` (default 90) — old data kept,
  but not used as authoritative routing evidence

## Isolation

Mutation tasks copy fixtures into a temp directory and require the Phase 2
sandbox boundary (fail-closed). The live DOTS checkout is never the eval
workspace. Fixtures use synthetic credentials only.
