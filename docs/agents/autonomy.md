# Autonomous recovery and observability (Phase 5)

Bounded autonomy for agent runs. Autonomy **never** overrides sandbox, budget,
credentials, unsafe-host consent, or human-required gates.

## Modes

| Mode | Behavior |
|------|----------|
| `manual` | Failures surface as human attention; no automatic recovery |
| `guarded` | **Default.** Transient retry → local replan → remote expert; team reroute escalates to attention |
| `auto` | Full ladder including team reroute within bounds |

Policy: `configs/agents/autonomy.toml` (`policy_version`).

## Recovery ladder

```text
transient_retry
    ↓
local_replan
    ↓
remote_expert
    ↓
team_reroute
    ↓
human_attention
```

Each step is counter-bounded (`max_transient_retries`, `max_local_replans`,
`max_expert_escalations`, `max_team_reroutes`). Identical failure fingerprints
escalate to human attention after `max_identical_fingerprints`.

## Structural failure detection

Decisions use **only** structural signals:

```text
exit status · typed errors · verification state · failure fingerprint
workflow / attention / progress state · iteration counters · budget state
```

Natural-language model phrases are **not** used for stuck/failure detection.

## Outcomes

| Outcome | Meaning |
|---------|---------|
| `COMPLETED` | Run finished without an explicit verification proof |
| `VERIFIED` | Explicit verification proof succeeded |
| `NEEDS_ATTENTION` | Human attention required |
| `RECONCILIATION_REQUIRED` | Billable call may have been sent; response not persisted |
| `SANDBOX_BLOCKED` / `BUDGET_BLOCKED` / `POLICY_BLOCKED` | Hard stops |

An LLM saying “done” is not verification.

## Forbidden automation

Automation must never:

```text
increase budget · disable sandbox · switch to unsafe-host
read protected secrets · broaden filesystem/network permissions
run sudo · git push / force-push · external deploy
```

## Resume

`dots agent resume RUN_ID` restores checkpointed:

```text
money spent · budget remaining · retry/expert/reroute counters
autonomy mode · worktree path · pending billable state
```

Allowances are **not** refreshed.

## Replay

`dots agent replay RUN_ID` recomputes recovery decisions from stored structural
events only:

```text
model calls = 0 · network calls = 0 · billable calls = 0 · mutations = 0
```

## Idempotency

If an expert request may have been sent and the response is not yet persisted,
state becomes `RECONCILIATION_REQUIRED` — never blindly re-issue a paid call.
Identical expert packets within a run are deduplicated.

## Observability CLI

```text
dots agent inspect RUN_ID
dots agent timeline RUN_ID
dots agent failures
dots agent attention
dots agent metrics
dots agent cancel RUN_ID
dots agent resume RUN_ID
dots agent replay RUN_ID
```

## Security wording

Remote experts receive explicit context packets and do not have direct
filesystem/shell access. Agent command execution is sandboxed/restricted by
default. Unsafe host execution requires explicit user opt-in.
