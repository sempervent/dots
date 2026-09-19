---
name: dots-maintainer
description: >-
  Canonical operating manual for humans and agents maintaining sempervent/dots.
  Covers git/PR/CI, sources of truth, profiles/packages/components/skills/models,
  docs (MkDocs), safety invariants, and validation. Use for any nontrivial DOTS
  change. Keep skills/agent-router/SKILL.md distinct (routing policy only).
license: MIT
metadata:
  version: "1.0.0"
  author: dots
---

# DOTS maintainer skill

You are working in **sempervent/dots** — a desired-state environment manager
(profile-driven workstation layer), not a casual dotfiles dump.

## Non-negotiables

1. **No direct commits to `master`.** Branch → local validation → push branch →
   PR → wait for GitHub Actions → merge when green.
2. **local validation ≠ GitHub CI.** Say which one you mean.
3. **No second source of truth.** Extend TOML registries; do not invent parallel
   hard-coded maps.
4. **Do not invent** commands, flags, component ids, package names, or model ids.
   If unsure, read the registry / `--help` / tests.
5. **Never** commit secrets, license keys, or machine-local state
   (`runtime.env`, `local.sh`, telemetry DB, snapshots).
6. **Never** document or implement `brew bundle cleanup` as something DOTS runs.
7. Label **future work** explicitly (e.g. ZFS `file-tank`, full Pi OS CI).

## Git workflow

```text
git fetch origin
git switch master && git pull --ff-only origin master
git switch -c <type>/<description>
# implement
./scripts/ci/lint.sh
./scripts/ci/test.sh
# docs touched?
./scripts/docs/generate.sh && ./scripts/docs/check.sh
git push -u origin HEAD
# gh pr create → master
# wait for checks; fix on SAME branch
# squash merge when green
```

Branch prefixes: `feat/` `fix/` `refactor/` `docs/` `test/` `chore/`

Never push `master` for feature work. Never `--force` to `master`/`main`.

## Required reading by change type

| Change | Read first |
|--------|------------|
| Architecture / SoT | `docs/concepts/architecture.md` (or `docs/ARCHITECTURE.md` stub) |
| Add package/component/link | `docs/using/extending.md` |
| Skills | `docs/using/skills.md` + `configs/skills/manifest.toml` |
| Linux / distro CI | `docs/platforms/linux.md` |
| mactools | `docs/macos/mactools.md` |
| Agents / routing | `docs/agents/harness.md` + `skills/agent-router/SKILL.md` |
| Models | `configs/models.toml` + `docs/agents/models.md` |
| Docs site | `docs/maintainers/documentation.md` |
| Contributing / CI names | `CONTRIBUTING.md` |

Live docs: https://sempervent.github.io/dots/

## Sources of truth

| Thing | Authority |
|-------|-----------|
| Optional components / supergroups / brewfile map | `configs/components.toml` |
| Package groups | `configs/packages/groups.toml` |
| Homebrew groups | `brew/groups/*.Brewfile` |
| Component Brewfiles | `brew/Brewfile.<id>` |
| Aggregate Brewfile | `brew/Brewfile` (convenience only) |
| Linux names | `configs/packages/{apt,pacman,dnf,xbps}.toml` |
| Links | `configs/links.toml` |
| Skills | `configs/skills/manifest.toml` |
| Models | `configs/models.toml` |
| Profiles | `configs/bootstrap/profiles/*.toml` |
| Router defaults | `configs/agents/router.toml` |
| Router behavior | `skills/agent-router/SKILL.md` |
| Telemetry | `configs/agents/telemetry.toml` |
| `--with` ids | Loaded from `components.toml` — not hard-coded in `setup.sh` |

## Identify the owner before adding a dependency

```text
package group
  OR optional component
  OR skill (pack vs standalone)
  OR model / provider
  OR host-specific profile overlay
```

Then follow the matching recipe in `docs/using/extending.md`.

## Safety invariants

- `--show` / `--dry-run` never mutate
- Backup unmanaged collisions before replace; backup failure aborts
- External casks: warn → `brew install --cask --adopt` → leave on failure; never `--force`
- AI consent: profile / `--with` only — presence ≠ authorization
- Cursor is never auto-routed (`skills/agent-router/SKILL.md`)
- Do not invent coding cwd; do not default agents to `$HOME` or this repo
- Do not pull models in CI

## Entrypoints

| Script | Role |
|--------|------|
| `./dots` | Human CLI |
| `./bootstrap.sh` | Profile → Stage 0 → setup → check |
| `./setup.sh` | Packages / links / components |
| `./configure.sh` | Profile TOML only |
| `./scripts/check.sh` | Health |
| `./scripts/pull_models.sh` | Models |
| `./scripts/ci/lint.sh` / `test.sh` | Local validation |
| `./scripts/docs/*` | Docs generate / check / serve |
| `./scripts/ci/docs.sh` | Docs CI only (not every unit test) |

## Documentation product

- Site config: `mkdocs.yml`
- Generate: `python3 scripts/docs/generate_reference.py` (or `./scripts/docs/generate.sh`)
- Check: `./scripts/docs/check.sh` (`--check` + `mkdocs build --strict`)
- Pages: `.github/workflows/docs.yml` — PR build only; deploy on `master`
- Do not hand-edit `docs/reference/generated/*` or generated maintainer copies
- Do not use `mkdocs gh-deploy` / `gh-pages` branch

## Validation checklist

Before claiming done:

```bash
./scripts/ci/lint.sh
./scripts/ci/test.sh
# if docs/registries/nav/SKILL changed:
./scripts/docs/generate.sh
./scripts/docs/check.sh
```

After PR: inspect `gh pr checks` / Actions UI until green. Fix on the same
branch. Prefer squash merge.

## Reporting language

| Phrase | When |
|--------|------|
| local validation passed | lint/test (and docs check if applicable) succeeded locally |
| GitHub CI passed | PR/master Actions checks completed green |
| Docs build passed | Docs workflow job green |
| Pages live | https://sempervent.github.io/dots/ verified after deploy |

## Compatibility

`AGENTS.md` is a **thin shim** pointing here. Keep critical bootstrap rules in
`AGENTS.md` only. Do not fork a second full manual.

`skills/agent-router/SKILL.md` remains the routing policy skill — do not merge
it into this maintainer skill.
