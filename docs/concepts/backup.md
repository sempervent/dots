# Backup and recovery

Before DOTS replaces unmanaged targets, it creates one coherent snapshot.

## Execution invariant

```text
detect collision → BACKUP (or abort) → then link / replace
```

Backup failure **aborts** the mutating path. Dry-run / show never write snapshots
as part of a fake apply.

Snapshot root:

```text
~/.local/state/dots/backups/<stamp>-<name>/
  manifest.toml
  files/          # paths mirrored relative to HOME (symlinks preserved)
```

## Collision candidates

Paths considered for automatic pre-change snapshots include managed link targets
from `configs/links.toml` plus key config destinations such as:

- `~/.config/nvim`
- `~/.config/herdr/config.toml`
- `~/.config/starship.toml`

Full inventory (manual backup) also includes DOTS state files such as
`runtime.env`, `active-profile`, models override, and skills lock — see
`helpers/backup.sh` (`dots_backup_inventory`).

## Collision types (conceptual)

| Situation | Behavior |
|-----------|----------|
| Target missing | Link/create as designed |
| Target already managed by DOTS (same link) | Idempotent refresh |
| Unmanaged file/dir at managed path | Snapshot first, then replace |
| Backup I/O failure | Abort apply |

Exact classification helpers live in `helpers/backup.sh` and
`scripts/tests/backup_gate_test.sh`.

## CLI

```bash
./dots backup --name before-mactools
./dots backups
./dots restore
./dots restore <snapshot-id>
./dots restore <snapshot-id> --dry-run
./dots backup import-legacy    # import existing ~/.old_dots content
```

Restore creates a **safety snapshot** first before overwriting current files.

## Recipes

### Before a risky optional component

```bash
./dots backup --name before-mactools
./setup.sh --with mactools
```

### Inspect then restore

```bash
./dots backups
./dots restore <id> --dry-run
./dots restore <id>
```

### Legacy `~/.old_dots`

```bash
./dots backup import-legacy
```

## Dangers

- Restoring an old snapshot can wipe newer intentional edits — always dry-run.
- Snapshots are **local** under your home directory; they are not cloud backups.
- Do not commit snapshot contents or secrets into the DOTS repo.
- Commercial app data (Raycast account sync, etc.) is **not** fully covered by
  DOTS link backups — see [mactools](../macos/mactools.md).

## Related

- [Packages](packages.md) (external casks are separate from file snapshots)
- Implementation: `helpers/backup.sh`
