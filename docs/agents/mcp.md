# MCP

Curated servers live in `configs/agents/mcp-trust.toml`. The protocol target is MCP `2026-07-28`. New declarations use `stdio` or `streamable_http`. Legacy HTTP+SSE is not the model.

```bash
./dots mcp list
./dots mcp show ID
./dots mcp status
./dots mcp doctor
./dots mcp search QUERY
./dots mcp inspect ID
./dots mcp enable ID --dry-run
./dots mcp disable ID --dry-run
./dots mcp plan --dry-run
./dots mcp sync --dry-run
./dots mcp audit
```

`./dots agent mcp inspect` still inspects the safe allowlist.

## Permissions

Policy uses dimensions, not a single trusted flag:

```text
filesystem_read
filesystem_write
shell
network
remote_write
billable
credentials
```

`dots mcp show` prints each one. A trust label such as `read_only_network` is only a summary.

Auth modes are `none`, `env`, `oauth`, and `client_credentials`. Status prints `SET` or `UNSET` for required environment names. Values are never printed and tokens are not stored. v1.14 does not run an OAuth login.

## Discovery

`dots mcp search` queries the official registry, or `DOTS_MCP_REGISTRY_FIXTURE` in tests. Search does not install, enable, or trust a server. A discovered server becomes curated only when a maintainer adds it to the registry.

## Projection

`dots mcp sync` merges DOTS-owned entries into client config:

| Client | Skills | MCP | Merge |
| --- | --- | --- | --- |
| Pi | native `~/.agents/skills` | `~/.pi/agent/mcp.json` `mcpServers` | JSON object merge |
| Cursor | native `~/.agents/skills` | `~/.cursor/mcp.json` `mcpServers` | JSON object merge |
| OpenCode | native | `~/.config/opencode/opencode.json` `mcp.servers` | JSON object merge |
| Codex | native `~/.agents/skills` | `~/.codex/config.toml` | marked DOTS region |
| Hermes | `~/.hermes/skills` stays | `~/.hermes/config.yaml` | marked region, or manual if `mcp_servers` already exists |

User keys are preserved. DOTS records the ids it wrote and removes only those on disable. Files are backed up before a change. Invalid JSON aborts before mutation. A client that cannot accept a server is reported as unsupported.

## Safe runs

A safe run uses a run-local allowlist:

```text
desired ∩ curated ∩ allowed client ∩ allowed mode ∩ trust policy
```

Shell, filesystem write, and remote write do not enter safe mode because a profile desires them. The user's interactive MCP config is not copied into the safe run.

Doctor checks the declaration, transport, command or URL, and auth state. It does not call mutating tools. MCP server processes remain a separate trust boundary; this release does not add a container runtime for them.
