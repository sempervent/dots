# Profiles

Builtin roles:

| Profile | Intent |
|---------|--------|
| `base` | Minimal core UX |
| `home` | Personal workstation |
| `work` | Work laptop (often AI-light) |
| `server` | Headless / remote |
| `all` | Broad optional set (see omit_from_all) |

```bash
./dots tui                             # interactive desired-state TUI
./dots profile                         # interactive profile menu
./dots profile list [--json]           # list builtin, custom, and overlay profiles
./dots profile show [NAME] [--json]    # resolved profile (read-only)
./dots profile add SELECTOR            # persist capability into sparse overlay
./dots profile remove SELECTOR         # remove from desired state (no uninstall)
./dots profile diff [NAME]             # local additions and removals
./dots profile apply [NAME]            # converge machine toward profile
./dots profile switch NAME [--apply]   # switch active profile
./bootstrap.sh --profile home --show
./bootstrap.sh --profile home --dry-run
```

Custom profiles and DOTS-managed overlays (`<name>-local.toml`) live under
`~/.config/dots/profiles/`. Built-in presets in `configs/bootstrap/profiles/`
are never modified by lifecycle commands.
