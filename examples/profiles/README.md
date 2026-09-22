# Example custom profiles

These files are **templates**, not active configuration.

1. Copy one into `~/.config/dots/profiles/`
2. Edit the name / `extends` / packages / components
3. Preview, then apply:

```bash
./bootstrap.sh --profile ~/.config/dots/profiles/<name>.toml --show
./bootstrap.sh --profile ~/.config/dots/profiles/<name>.toml --dry-run
./bootstrap.sh --profile ~/.config/dots/profiles/<name>.toml
```

| Example | Extends | Intent |
|---------|---------|--------|
| `home-studio.toml` | `home` | Personal workstation without Cursor |
| `work-custom.toml` | `work` | Employer machine + infra/images, still AI-free |
| `bertha.toml` | `server` | Headless Linux + infra; tmux auto-mux |
| `developer.toml` | `base` | `dev` + `security` CLIs, no AI |
| `data-geo.toml` | `base` | `data` + `geo` on a desktop baseline |
| `work-network.toml` | `work` | Work allowlist + `network` (still no AI) |

Builtin short names (`home`, `work`, `server`, …) always resolve to repository
presets — they are never shadowed by files in `~/.config/dots/profiles/`.
