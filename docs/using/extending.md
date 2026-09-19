# Extending DOTS

Canonical cookbook for adding packages, components, skills, links, and related
artifacts. Read [Architecture](../concepts/architecture.md) for sources of truth.

**local validation passed ≠ GitHub CI passed.** After local lint/tests, open a
PR and wait for Actions.

Every recipe ends with:

```bash
./scripts/ci/lint.sh
./scripts/ci/test.sh
```

plus any focused tests named below. Docs changes also need:

```bash
./scripts/docs/generate.sh
./scripts/docs/check.sh
```

---

## Adding a portable CLI dependency

```text
new CLI tool
  ↓
which package group owns it?
  ↓
configs/packages/groups.toml   (required vs optional)
  ↓
brew/groups/<group>.Brewfile
  ↓
configs/packages/apt.toml
configs/packages/pacman.toml
configs/packages/dnf.toml
configs/packages/xbps.toml
  ↓
tests + docs/using/tools.md if conceptually significant
```

| Kind | Meaning |
|------|---------|
| **required** | Missing after install → ERROR for that profile contract |
| **optional** | Nice-to-have; WARN if missing; may be empty/SKIP on some managers |

Unavailable on a distro: set the map value to `""` (skip). Do not invent fake
package names. Do **not** add ownership only to top-level `brew/Brewfile`.

Focused: `scripts/tests/package_state_test.sh`, `scripts/tests/repository_contract_test.sh`.

---

## Adding an optional component

```text
configs/components.toml
  (+ brewfile = "brew/Brewfile.<id>" when packaged)
brew/Brewfile.<id> if needed
helper / configure logic only if side effects require it
focused tests + scripts/check.sh contract
docs (tools / extending / README index as needed)
```

- **platforms** — `darwin` / `linux`; unsupported explicit `--with` is an error;
  unsupported members of a **supergroup** are reported and omitted.
- **omit_from_all** — skip when profile `all` expands the registry (e.g. `mactools`,
  `archify`).
- **supergroups** — declarative member lists in `components.toml`; expand to ids
  before install (no second install path).
- **brewfile** — optional path relative to repo root; looked up by
  `dots_component_brewfile` (no hard-coded case map).

Specialized side effects (Herdr Linux installer, hermes-desktop, FluidVoice cask
presence, Codex npm→cask migration) stay in `helpers/optional_components.sh`.

Focused: `scripts/tests/component_supergroups_test.sh`,
`scripts/tests/optional_failure_summary_test.sh`.

---

## Adding a managed config / link

```text
repo-owned source (syms/ or configs/…)
  ↓
configs/links.toml
  ↓
backup semantics (never replace unmanaged without backup)
  ↓
scripts/tests/link_manifest_test.sh
```

Never replace an unmanaged target without backup. Prefer additive links.

Dormant `syms/` files that are not in `links.toml` are intentional — see
[Architecture](../concepts/architecture.md). Do not delete them casually.

---

## Adding a skill

See [Skills](skills.md).

Adding a skill to an existing pack normally does **not** require a new component —
edit `configs/skills/manifest.toml` only.

---

## Adding a local model / provider

Edit `configs/models.toml` (and pull policy used by `scripts/pull_models.sh`).
Do not pull models in CI. Keep provider consent explicit via profile / `--with`.
Regenerate docs: `./scripts/docs/generate.sh`.

---

## Adding a distro package mapping

```text
portable tool id (from groups.toml)
  ↓
shared family map: apt / pacman / dnf / xbps
  ↓
distro-specific override only for real incompatibilities
  ↓
docs/platforms/linux.md + CI smoke expectations
```

Empty string = cannot install via that manager.

---

## Adding a new CI distro

Follow [Linux](../platforms/linux.md) and the smoke harness under
`scripts/ci/distro_smoke*.sh` plus `.github/workflows/ci.yml`. Keep smoke
non-mutating where possible.

---

## Adding a new external GUI app

```text
prefer Homebrew cask (often via brew/Brewfile.mactools or a component Brewfile)
external-app adoption: warn → brew install --cask --adopt → leave untouched on failure
never --force
never delete unmanaged app copies
manual permissions / licenses where needed
```

See [Packages](../concepts/packages.md).

---

## Adding a tool to the documentation catalog

Add a row to [Tools](tools.md) with an official upstream link. Do not list every
transitive dependency.

---

## When NOT to add something

| Urge | Prefer instead |
|------|----------------|
| Hard-code a new `case` for Brewfiles | `brewfile =` in `components.toml` |
| Edit `SUPPORTED_WITH` in `setup.sh` | add component id to `components.toml` |
| Put a package only in `brew/Brewfile` | owning `brew/groups/*.Brewfile` or component Brewfile |
| New skill as a component “just in case” | pack membership in `manifest.toml` |
| Live HTTP checks in CI for upstream URLs | document links; contract tests stay offline |
| Delete dormant `syms/` | document status; promote via `links.toml` when ready |

---

## Compact source-of-truth reminder

| Thing | Authority |
|-------|-----------|
| optional components + Brewfile map | `configs/components.toml` |
| package groups | `configs/packages/groups.toml` |
| Homebrew groups | `brew/groups/*.Brewfile` |
| Linux names | `configs/packages/*.toml` |
| links | `configs/links.toml` |
| skill packs | `configs/skills/manifest.toml` |
| models | `configs/models.toml` |
| profiles | `configs/bootstrap/profiles/*.toml` |
| agent router | `configs/agents/router.toml` + `skills/agent-router/SKILL.md` |
