# Agent capabilities

DOTS answers one question from the registries it already has: what this profile wants, where it came from, what it can touch, which clients can use it, whether the runtime fits, and whether it is safe for the current mode.

There is no second inventory. The view is computed:

| Question | Authority |
| --- | --- |
| Which skills exist | `configs/skills/manifest.toml` |
| Which MCP servers are curated | `configs/agents/mcp-trust.toml` |
| Which clients and packs can be selected | `configs/components.toml` |
| Which Node each capability needs | `configs/runtime-requirements.toml` |
| What this machine wants | the active profile |

```bash
./dots agent capabilities
./dots agent capabilities --json
```

JSON is `schema_version` 1 with `skills`, `mcp`, `clients`, `models`, `runtime`, and `summary`. The TUI reads that API.

## States

These words are not interchangeable:

| State | Meaning |
| --- | --- |
| DISCOVERED | Returned by MCP registry search. Not trusted. |
| CURATED | Present in `configs/agents/mcp-trust.toml` after review. |
| DESIRED | Selected by the profile or by a skill pack. |
| CONFIGURED | Projected into a client by `dots mcp sync`. |
| HEALTHY | Declaration, transport, and required auth state check out. |
| REVIEWED | Skill source has a pinned reviewed ref. |
| UNREVIEWED | Known skill without a pinned ref. |
| DRIFTED | Installed bytes no longer match the recorded hash. |
| UPDATE_AVAILABLE | A candidate exists and has not been applied. |
| INVALID | Agent Skills structure failed validation. |

Installed does not mean trusted. Listed in the public registry does not mean curated. Configured does not mean healthy.

## Runtime

`./dots check runtimes` resolves one Node for the selected capabilities. An existing Node that already satisfies the set is kept. Conflicting constraints fail before install. Node is managed with fnm only.

## Profiles

```toml
[skills]
include = ["hf-cli"]
exclude = []

[mcp]
include = ["dots-model-scout"]
exclude = []
```

```bash
./dots profile plan --profile home --add-skill hf-cli --add-mcp dots-model-scout --json
./dots profile mutate --profile home --add-skill hf-cli --add-mcp dots-model-scout --dry-run --yes
```

Unknown skill or MCP ids are errors. A profile cannot select an arbitrary URL.

## Diagram

```text
profiles
   │
   ├── software desired state
   ├── skill desired state
   └── MCP desired state
          │
          ▼
capability resolver
   │
   ├── trust
   ├── runtime requirements
   ├── client support
   └── sandbox policy
          │
          ▼
client projection
   ├── Pi
   ├── Hermes
   ├── Codex
   ├── OpenCode
   └── Cursor
```

Source: `docs/diagrams/src/dots-capability-plane.architecture.json`.
