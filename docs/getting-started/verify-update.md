# Verify and update

## Health check

```bash
./dots check
./scripts/check.sh --profile home
./scripts/check.sh --profile ~/.config/dots/profiles/my.toml
```

Required check failures make bootstrap **fail**. Warnings do not.

`./dots status` runs a concise read-only dashboard (including a quick package
drift summary when Homebrew is available).

## Package audit and upgrades

`dots update` updates the **DOTS repository** (`git pull`). `dots upgrade`
upgrades **installed Homebrew software** in the active DOTS desired scope
(`update != upgrade`).

| Command | Role |
|---------|------|
| `dots tui` | Dynamic desired-state TUI |
| `dots update` | Update DOTS itself |
| `dots upgrade` | Upgrade managed software |
| `dots install X` | Add known software/capability to persistent desired state |
| `dots profile` | Inspect/edit desired state |
| `dots setup` | Bootstrap/reconfigure/converge |

```bash
./dots packages status     # full audit (advisories)
./dots packages outdated   # outdated DOTS-managed packages
./dots upgrade --dry-run   # preview managed, excluded, and undeclared updates
./dots upgrade             # upgrade resolved desired set only
./dots upgrade --all --yes # opt-in: also upgrade undeclared Homebrew packages
```

DOTS never runs `brew bundle cleanup`, `brew cleanup`, or OS package-manager
upgrades (`apt full-upgrade`, `dnf upgrade`, `pacman -Syu`, `xbps-install -Su`).
See [Packages](../concepts/packages.md).

## Backup before risky changes

```bash
./dots backup --name before-upgrade
./dots backups
```

See [Backup and recovery](../concepts/backup.md).

## Update the repo

```bash
./dots update
```

This pulls the DOTS repository and can optionally reapply the active profile.
Expert equivalent: `scripts/update.sh` / `git pull` then re-bootstrap as needed.

## Skills updates (opt-in)

```bash
./scripts/update-skills.sh
```

Not run on every setup. Set `DOTS_SKILLS_STRICT_REVIEW=1` to fail on advisory
security findings (does not delete skills).

## Models

```bash
./dots models
./scripts/pull_models.sh --list
```

Model pulls are **never** part of CI. Registry: `configs/models.toml`
([generated](../reference/generated/models.md)).

## Local documentation site

```bash
./scripts/docs/serve.sh
./scripts/docs/check.sh
```

Maintainer docs workflow: [Documentation](../maintainers/documentation.md).
