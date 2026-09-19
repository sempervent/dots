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
