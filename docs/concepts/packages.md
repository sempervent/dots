# Packages

Installed software must never fail setup merely because DOTS did not install it.

## Ownership model

| Term | Meaning |
|------|---------|
| **managed** | Declared by the *resolved* DOTS package/component set **and** owned by Homebrew |
| **missing** | Declared by DOTS but absent |
| **outdated** | Declared, Homebrew-owned, update available |
| **external** | Declared by DOTS; app exists but Homebrew does not own it |
| **undeclared** | Top-level Homebrew install not in the resolved desired set |

```text
installed ≠ managed
managed = declared by resolved DOTS configuration
```

Desired state is the **union** of active profile package-group Brewfiles plus
selected optional components — never every Brewfile on disk.

## Where ownership lives

```text
brew/groups/*.Brewfile          # profile package groups (canonical)
brew/Brewfile.<component>       # optional --with components (canonical)
brew/Brewfile                   # convenience / backward-compatible aggregate only
configs/packages/groups.toml    # required vs optional logical ids
configs/packages/{apt,pacman,dnf,xbps}.toml   # Linux native names
```

There is no `packages.txt`. Do not treat top-level `brew/Brewfile` as the sole
authority.

## Logical groups

From `configs/packages/groups.toml` ([generated](../reference/generated/package-groups.md)):

| Group | Role |
|-------|------|
| `core` | Portable essentials |
| `modern` | Shared ergonomic CLI |
| `workstation` | Desktop-user tools (not headless) |
| `infra` | Containers / k8s / terraform |
| `media` | Image / video processing |
| `gui` | macOS GUI / fonts |
| `server` | Headless extras |

**required** → ERROR if missing after install for that profile contract.
**optional** → WARN if missing; may be empty/SKIP on some managers.
Unavailable on a distro: map value `""` (skip) — do not invent fake names.

## CLI

```bash
./dots packages status              # full audit (advisories only)
./dots packages outdated            # outdated managed packages
./dots packages upgrade             # upgrade managed outdated only
./dots packages upgrade --all       # opt-in: also upgrade undeclared Homebrew pkgs
./dots packages adopt glow --group modern   # prints suggested Brewfile lines (no auto-edit)
```

## External casks

When a declared cask app exists but Homebrew does not own it:

1. Warn
2. Attempt `brew install --cask --adopt`
3. Leave untouched on failure

Never `--force`. Never delete unmanaged app copies.

## Hard invariant

DOTS **never** runs `brew bundle cleanup` or uninstalls undeclared software.

## Implementation

Logic: `helpers/package_state.sh`, `helpers/packages.sh`, `helpers/cask_apps.sh`.
Tests: `scripts/tests/package_state_test.sh`, `scripts/tests/cask_app_test.sh`.
