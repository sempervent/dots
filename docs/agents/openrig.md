# OpenRig orchestration

OpenRig coordinates persistent multi-agent teams. DOTS continues to own
execution safety, model selection, budgets, local-first policy, and remote
escalation.

## Ownership

| Concern | Owner |
|---------|--------|
| **fnm** (Node version manager) | **DOTS** |
| Node + npm (active managed runtime) | **DOTS / fnm** |
| OpenRig CLI (`@openrig/cli` / `rig`) | **DOTS** (install + ABI verify) |
| tmux prefix/policy, Herdr | **DOTS** |
| Pi / Codex install | **DOTS** |
| LiteLLM, sandbox, routing, MCP trust | **DOTS** |
| Team templates / seat projection | **DOTS** |
| Daemon, kernel, queue, seat lifecycle | **OpenRig** |
| Snapshots / restore / OpenRig views | **OpenRig** |

DOTS uses **fnm** only. DOTS does **not** install or source **nvm**.

DOTS does **not** run `rig setup` (avoids rewriting `~/.tmux.conf` and
reinstalling Herdr/providers). A small DOTS-managed tmux fragment enables
mouse/scrollback only — prefix stays Ctrl-Space.

## Install (desired state)

```bash
./dots setup --with openrig
# or --with ai  (includes openrig)
```

Convergence chain:

```text
ensure fnm
  → ensure supported Node (preferred major 22; accepted 22/24)
  → activate DOTS-selected Node
  → verify npm belongs to that Node (user-owned global prefix; never sudo)
  → npm install -g @openrig/cli under that npm
  → verify rig under the active npm prefix
  → run Node/SQLite ABI check
  → merge DOTS tmux fragment
  → PASS
```

Policy file: `configs/agents/openrig/runtime.toml` (reviewed against OpenRig
0.7.7 / 2026-11-03). Upstream requires Node **22 or 24** (Apple silicon:
prefer 22). DOTS prefers major **22** when installing; an already-active
accepted major with a matching npm is preserved.

Never `curl | sh`. Never `sudo npm`.

### Node migration

Global npm packages under fnm are **Node-version-specific**. Switching the
active major may leave a stale `rig` earlier on `PATH`. DOTS detects
wrong-prefix installs and reinstalls `@openrig/cli` under the active npm.

### ABI validation

`npm install` success is not enough (npm 11+ may skip install scripts). After
install DOTS runs:

```bash
node "$(npm root -g)/@openrig/cli/scripts/check-abi.mjs"
```

using the same `node`/`npm` pair that performed the install. One safe reinstall
is attempted on ABI failure; then setup fails with doctor remediation.

## Doctor

```bash
./dots agent team doctor
```

Read-only. Reports fnm / Node / npm / OpenRig / ABI / integration and prints
`./dots setup --with openrig` when diverged. Never installs.

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
