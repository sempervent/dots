# Packages

Installed software must never fail setup merely because DOTS did not install it.

## Ownership model

| Term | Meaning |
|------|---------|
| **managed** | Declared by the *resolved* DOTS package/component set **and** owned by Homebrew |
| **missing** | Declared by DOTS but absent |
| **outdated** | Declared, Homebrew-owned, update available |
| **external** | Declared by DOTS; app exists but Homebrew does not own it |
| **inactive** | Installed; known DOTS owner(s) exist but **none are selected** |
| **undeclared** | Top-level Homebrew install with **no** DOTS group/component owner |

```text
known ≠ selected ≠ installed

installed ≠ managed
managed = declared by resolved DOTS configuration (active groups + selected components)
inactive = known in a Brewfile owner, but that owner is not active
undeclared = no owner in brew/groups/*.Brewfile or component brewfile=
```

Desired state is the **union** of active profile package-group Brewfiles plus
selected optional components — never every Brewfile on disk, and never the
aggregate `brew/Brewfile` as ownership authority.

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
| `dev` | Local CI / lint / Rust ergonomics (install-only) |
| `security` | Secrets scanning / SBOM / signing CLIs (install-only; no auth) |
| `network` | Network / remote / k8s context CLIs (install-only; no Tailscale up) |
| `data` | Tabular / analytical CLIs |
| `geo` | Geospatial CLI tooling |

**required** → ERROR if missing after install for that profile contract.
**optional** → WARN if missing; may be empty/SKIP on some managers.
Unavailable on a distro: map value `""` (skip) — do not invent fake names.

New workstation tool groups are **mostly optional** membership. They do **not**
change global Git (`difftastic` / `mergiraf` are install-only — opt in per-repo).
`mitmproxy` is intentionally **not** in `network` (defer as opt-in later).
DOTS never runs `tailscale up` / login.

Aggregate `brew/Brewfile` still covers only the legacy bare-`setup.sh` set
(`core`…`infra`). New groups are owned solely by `brew/groups/<name>.Brewfile`
and selected via profile `packages =`.

## CLI

```bash
./dots packages groups                  # capability groups (+ active)
./dots packages group geo               # one group in detail
./dots packages plan --profile home     # resolved plan (read-only)
./dots packages status                  # full audit (advisories only)
./dots packages explain dust            # owners + activate hint
./dots packages outdated                # outdated managed packages
./dots packages upgrade                 # upgrade managed outdated only
./dots packages upgrade --all           # opt-in: broader Homebrew upgrades
./dots packages adopt glow --group modern   # suggest Brewfile lines (no auto-edit)
# If a package already has a component owner, adopt points to --with instead.
```

Human guide: [Package groups](../using/package-groups.md).
See also [Components and `--with`](../using/components.md).

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
Tests: `scripts/tests/package_state_test.sh`, `scripts/tests/cask_app_test.sh`,
`scripts/tests/component_discovery_test.sh`.
