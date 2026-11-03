# dots-triad workflow (OpenRig queue-backed)

DOTS does not implement a parallel state machine. Use OpenRig queue + this policy:

```text
plan (lead)
  → build (builder)
  → review (reviewer)
  → fix if needed (builder)   # max 2 correction rounds
  → verify (reviewer)
  → done (lead)
  → else escalate to human
```

Bounded review cycles: `roles.toml` → `[team].max_review_rounds` (default 2).

Verification evidence required before lead marks complete:

- verification command + exit status
- reviewer verdict
- diff / artifact reference

Human attention from OpenRig is surfaced, never auto-answered (Phase 4).
