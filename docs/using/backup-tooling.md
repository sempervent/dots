# Backup and synchronization tooling

Package group **`backup`** means backup/recovery/sync **CLIs are available**.
It does **not** mean a backup policy is configured, a repository exists, or sync
is running.

> **Not the same as** `./dots backup` — that command snapshots DOTS-managed
> config collisions (`docs/concepts/backup.md`). This page covers **restic**,
> **rclone**, and **Syncthing**.

## Install

```bash
./setup.sh --packages backup          # restic
./setup.sh --with syncthing           # opt-in; omit_from_all
# rclone remains owned by the network group
```

Profile guidance (Phase 0):

| Profile | Backup group |
|---------|----------------|
| `home` | recommended (included) |
| `all` | includes `backup` (restic); Syncthing still omitted |
| `server` | selective (see `examples/profiles/server-backup.toml`) |
| `work` | not assumed |

## Tool roles

| Tool | Owner | Role |
|------|-------|------|
| **restic** | `backup` | Encrypted snapshot **backup** (primary backup capability) |
| **rclone** | `network` (xref here) | Remote / object-storage **transport** |
| **Syncthing** | `--with syncthing` | Peer-to-peer **synchronization** |

**Syncthing is not a backup by itself.** Bidirectional sync does not replace
versioned, encrypted snapshots. rclone may support restic backends but is not
itself a backup policy.

## Non-destructive defaults

DOTS setup / `./dots check backup` never:

- runs `restic init` / `backup` / `restore` / `forget` / `prune`
- reads `RESTIC_PASSWORD` or cloud credentials
- contacts rclone remotes (except optional local `listremotes` for a count)
- starts Syncthing, enables launchd/systemd, opens the web UI
- pairs devices or creates shared folders
- creates cron / launchd / systemd backup schedules

## Diagnostics

```bash
./dots check backup              # local metadata only
./dots check backup examples     # recovery-oriented examples (not executed)
```

Typical status:

```text
restic
  binary              OK
  repository          NOT CONFIGURED   # informational, not FAIL

rclone
  binary              OK
  config              FOUND / NOT FOUND
  remotes             N

Syncthing
  binary              OPTIONAL / INSTALLED
  running             YES / NO         # informational
```

## Recovery remains user-directed

DOTS does not choose snapshots, destinations, or overwrite sets. Use tool
docs / `./dots check backup examples` and run restores explicitly.

## Scheduling

Phase 5 does **not** create launchd jobs, cron entries, or systemd timers.
Scheduling may become an explicit future component.
