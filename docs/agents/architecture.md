# Agent architecture

DOTS runs a **local-first** agent stack: Pi does the work on your machine;
remote models are consulted only when policy and evidence say they are worth
the spend. This page is the current system overview for GitHub Pages — not a
frozen release snapshot. Delivery history lives in the
[roadmap](v1.6-roadmap.md). Explorable diagrams:
[Architecture diagrams](diagrams.md).

## End-to-end control flow

```text
operator / CLI
      │
      ▼
dots agent run / team
      │
      ├─► Git worktree (default) + pi-sandbox + MCP allowlist
      │
      ├─► Pi (local model + tools)
      │         │
      │         ├─ model-scout (catalog / selection metadata)
      │         ├─ eval evidence → expected-cost routing
      │         └─ DOTS budget reserve → LiteLLM (127.0.0.1:4000)
      │                                      → expert / OpenRouter
      │                                      → settle ledger
      │
      ├─► OpenRig teams (optional): seats projected into sandboxed Pi
      │
      └─► autonomy: structural failure fingerprint → recovery ladder
                   → resume / replay / attention / metrics
```

Safe mode never auto-falls back to unrestricted host execution. See
[security](security.md).

## Ownership

| Concern | Owner |
|---------|--------|
| Desired-state install (`./dots setup --with …`) | **DOTS** |
| Sandbox, worktrees, env scrub, MCP allowlist | **DOTS** |
| Model scout, evals, expected-cost routing, budget/ledger | **DOTS** |
| LiteLLM localhost gateway + Pi models merge | **DOTS** |
| fnm / Node / npm / `@openrig/cli` install + ABI check | **DOTS** |
| tmux fragment, Herdr views, team templates / seat projection | **DOTS** |
| Local tools, edits, verification, escalation *decision* | **Pi** |
| Daemon, kernel, queue, seat lifecycle, snapshots | **OpenRig** |
| Live remote marketplace / provider prices | **OpenRouter** (via LiteLLM) |

DOTS uses **fnm** only. It does **not** install or source **nvm**, run
`rig setup`, or use `sudo npm`.

## Capability map

| Capability | What it does | Deep dive |
|------------|--------------|-----------|
| Local harness | Pi, Ollama/llama.cpp, Hermes/OpenCode/Codex/Cursor wiring | [harness](harness.md) |
| Trust boundary | Safe/in-place/unsafe-host; OS sandbox; credential isolation | [security](security.md) |
| Model Scout | Read-only catalog + selection; no task source exfiltration | [model-scout](model-scout.md) |
| Evaluations | Deterministic task-class evidence for routing | [evals](evals.md) |
| LiteLLM / expert | Localhost gateway; billable consult text-in/text-out | [litellm](litellm.md) |
| OpenRig teams | Multi-agent seats under DOTS safety + budgets | [openrig](openrig.md) |
| Autonomy | Guarded recovery ladder; resume/replay/observe | [autonomy](autonomy.md) |
| OpenRig install | fnm → Node → npm → CLI → ABI → doctor | [openrig](openrig.md#install-desired-state) |

## Routing policy (summary)

Prefer local success. When consulting remote models, route on **expected cost of
success**, not cheapest request price alone:

```text
local-first
  → empirical Wilson floor for the task class
  → expected cost = request cost / P(success)
  → remote only when eligible under budget + policy
```

Normal CI uses mock/oracle solvers. Paid remote evals require explicit flags.
Details: [evals](evals.md), [model-scout](model-scout.md).

## Trust invariants (summary)

| Invariant | Rule |
|-----------|------|
| Default mode | Sandboxed + worktree when in a Git repo; fail closed |
| No silent escape | Never auto-fallback to `--unsafe-host` |
| Secrets | Env scrub; deny sensitive paths; redact |
| MCP | Allowlist only; scout/expert have no filesystem |
| LiteLLM | Bind `127.0.0.1` by default |
| Autonomy | Never overrides sandbox, budget, credentials, or human gates |

Full threat model: [security](security.md). Autonomy bounds:
[autonomy](autonomy.md).

## OpenRig install chain

```text
./dots setup --with openrig
  → ensure fnm
  → ensure supported Node (prefer 22; accept 22/24)
  → verify npm on that Node (user-owned prefix)
  → npm install -g @openrig/cli
  → ABI check (check-abi.mjs)
  → merge DOTS tmux fragment
  → doctor reports PASS / remediation
```

## Privacy

- **Scouting** sends a catalog HTTP request only (no task/source).
- **Consultation** sends an explicit context packet only (not the whole repo).
- **Replay** is offline: no network, mutations, or billable calls.

## Diagrams

Explorable Archify HTML (dark/light, pan/zoom, export):

- [System overview](../diagrams/dots-agent-system-overview.html)
- [Trust boundary](../diagrams/dots-agent-trust-boundary.html)
- [Routing and eval](../diagrams/dots-agent-routing-eval.html)
- [OpenRig teams](../diagrams/dots-openrig-teams.html)
- [Autonomy ladder](../diagrams/dots-agent-autonomy-ladder.html)
- [OpenRig install](../diagrams/dots-openrig-install.html)

Index: [Architecture diagrams](diagrams.md).
