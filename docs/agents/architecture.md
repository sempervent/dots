# Agent architecture (v1.6 Phase 1)

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
| OS sandbox / OpenRig / evals | **DEFERRED** (see [v1.6-roadmap](v1.6-roadmap.md)) |

## Deferred (Phases 2–5)

- OpenRig session/topology orchestration
- OS-level sandboxing
- Agent eval suite / capability benchmarking
- Multi-agent orchestration / consensus
- Advanced automatic failure heuristics

See [v1.6-roadmap.md](v1.6-roadmap.md).

## Threat model (acknowledged, not fully solved)

| Risk | Mitigation in Phase 1 |
|------|------------------------|
| Prompt injection in repo content | Compact explicit context packet; local review of advice |
| Secret exfiltration | Redaction/reject heuristics; never log keys |
| Budget runaway | DOTS-side reserve/settle before each call |
| Malicious MCP output | Separate scout vs expert; local agent applies changes |
| Pi host permissions | Explicit warning; recommend worktree/container |
| LiteLLM exposure | Bind `127.0.0.1` only by default |
| Catalog staleness | TTL cache + age reporting; refuse ancient cache |

## Privacy

- **Scouting** sends a catalog HTTP request only (no task/source).
- **Consultation** sends an explicit context packet only (not the whole repo).
