# OpenRig orchestration (Phase 4)

OpenRig coordinates persistent multi-agent teams. DOTS continues to own
execution safety, model selection, budgets, local-first policy, and remote
escalation.

## Ownership

| Concern | Owner |
|---------|--------|
| Node, tmux prefix/policy, Herdr | **DOTS** |
| Pi / Codex install | **DOTS** |
| LiteLLM, sandbox, routing, MCP trust | **DOTS** |
| Team templates / seat projection | **DOTS** |
| Daemon, kernel, queue, seat lifecycle | **OpenRig** |
| Snapshots / restore / OpenRig views | **OpenRig** |

DOTS does **not** run `rig setup` (avoids rewriting `~/.tmux.conf` and
reinstalling Herdr/providers). A small DOTS-managed tmux fragment enables
mouse/scrollback only — prefix stays Ctrl-Space.

## Install

```bash
./setup.sh --with openrig
# or --with ai  (includes openrig)
```

Uses `npm install -g @openrig/cli` (reviewed version recorded in
`configs/agents/defaults.toml` / `helpers/openrig.sh`). Never `curl | sh`.

Requires Node ≥22 and tmux. Herdr preferred for operator UI; plain tmux fallback.

## Teams

| Template | Roles |
|----------|--------|
| `dots-pair` | lead, builder |
| `dots-triad` | lead, builder, reviewer (default) |
| `dots-investigate` | lead, investigator, builder |

Specs: `configs/agents/openrig/`

## Pi seat isolation

OpenRig Pi seats use `$OPENRIG_HOME/state/pi/<session>/agent` with
`PI_CODING_AGENT_DIR` — **not** `~/.pi/agent`.

DOTS projects only:

- `models.json` (provider defs)
- safe MCP allowlist (`dots-model-scout`, `dots-expert`)
- role-specific `sandbox.json`
- `DOTS_ROLE.md`

Never symlinks the whole user Pi agent dir. Never copies history or unrelated MCP.

## Commands

```bash
./dots agent team status
./dots agent team list
./dots agent team up dots-triad --project ~/dev/foo --dry-run
./dots agent team up dots-triad --project ~/dev/foo
./dots agent team open
./dots agent team tasks
./dots agent team messages
./dots agent team restore-check
./dots agent team down dots-triad
./dots agent team doctor
```

Advanced OpenRig operations: use `rig` directly.

## Budget

Team remote-expert budget defaults to **$3.00** (SQLite, atomic reservations).
Codex/Claude subscription usage is reported separately as unknown — never
fabricated as OpenRouter dollars.

## Workflow

OpenRig queue is authoritative for task ownership/handoff. DOTS ledger remains
authoritative for cost, routing, sandbox, verification. Triad review cycles are
bounded (`max_review_rounds = 2`) then escalate; richer recovery is owned by
[autonomy](autonomy.md) (Phase 5).
