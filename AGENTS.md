# Agent instructions (DOTS)

Canonical operating manual: **[`SKILL.md`](SKILL.md)** (`name: dots-maintainer`).

Read that file for sources of truth, safety invariants, docs workflow, and
validation. This shim keeps only bootstrap rules for tools that look for
`AGENTS.md`.

## Git workflow (required)

Do **not** commit or push feature/fix work directly to `master`.

```text
updated master → feature/fix branch → local validation
  → push branch → pull request → GitHub CI → merge when green
```

See `CONTRIBUTING.md` and `SKILL.md`.

## Reporting status

| Say this | When |
|----------|------|
| local validation passed | `./scripts/ci/lint.sh` / `./scripts/ci/test.sh` succeeded locally |
| GitHub CI passed | PR (or master) Actions checks actually completed green |

Never equate local validation with GitHub CI.

## No second source of truth

Do **not** invent a second source of truth. Prefer declarative registries
(`configs/components.toml`, `configs/packages/*`, `configs/skills/manifest.toml`,
`configs/links.toml`, `configs/models.toml`, …) over new hard-coded `case`
maps. Details: `SKILL.md`.

## Before architecture edits

```text
READ: SKILL.md
      docs/concepts/architecture.md   (or docs/ARCHITECTURE.md stub)
      docs/using/extending.md
```
