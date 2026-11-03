# Files & Configuration

| Path | Role |
|------|------|
| `~/dots` (or clone) | Repository |
| `~/.config/dots/` | Runtime state, profiles, models overlay |
| `~/.config/dots/runtime.env` | Active runtime exports |
| `~/.config/dots/active-profile` | Last applied profile record |
| `~/.config/starship.toml` | Prompt |
| `~/.local/state/dots/backups/` | Snapshots |
| `~/.local/share/man/` | User man pages (`man dots`) |
| `~/.local/bin/dots-help` | Help launcher |

Environment (non-secret):

| Variable | Role |
|----------|------|
| `DOTS_MULTIPLEXER` | tmux / herdr / none |
| `DOTS_GREETING` | Startup greeting |
| `NO_COLOR` | Disable ANSI color |
