# Agent Security

Default `dots agent run` is **safe**: sandboxed Pi tools, restricted bash
network, secret-path denies, and (in Git repos) an isolated worktree.

## Quick commands

```bash
dots agent doctor
dots agent sandbox status
dots agent worktrees
dots agent mcp status
```

## Modes

```bash
dots agent run "TASK"                 # safe (default)
dots agent run --in-place "TASK"      # sandbox; current checkout
dots agent run --unsafe-host "TASK"   # explicit unrestricted host
```

Safe/in-place **fail closed** if the sandbox cannot start. There is no silent
unsafe fallback.

## Worktrees

```bash
dots agent diff RUN_ID
dots agent apply RUN_ID      # requires clean primary checkout
dots agent discard RUN_ID    # never automatic
```

## See also

- [docs/agents/security.md](../agents/security.md)
- [docs/help/agent.md](agent.md)
