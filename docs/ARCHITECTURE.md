# Architecture

DOTS is a profile-driven workstation layer. Humans use `./dots`; automation uses
`bootstrap.sh` / `setup.sh`. Declarative registries own desired state — helpers
execute it.

## Entrypoints

| Script | Role |
|--------|------|
| `dots` | Unified CLI (wizard, status, packages, models, check, update) |
| `bootstrap.sh` | Profile resolution → Stage 0 → setup → health gate |
| `setup.sh` | Install / refresh mechanism (packages, links, optional components) |
| `configure.sh` | Create/edit profile TOML only (no installs) |
| `scripts/check.sh` | Health verification for a resolved profile |

## Execution graph

```text
profile resolution
  ↓
Stage 0 (CLT / Homebrew / Python as needed)
  ↓
backup (unmanaged targets)
  ↓
package acquisition (groups + selected optional Brewfiles)
  ↓
configuration helpers
  ↓
link / relink (configs/links.toml)
  ↓
optional component configuration (post-link)
  ↓
health verification (scripts/check.sh)
```

`--show` / `--dry-run` never mutate. Consent for AI clients is explicit profile /
`--with` listing — binary presence alone does not authorize configuration.

## Layers of desired state

```text
profiles          machine-role presets (home / work / server / …)
package groups    portable tool sets (core, modern, …)
optional components   --with ids (herdr, hermes, mactools, …)
supergroups       expand to component ids (e.g. ai)
managed links     repo files → home paths
skills            packs / standalone via skills CLI
models            local model registry + pull policy
runtime.env       generated non-secret runtime
local.sh          host overrides (never overwritten)
```

## Source of truth

| Thing | Authority |
|-------|-----------|
| optional components / platforms / `omit_from_all` | `configs/components.toml` |
| component → Brewfile mapping | `configs/components.toml` (`brewfile =`) |
| supergroups | `configs/components.toml` |
| package groups (required/optional ids) | `configs/packages/groups.toml` |
| Homebrew group ownership | `brew/groups/*.Brewfile` |
| optional component Homebrew fragments | `brew/Brewfile.<id>` |
| convenience aggregate Brewfile | `brew/Brewfile` (not canonical ownership) |
| Linux native package names | `configs/packages/{apt,pacman,dnf,xbps}.toml` |
| managed file links | `configs/links.toml` |
| skill packs | `configs/skills/manifest.toml` |
| local model policy | `configs/models.toml` |
| built-in profiles | `configs/bootstrap/profiles/*.toml` |
| supported `--with` ids | loaded from `configs/components.toml` (not edited in `setup.sh`) |

Do **not** invent a second registry. Prefer extending these files over new
hard-coded `case` maps.

## `brew/Brewfile` role

`brew/Brewfile` is a **convenience / backward-compatible aggregate** of workstation
groups for bare `./setup.sh`. Canonical ownership is:

```text
brew/groups/*.Brewfile
brew/Brewfile.<component>
```

Add new packages to the owning group or component Brewfile — not the aggregate.
`scripts/tests/repository_contract_test.sh` checks aggregate ↔ group drift.

There is no `packages.txt`.

## Dormant / unclassified `syms/` entries

`configs/links.toml` lists **active** managed links. Other files under `syms/` may
remain in the tree without being linked:

| Status | Examples |
|--------|----------|
| active | listed in `configs/links.toml` |
| template | `gitconfig.template`, `docker_config.json.template` |
| legacy / deprecated | `init.vim` (Neovim uses `configs/nvim`), `screenrc`, `xonshrc` |
| dormant / optional | `curlrc`, `dircolors`, `exrc`, `gemrc`, `config.fish`, … |

Do not delete dormant files casually. Document before promoting them into
`configs/links.toml`.

## Related docs

- [EXTENDING.md](EXTENDING.md) — how to add packages, components, skills, links
- [SKILLS.md](SKILLS.md) — skill packs vs standalone
- [TOOLS.md](TOOLS.md) — conceptual tool catalog
- [LINUX.md](LINUX.md) — distro matrix
- [MACTOOLS.md](MACTOOLS.md) — macOS workstation layer
