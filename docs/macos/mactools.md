# macOS tools (`--with mactools`)

Optional Darwin workstation layer. Not included in profile `all` (`omit_from_all`).

## Install

```bash
./setup.sh --with mactools
./setup.sh --with herdr,hermes,mactools
./setup.sh --dry-run --with mactools
```

Linux / non-Darwin: explicit `--with mactools` errors (same platform gate as
`fluidvoice` / `cursor`).

## Why Vorssaint

Vorssaint is the macOS **control plane**: clipboard history, snippets, window helpers,
file shelf, capture, light system monitoring, and related utilities in one app.

DOTS therefore does **not** install CleanShot X, Dropover, SoundSource,
BetterTouchTool, or PopClip by default.

## What is included

Declared in `brew/Brewfile.mactools` (verified Homebrew names; no duplicates of
`just` / `lazygit` from the modern group):

| Area | Packages |
|------|----------|
| Control plane | `vorssaint` |
| Launcher / automation | `raycast`, `keyboard-maestro`, `hazel` |
| Network | `little-snitch` |
| Containers | `orbstack` (additive; does not remove Docker Desktop) |
| Knowledge | `hookmark`, `devonthink` |
| Terminal / editor | `ghostty`, `zed` (iTerm + Neovim stay primary) |
| Audio / PFL | `loopback`, `audio-hijack`, `blackhole-2ch`, `vcv-rack`, `obs`, `touchdesigner`, `processing`, `sonic-pi`, `supercollider` |
| CLI | `mise`, `yazi`, `watchexec`, `hyperfine`, `mprocs`, `xh`, `dust`, `duf` |

Omitted on purpose (already owned elsewhere): `just`, `lazygit`, Docker CLI formulae, Ranger.

## Setup ordering (safety)

```text
Stage 0 / preflight
  ↓
BACKUP unmanaged collisions  (abort on failure)
  ↓
Core / profile package groups
  ↓
Optional component packages (incl. mactools Brewfile)
  ↓
Configure + symlink / relink managed configs
  ↓
Optional component configuration (portable mactools configs)
  ↓
Post-install notes (no force-kill / no reboot)
```

External GUI apps declared by mactools are **EXTERNAL** until Homebrew owns
them: DOTS warns, attempts `brew install --cask --adopt`, never `--force`s or
deletes the app. See [Packages](../concepts/packages.md).

Snapshots: [Backup](../concepts/backup.md).

```bash
./dots backups
./dots restore <snapshot-id>
```

## Portable configuration (in repo)

| Tool | Managed? | Location | Notes |
|------|----------|----------|-------|
| Ghostty | yes (text) | `configs/ghostty/config` → `~/.config/ghostty/config` | Catppuccin Mocha; does not change default terminal |
| Yazi | yes (text) | `configs/yazi/yazi.toml` | Additive; Ranger kept |
| mise | yes (minimal) | `configs/mise/config.toml` | **Not** activated in shell by default |
| lazygit | yes (minimal) | `configs/lazygit/config.yml` | Package may already come from modern group |
| Vorssaint | manual→ingest | `configs/mactools/vorssaint/` | In-app Export/Import plist |
| Keyboard Maestro | manual | `configs/mactools/keyboard-maestro/` | File → Export Macros |
| Hazel | manual | `configs/mactools/hazel/` | Action → Export All |
| Raycast | unsupported | — | Account sync; do not scrape Application Support |
| Loopback / Audio Hijack / OBS | no | — | Preserve existing profiles |

### GUI export / import helpers

```bash
./scripts/mactools/export-configs.sh all
./scripts/mactools/export-configs.sh vorssaint ~/Desktop/Vorssaint\ Settings.plist
./scripts/mactools/import-configs.sh vorssaint
```

These helpers **ingest** vendor-supported exports. They never scrape `~/Library`.

## OrbStack / Docker Desktop

Migration is manual and reversible: [OrbStack migration](../migration/orbstack.md).
Read-only audit: `./scripts/mactools/docker-orbstack-audit.sh`

## Commercial licenses

Install is allowed; activation is manual. DOTS never stores license keys.

Likely paid / licensed: Keyboard Maestro, Hazel, Little Snitch, Hookmark,
DEVONthink, Loopback, Audio Hijack, TouchDesigner (edition-dependent).

## macOS permissions

Grant in **System Settings → Privacy & Security** as prompted:

| Permission | Typical apps |
|------------|----------------|
| Accessibility | Vorssaint, Raycast, Keyboard Maestro |
| Input Monitoring | Vorssaint, Keyboard Maestro |
| Screen Recording | Vorssaint, OBS, Loopback, Audio Hijack |
| Microphone / System Audio | OBS, Loopback, Audio Hijack, Vorssaint (if used) |
| Full Disk Access | Hazel, DEVONthink, Hookmark (feature-dependent) |
| Network / System Extension | Little Snitch |
| Virtualization | OrbStack |

## Restarts / reboot

DOTS does **not** reboot or force-quit creative apps.

- **Manual restart required** after first install/config: Raycast, Keyboard Maestro, Hazel, Little Snitch, Loopback, Audio Hijack, OBS, DEVONthink (as needed).
- **Reboot may be required** for BlackHole 2ch audio driver — report only; never automatic.
- Do not migrate Docker Desktop → OrbStack as part of setup.

## mise / runtimes

`mise` is installed for future use. Existing **fnm** remains authoritative until a
separate, intentional migration. Analysis only: [mise migration](../migration/mise.md).

Optional (manual) shell hook — only if you choose to adopt mise:

```bash
eval "$(mise activate zsh)"   # or bash
```

## Ghostty + Herdr

iTerm remains supported. To try Herdr inside Ghostty:

```bash
ghostty -e herdr
```
