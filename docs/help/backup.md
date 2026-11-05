# Backup & Restore

## DOTS config snapshots

Snapshots: `~/.local/state/dots/backups/`

```bash
./dots backup --name before-change
./dots backups
./dots restore
```

Setup also creates automatic pre-change backups when replacing unmanaged
collisions. Legacy trees may appear as `~/.old_dots`.

## Backup / sync CLIs (package group)

```bash
./setup.sh --packages backup    # restic
./setup.sh --with syncthing     # opt-in; never auto-started
./dots check backup             # local diagnostics only
```

`rclone` stays in the `network` group. Syncthing is **not** a backup by itself.
DOTS never initializes restic repos, runs backup/restore, or contacts remotes
during setup/check. See `docs/using/backup-tooling.md`.
