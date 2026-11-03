# Backup & Restore

Snapshots: `~/.local/state/dots/backups/`

```bash
./dots backup --name before-change
./dots backups
./dots restore
```

Setup also creates automatic pre-change backups when replacing unmanaged
collisions. Legacy trees may appear as `~/.old_dots`.
