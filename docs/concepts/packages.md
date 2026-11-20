# Packages

Installed software must never fail setup merely because DOTS did not install it.

## Ownership model

| Term | Meaning |
|------|---------|
| **managed** | Declared by the *resolved* DOTS package/component set **and** owned by Homebrew |
| **missing** | Declared by DOTS and installable here, but absent |
| **outdated** | Declared, Homebrew-owned, update available |
| **external** | Present on the machine, not owned by DOTS's selected install mechanism |
| **inactive** | Installed; known DOTS owner(s) exist but **none are selected** |
| **undeclared** | Top-level Homebrew install with **no** DOTS group/component owner |
| **installable** | DOTS has an authoritative installation mechanism on this platform |
| **unsupported** | Known capability with no DOTS-supported install route on this platform |

```text
known ≠ installable ≠ installed ≠ selected

installed ≠ managed
managed = declared by resolved DOTS configuration (active groups + selected components)
inactive = known in a DOTS registry/Brewfile owner, but that owner is not active
undeclared = no owner in configs/packages/groups.toml, brew/groups/*.Brewfile, or component registries
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

The complete, authoritative list of groups, required/optional memberships, and
platform support lives in `configs/packages/groups.toml` and the
[generated package-groups reference](../reference/generated/package-groups.md).

**required** → ERROR if missing after install for that profile contract (and
if a group's required package has no installation route on the current platform,
DOTS reports the group unsupported rather than claiming convergence).
**optional** → WARN if missing; may be empty/SKIP on some managers without
invalidating the owning group.
Unavailable on a distro: map value `""` (skip) — do not invent fake names.

New workstation tool groups are **mostly optional** membership. They do **not**
change global Git (`difftastic` / `mergiraf` are install-only — opt in per-repo).
`mitmproxy` is intentionally **not** in `network` — use the explicit opt-in
`mitmproxy` component (`--with mitmproxy`, `omit_from_all = true`).
DOTS never runs `tailscale up` / login.

Aggregate `brew/Brewfile` still covers only the legacy bare-`setup.sh` set
(`core`…`infra`). New groups are owned solely by `brew/groups/<name>.Brewfile`
and selected via profile `packages =`.

## CLI

```bash
./dots install hyperfine                # resolve owner, persist sparse overlay, apply
./dots install karabiner-elements --dry-run
./dots upgrade                          # upgrade managed outdated Homebrew software
./dots upgrade --profile work --dry-run
./dots upgrade --all --yes              # opt-in: broader Homebrew upgrades
./dots packages groups                  # capability groups (+ active)
./dots packages group geo               # one group in detail
./dots packages plan --profile home     # resolved plan (read-only)
./dots packages status                  # full ownership report (advisories only)
./dots packages audit [--json]          # offline registry / Brewfile / map audit
./dots packages explain dust            # owners + desired state + install hint
./dots packages outdated                # outdated managed packages
./dots packages upgrade                 # delegates to dots upgrade
./dots packages adopt glow --group modern   # suggest Brewfile lines (no auto-edit)
# If a package already has a component owner, adopt points to --with / install instead.
```

`dots install` activates **known** DOTS capabilities persistently (never arbitrary
`brew install`). `dots packages adopt` teaches DOTS new ownership declarations.
Removing desired state never uninstalls already-installed packages.

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
