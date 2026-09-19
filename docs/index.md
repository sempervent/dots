# DOTS

**Desired-state environment manager** for a personal workstation operating layer —
shared muscle memory across home Mac, work Mac, and headless Linux. Not a pile of
identical packages everywhere; not “just dotfiles.”

Humans use [`./dots`](reference/cli.md). Automation uses `bootstrap.sh` /
`setup.sh`. Declarative registries own desired state; helpers execute it.

## Documentation site

Live docs: [https://sempervent.github.io/dots/](https://sempervent.github.io/dots/)

## Entry points

| I want to… | Go here |
|------------|---------|
| Install and run the first time | [Getting Started](getting-started/index.md) |
| Understand profiles / packages / components | [Core Concepts](concepts/architecture.md) |
| Select optional `--with` components | [Components and `--with`](using/components.md) |
| Pick a machine role (home / work / server / Pi) | [Profiles](concepts/profiles.md) |
| Use Linux or Raspberry Pi | [Linux](platforms/linux.md) · [Raspberry Pi](platforms/raspberry-pi.md) |
| macOS workstation apps (Vorssaint, Raycast, …) | [mactools](macos/mactools.md) |
| Agents, models, routing | [Agent harness](agents/harness.md) · [Models](agents/models.md) |
| Fix something that broke | [Troubleshooting](troubleshooting/index.md) |
| Extend the repo safely | [Extending](using/extending.md) |
| CLI flags (generated) | [CLI reference](reference/cli.md) |

## Happy path

```bash
git clone https://github.com/sempervent/dots.git ~/dots
cd ~/dots
./dots                     # interactive setup
./dots setup --dry-run     # preview without mutating
./dots status              # read-only dashboard
./dots check               # health verification
```

## Sources of truth (do not invent a second)

| Thing | Authority |
|-------|-----------|
| Optional components / supergroups | `configs/components.toml` |
| Package groups | `configs/packages/groups.toml` + `brew/groups/*.Brewfile` |
| Linux package names | `configs/packages/{apt,pacman,dnf,xbps}.toml` |
| Managed links | `configs/links.toml` |
| Skill packs | `configs/skills/manifest.toml` |
| Local models | `configs/models.toml` |
| Built-in profiles | `configs/bootstrap/profiles/*.toml` |

See [Architecture](concepts/architecture.md) for the full map.

## What DOTS is not

- A forced identical install on every machine
- An auto-cleanup tool (`brew bundle cleanup` is never run)
- An AI consent grab — presence of a binary does not authorize configuration
- A ZFS / NAS appliance (a future `file-tank` profile is explicitly out of scope today)

## Contribute / maintain

Branch → PR → GitHub CI. See [Contributing](maintainers/contributing.md) and the
[maintainer skill](maintainers/skill.md).
