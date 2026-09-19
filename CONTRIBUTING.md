# Contributing to DOTS

## No direct commits to `master`

All nontrivial changes use a feature/fix branch and a pull request.

```text
git fetch origin
git switch master
git pull --ff-only origin master
git switch -c <type>/<description>

# implement + local validation
./scripts/ci/lint.sh
./scripts/ci/test.sh

git push -u origin <branch>
# open PR targeting master
# wait for GitHub Actions — fix on the SAME branch until green
# merge only after required checks pass
```

Recommended branch prefixes: `feat/` `fix/` `refactor/` `docs/` `test/` `chore/`

## Local validation vs GitHub CI

These are distinct:

| Phrase | Meaning |
|--------|---------|
| **local validation passed** | lint/tests ran successfully on a developer machine |
| **GitHub CI passed** | the Actions checks on the PR (or post-merge `master`) completed successfully |

Do **not** report "CI green" from local validation alone. Agents must inspect the
actual PR check runs before claiming completion.

Pinned lint tools (see `scripts/ci/tool-versions.env`):

```text
ShellCheck 0.11.0
shfmt 3.12.0
```

`./scripts/ci/lint.sh` bootstraps these into `.tools/bin` (SHA-256 verified).

## Pull requests

- Target `master`.
- Prefer **squash merge** for agent/feature work; the PR title becomes the
  durable `master` commit subject (Conventional Commits, e.g. `fix(ci): …`).
- Intermediate branch commits need not remain in permanent history.

## GitHub repository settings (manual)

Configure a `master` ruleset / branch protection (admin UI; not automated here):

```text
Require a pull request before merging
Require status checks to pass before merging
Block force pushes
Block branch deletion
Require conversation resolution before merging
```

For this single-maintainer repository:

```text
Do NOT require one approving review by default
```

Suggested required checks (names from `.github/workflows/ci.yml`):

```text
Ubuntu test
Distro smoke (Ubuntu 24.04)
Distro smoke (Debian 13)
Distro smoke (Arch)
Distro smoke (Manjaro)
Distro smoke (Fedora)
Distro smoke (Void)
ARM64 smoke (Debian 13)
macOS smoke
```

## Safety notes

- Never weaken backup gates or dry-run brew-safety for convenience.
- Do not commit secrets, credentials, or unrelated local scratch files.
