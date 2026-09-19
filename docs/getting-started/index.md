# Getting Started

DOTS turns a supported Mac or Linux host into a **profile-driven** environment:
package groups, optional components, managed links, skills, and (when you opt in)
local models.

## Prerequisites

| Need | Notes |
|------|-------|
| Supported OS | macOS (Darwin) or Linux (see [Linux](../platforms/linux.md)) |
| `/bin/bash` | Bootstrap scripts are Bash |
| Network | Official installers (Homebrew / Stage 0) when needed |
| Elevation | `sudo` when the OS package manager requires it |

**Irreducible seed:** supported OS + Bash + network for official installers + OS
elevation when system packages require it. Everything else is acquired by DOTS.

## Install

```bash
git clone https://github.com/sempervent/dots.git ~/dots
cd ~/dots
./dots
```

`./dots` (same as `./dots setup`) runs the interactive wizard: machine role →
profile → components → runtime → models → review → bootstrap → verify.

Expert / automation path:

```bash
./bootstrap.sh --profile home
./bootstrap.sh --profile work
./bootstrap.sh --profile server
```

## First run checklist

1. Choose a **profile** (`home` / `work` / `server` / `base` / custom).
2. Preview: `./bootstrap.sh --profile <name> --show` and `--dry-run`.
3. Apply: `./dots` or `./bootstrap.sh --profile <name>`.
4. Verify: `./dots check` or `./scripts/check.sh --profile <name>`.
5. Optional backup awareness: `./dots backups`.

## Dry-run and show

```bash
./dots setup --dry-run
./bootstrap.sh --profile home --show
./bootstrap.sh --profile home --dry-run
./setup.sh --dry-run --with ai
```

`--show` / `--dry-run` **never mutate**. Use them before first apply on a
machine that already has carefully tuned configs.

## Profiles at a glance

| Profile | Intent |
|---------|--------|
| `base` | Core shell UX only — no optional AI / skills |
| `home` | Personal workstation (AI via `ai` supergroup + extras) |
| `work` | Conservative — **no** AI clients by default |
| `server` | Headless — Herdr available, no GUI/AI providers by default |
| `all` | Lab convenience — all optional components |

Details and real examples: [Profiles](../concepts/profiles.md).

## Next

- [Install and first run (detail)](install.md)
- [Verify and update](verify-update.md)
- [Packages ownership model](../concepts/packages.md)
- [Backup and recovery](../concepts/backup.md)
