# Troubleshooting

Symptom-driven. Prefer read-only diagnosis (`--show`, `--dry-run`, `./dots status`,
`./dots check`) before mutating.

## Bootstrap / setup fails immediately

| Symptom | Checks |
|---------|--------|
| Missing Bash / unsupported OS | Confirm Darwin or Linux; `/bin/bash` present |
| Network / TLS errors during Stage 0 | Official Homebrew installer needs network |
| Python / tomllib errors | Need Python ≥3.11; Stage 0 can provision — re-run without `--dry-run` |
| `sudo` prompts fail | OS package installs need elevation |

## `--with` rejected

| Symptom | Likely cause |
|---------|--------------|
| Unknown component id | Must exist in `configs/components.toml` |
| Platform error for `mactools` / `cursor` / `codex` / `fluidvoice` | Darwin-only (FluidVoice also needs macOS 15+) |
| Supergroup member skipped | Unsupported on this platform — reported and omitted |

```bash
./setup.sh --dry-run --with ai
./bootstrap.sh --profile home --show
```

## Dry-run looked fine; apply aborted on backup

Backup of unmanaged collisions failed → apply **aborts** by design.

```bash
./dots backup --name manual
./dots backups
```

See [Backup](../concepts/backup.md).

## Links / shell config wrong after setup

```bash
./dots check
./scripts/check.sh --profile <active>
```

Open a new shell. Confirm target is listed in `configs/links.toml`
([generated links](../reference/generated/links.md)). Dormant `syms/` files are
**not** linked until promoted.

## Package shows EXTERNAL

Declared cask present but Homebrew does not own it. DOTS warned and may have
tried `--adopt`. It will not `--force` or delete the app.

```bash
./dots packages status
```

## Undeclared Homebrew packages

Expected if you installed tools outside DOTS. Never cleaned by `brew bundle
cleanup` (DOTS does not run that).

```bash
./dots packages upgrade          # managed only
./dots packages upgrade --all    # opt-in undeclared too
```

## Health check fails; warnings only

Required failures fail bootstrap. Warnings alone should not.

```bash
./dots check
./dots status
```

## Skills missing after `--with skills`

```bash
ls ~/.agents/skills
# Hermes co-selected:
ls ~/.hermes/skills
./scripts/update-skills.sh
```

Strict advisory: `DOTS_SKILLS_STRICT_REVIEW=1`.

## Models not present

Runtimes install without weights.

```bash
./scripts/pull_models.sh --list
./dots models
```

FluidVoice models: app UI only.

## Model pull floods the terminal with `>>>>`

Fixed in **v1.4.0**. Wizard used to pipe `pull_models.sh` through `tee` for the
setup log, which stole the TTY so CR progress became permanent scrollback.

- Prefer `./dots models` (direct `exec`) or re-run wizard / models-only on v1.4.0+
- Durable logs should show `MODEL START` / `MODEL RESULT`, not progress bars
- If you still see floods on an older checkout, update past v1.4.0

## Agent routed to wrong backend

Read `skills/agent-router/SKILL.md` and `~/.config/dots/agents/router.toml`.
Cursor is never automatic. Coding requires an explicit/trusted cwd.

## Linux package missing on one distro

Check family map (`apt`/`pacman`/`dnf`/`xbps`). Empty string means intentionally
unavailable — do not invent names.

```bash
./dots status
```

## Raspberry Pi / ARM oddities

Use 64-bit OS when possible. CI ARM64 smoke is Debian-on-ARM proxy — see
[Raspberry Pi](../platforms/raspberry-pi.md).

## Docs site / generator

```bash
./scripts/docs/generate.sh
./scripts/docs/check.sh
```

`--check` fails on drift. Do not hand-edit `docs/reference/generated/*`.

## Still stuck

1. `./bootstrap.sh --profile <name> --show`
2. `./dots status` + `./dots check`
3. Focused test under `scripts/tests/` matching the subsystem
4. Open an issue / PR with the **exact** command and non-secret output
