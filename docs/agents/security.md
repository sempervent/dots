# Agent security (v1.6 Phase 2)

DOTS agent runs are **sandboxed and restricted** by default — not “secure against
arbitrary malicious code.” Prefer those words over absolute claims.

## Trust boundary

```text
dots agent run (safe)
  → isolated Git worktree (when in a repo)
  → Pi + pi-sandbox (OS bash sandbox + tool policy)
  → trusted MCP allowlist only
```

`pi-sandbox` is part of the **trusted computing base**. Installing a Pi package
executes code with your privileges; the extension cannot sandbox itself.
Provenance: `configs/agents/pi-sandbox-provenance.toml`.

## Execution modes

| Mode | Flag | Behavior |
|------|------|----------|
| **safe** (default) | `--safe` | Sandbox + worktree when Git; fail closed |
| **in-place** | `--in-place` | Sandbox; write to current checkout |
| **unsafe-host** | `--unsafe-host` | Explicit unrestricted host execution |

If the sandbox cannot initialize in safe/in-place mode, the run **fails**.
There is **never** an automatic fallback to unrestricted execution.

## What the sandbox covers

| Domain | Mechanism |
|--------|-----------|
| Pi `read` / `write` / `edit` | pi-sandbox allow/deny lists |
| Pi `bash` | macOS `sandbox-exec` / Linux `bubblewrap` |
| Bash external network | Default allowlist: `localhost`, `127.0.0.1` only |
| Secrets / `$HOME` | denyRead/denyWrite for sensitive paths + globs |

### Linux glob limitation

On Linux, filesystem **globs** in `allowWrite`/`denyWrite` are **not** enforced
for bash (bubblewrap binds concrete paths). DOTS therefore denies concrete
secret directories and still applies globs to Pi’s direct tools.

## What it does **not** cover

- Pi extension / package code itself
- MCP server processes (outside bash sandbox)
- Kernel/OS sandbox escapes
- Remote model receiving explicitly supplied context
- Intentional `--unsafe-host` bypass

## Separate network domains

Do not conflate these:

| Domain | Default |
|--------|---------|
| Sandboxed bash | External denied (localhost only) |
| Pi model calls | Local provider / configured endpoint |
| model-scout MCP | OpenRouter **metadata** (catalog) |
| dots-expert MCP | LiteLLM → OpenRouter (billable) |

## MCP trust

Safe harness runs expose only:

```text
dots-model-scout   # read_only_network; no filesystem; no shell
dots-expert        # billable_remote; no filesystem; no shell
```

Interactive `pi` keeps the user’s full MCP configuration. Metadata:
`configs/agents/mcp-trust.toml`.

## Credentials

| Process | OpenRouter key | LiteLLM master key |
|---------|----------------|--------------------|
| Pi / bash | **No** | **No** |
| model-scout | Yes (catalog) | No |
| dots-expert | No | Yes |
| LiteLLM Compose | Yes | Yes |

Pi does **not** receive a full parent `os.environ.copy()`.

## Worktrees

Safe coding runs use `git worktree` under
`~/.local/state/dots/agents/worktrees/<run-id>/`.
The primary checkout is not written. Apply/discard are explicit:

```bash
dots agent worktrees
dots agent diff RUN_ID
dots agent apply RUN_ID
dots agent discard RUN_ID
```

## Threat model (acknowledged)

| Threat | Phase 2 mitigation |
|--------|--------------------|
| Malicious repo prompt injection | Compact context; sandbox FS/network |
| Credential exfiltration via bash | Env scrub + deny paths + network deny |
| Credential exfiltration via MCP | Allowlist + capability-specific env |
| Arbitrary host file mutation | Worktree + denyWrite outside cwd |
| Network exfiltration (shell) | Domain allowlist / prompt timeout deny |
| Sandbox escape | Out of scope (OS/kernel) |
| MCP server compromise | Trust metadata; minimal servers |
| Unsafe extension compromise | Provenance review; TCB disclosure |
| Primary checkout corruption | Worktree isolation; explicit apply |
| Policy self-modification | Live policy outside agent-writable paths |

## MCP Inspector

Developer/diagnostic only (not a run dependency):

```bash
dots agent mcp inspect dots-model-scout
dots agent mcp inspect dots-expert
```
