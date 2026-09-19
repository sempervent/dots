# Agent instructions (DOTS)

## Git workflow (required)

Do **not** commit or push feature/fix work directly to `master`.

```text
updated master → feature/fix branch → local validation
  → push branch → pull request → GitHub CI → merge when green
```

See `CONTRIBUTING.md` for the full policy.

## Reporting status

| Say this | When |
|----------|------|
| local validation passed | `./scripts/ci/lint.sh` / `./scripts/ci/test.sh` succeeded locally |
| GitHub CI passed | PR (or master) Actions checks actually completed green |

Never equate local validation with GitHub CI.

After opening a PR, inspect check runs (`gh pr checks` / Actions UI). If checks
fail, fix on the **same** branch, push again, and wait — do not push `master`.

## Required reading before architecture edits

Before modifying dependency / component / skill / profile / link / model / distro
architecture:

```text
READ:
  docs/EXTENDING.md
  docs/ARCHITECTURE.md
```

Before modifying skills:

```text
docs/SKILLS.md
```

Before modifying Linux mappings or distro CI:

```text
docs/LINUX.md
```

Tool catalog (conceptual ownership + upstream links):

```text
docs/TOOLS.md
```

## No second source of truth

Do **not** invent a second source of truth.

Prefer extending declarative registries over adding new hard-coded `case`
statements:

| Extend this | Instead of |
|-------------|------------|
| `configs/components.toml` | hard-coded Brewfile maps / manual `SUPPORTED_WITH` lists |
| `configs/packages/groups.toml` + `brew/groups/*.Brewfile` | editing only top-level `brew/Brewfile` |
| `configs/skills/manifest.toml` | ad-hoc skill install scripts |
| `configs/links.toml` | one-off `ln` in setup without backup |

`SUPPORTED_WITH` is loaded from `configs/components.toml` — do not tell future
editors to hard-code ids in `setup.sh`.

## Identify the owner

If adding a dependency, identify its owner first:

```text
package group
  OR optional component
  OR skill (pack vs standalone)
  OR model / provider
  OR host-specific profile overlay
```

Then follow the matching recipe in `docs/EXTENDING.md`.
