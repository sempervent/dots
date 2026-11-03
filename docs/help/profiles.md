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
./dots profile
./bootstrap.sh --profile home --show
./bootstrap.sh --profile home --dry-run
```

Custom profiles may live under `~/.config/dots/profiles/`.
