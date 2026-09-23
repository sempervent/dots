# Profiles

A **profile** is a machine-role preset: package groups, optional components,
runtime defaults (multiplexer, greeting), and optional `open_apps`.

Authority: `configs/bootstrap/profiles/*.toml`
([generated reference](../reference/generated/profiles.md)).

## Built-in profiles

| Profile | Package groups | Optional components | Multiplexer | GUI |
|---------|----------------|---------------------|-------------|-----|
| `base` | `core`, `modern` | none | tmux | minimal |
| `home` | `core`…`gui` + `infra`/`media` + `dev`/`network`/`data`/`geo`/`security` | `ai` + herdr, skills, ai-skills, images, tex; FluidVoice excluded by default | herdr | yes |
| `work` | `core`, `modern`, `workstation`, `dev`, `data`, `geo`, `security`, `gui` | **none** unless `--with` / custom | tmux | yes (font) |
| `server` | `core`, `modern`, `server` | **Herdr** only (no AI providers) | tmux | no |
| `all` | full workstation groups incl. `dev`/`security`/`network`/`data`/`geo` | all optional (`include_all_optional`; respects `omit_from_all`) | tmux | yes |

### `base`

Universally safe baseline — **no** optional AI providers or skill packs.

### `home`

Personal workstation. Uses the `ai` **supergroup** for AI applications, then adds
non-AI extras (`herdr`, `skills`, `ai-skills`, `images`, `tex`). FluidVoice is in
`without` by default (opt in with `--with fluidvoice`). Platform-incompatible AI
members are omitted automatically.

### `work`

Conservative allowlist. **Do not** infer employer AI policy. Start with no AI
clients. Cursor must not be included without approval. Package groups add
`dev` / `data` / `geo` / `security` (install-only CLIs) plus `gui` (JetBrains Mono
Nerd Font). `network` stays off unless a custom profile or `--packages` opts in.

### `server`

Headless Linux (or conservative remote). Installs Herdr but defaults multiplexer
to tmux. Herdr availability does **not** authorize Hermes/Codex/Cursor/Ollama.

### `all`

Lab convenience: every optional component (may include cloud AI). Components with
`omit_from_all` (e.g. `mactools`, `archify`) are skipped.

## Custom profiles

Copy a template from `examples/profiles/` into `~/.config/dots/profiles/`:

```bash
./bootstrap.sh --profile ~/.config/dots/profiles/<name>.toml --show
./bootstrap.sh --profile ~/.config/dots/profiles/<name>.toml --dry-run
./bootstrap.sh --profile ~/.config/dots/profiles/<name>.toml
```

Builtin short names always resolve to **repository** presets — never shadowed by
user files with the same basename.

### Real examples (templates)

| Example | Extends | Intent |
|---------|---------|--------|
| `home-studio.toml` | `home` | Personal workstation **without** Cursor |
| `work-custom.toml` | `work` | Employer machine + infra/images, still AI-free |
| `bertha.toml` | `server` | Headless Linux + infra; tmux auto-mux |

### Suggested machine recipes

| Machine | Suggested approach |
|---------|-------------------|
| Home Mac | `home` or copy `home-studio` (drop Cursor) |
| Work Mac | `work` or `work-custom` (+ employer-approved `--with` only) |
| Debian / Ubuntu server | `server` or `bertha`-style extend |
| Raspberry Pi | `server` + apt map; see [Raspberry Pi](../platforms/raspberry-pi.md) |
| Manjaro / Arch desktop | `home` or `base` + selective `--with`; pacman map |
| Minimal server | `base` or `server` with fewer extras |
| Home studio (audio/creative) | `home` + `--with mactools` on Darwin |

## Future: ZFS / file-tank

A `file-tank` profile extending `server` (ZFS / SMART / nvme tooling) is
**future work** — not implemented. Do not document it as available.

## CLI

```bash
./dots profile
./configure.sh                 # edit/create profile TOML only
./bootstrap.sh --profile home --show
```

## Related

- [Architecture](architecture.md)
- [Components](components.md)
- [Generated profiles](../reference/generated/profiles.md)
