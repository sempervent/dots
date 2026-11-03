# Agent architecture (v1.6)

## Vertical slice

```text
Pi local model
   ↓
model-scout MCP   (OpenRouter catalog metadata only)
   ↓
DOTS hard budget
   ↓
LiteLLM Gateway   (127.0.0.1:4000)
   ↓
OpenRouter        (completion)
   ↓
local Pi applies advice + verifies
```

## Responsibility boundaries

| Layer | Owns |
|-------|------|
| Pi | Local tools, edits, verification, escalation *decision* |
| dots-model-scout | Read-only model discovery/selection |
| DOTS budget | Hard session spend + remote call caps |
| LiteLLM | Provider abstraction + OpenRouter requests |
| OpenRouter | Live remote marketplace + provider price routing |
| dots-expert | Billable consultation (text in → text out; no FS) |

## Phase 1 evidence (use these labels only)

| Claim | Status |
|-------|--------|
| Model scout selection + cost estimate | **MOCKED** (+ live metadata when network available) |
| Budget reserve → LiteLLM mock → settle → ledger | **MOCKED** (Phase 1 acceptance test) |
| Connection-refused does not fabricate spend | **MOCKED** |
| Runtime launchers never `uv sync` | **PROVEN** (code + shell gate) |
| LiteLLM non-predictable master key | **CONFIGURED** (generated at setup; compose requires env) |
| Pi `models.json` structured merge | **MOCKED** (+ live when local provider present) |
| Pi RPC local inference | **PROVEN** on machines with Pi + local model (else SKIP) |
| MCP tools/list + `pi mcp list` discovery | **PROVEN** when executables / Pi present |
| OS sandbox / worktrees / MCP trust | **implemented** (Phase 2) |
| Eval-driven expected-cost routing | **implemented** (Phase 3; see [evals](evals.md), [model-scout](model-scout.md)) |
| OpenRig multi-agent orchestration | **implemented** (Phase 4; see [openrig](openrig.md)) |
| Guarded autonomy / recovery / resume / replay | **implemented** (Phase 5; see [autonomy](autonomy.md)) |

## Stretch / Final

- Multi-model consensus (stretch; not required for v1.6.0)
- Full CI / release convergence (Final gate)

See [v1.6-roadmap.md](v1.6-roadmap.md).

## Threat model

See [security.md](security.md) for the Phase 2 trust boundary (sandbox,
worktrees, env isolation, MCP allowlist). Summary:

| Risk | Mitigation |
|------|------------|
| Prompt injection in repo content | Compact context packet; sandboxed tools |
| Secret exfiltration | Env scrub; deny paths; bash network deny; redaction |
| Budget runaway | DOTS-side reserve/settle before each call |
| Malicious MCP output | Allowlist; scout vs expert; no FS on MCP |
| Pi host permissions | Safe mode default; `--unsafe-host` explicit only |
| LiteLLM exposure | Bind `127.0.0.1` only by default |
| Catalog staleness | TTL cache + age reporting |
| Primary checkout corruption | Git worktree isolation; explicit apply |

## Privacy

- **Scouting** sends a catalog HTTP request only (no task/source).
- **Consultation** sends an explicit context packet only (not the whole repo).
