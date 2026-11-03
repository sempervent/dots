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

## Deferred (later PRs)

- OpenRig session/topology orchestration
- OS-level sandboxing
- Agent eval suite / capability benchmarking
- Multi-agent orchestration / consensus
- Advanced automatic failure heuristics

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
