# Local CI feedback loop

DOTS catches cheap, deterministic failures **before** `git push`. GitHub Actions
still owns final multi-platform / integration validation (Phase 11 and ongoing).

## Quick start

```bash
# Requires package group `dev` (work/home profiles include it):
./setup.sh --profile work
# or: ./setup.sh --packages core,modern,dev

./dots check fast          # cheap deterministic validators
./dots check workflows     # actionlint + zizmor
./dots check docs          # markdownlint + cspell + lychee (HTTP)
./dots check docs --offline
./dots check all-local     # fast + full links + pre-commit
./dots check act list      # list jobs act can see (needs container runtime)
./dots check release-notes # git-cliff preview to stdout (never writes CHANGELOG)
```

Validation is **read-only**: it never installs packages, never rewrites profiles,
and never starts Docker Desktop / OrbStack.

## What `fast` runs

| Check | Tool | Notes |
|-------|------|-------|
| Workflow syntax | `actionlint` | All `.github/workflows/*` |
| Workflow security | `zizmor` | Offline; informational findings do not fail |
| Dockerfiles | `hadolint` | Skips cleanly when none exist |
| Markdown | `markdownlint-cli2` | Project config: `.markdownlint-cli2.jsonc` |
| Spelling | `cspell` | Dictionary: `cspell.json` |
| Shell subset | `shellcheck` + `shfmt` | New CI surface + existing lint script |
| Internal links | `lychee --exclude '^https?://'` | No public internet required |

## What remains GitHub-only

- Full distro / OS matrices
- macOS runners and privileged jobs
- Paid external services
- Final release convergence

`act` can reproduce **some** Linux-compatible jobs locally. It is **not** a
complete substitute for GitHub-hosted runners.

## Workflow audit

```bash
./dots check workflows
```

- `actionlint` — syntax, expressions, workflow semantics
- `zizmor` — dangerous CI patterns (unpinned Actions, broad permissions, …)

Policy config: `.github/zizmor.yml`. Prefer fixing workflows over broad ignores.

## Documentation validation

```bash
./dots check docs --offline   # internal references only
./dots check docs             # includes external HTTP (transient 429 accepted)
```

Configs: `.markdownlint-cli2.jsonc`, `cspell.json`, `.lychee.toml`.

## Dockerfiles and pre-commit

- `hadolint` runs whenever Dockerfiles are discovered under the repo
  (`Dockerfile`, `Dockerfile.*`, `*.Dockerfile`), excluding vendor/generated trees.
- Full `pre-commit run --all-files` is part of `all-local` (not `fast`).
- DOTS **does not** auto-install git hooks. To enable hooks explicitly:

  ```bash
  pre-commit install
  ```

## Release-note preview

```bash
./dots check release-notes
```

Uses `cliff.toml` and prints notes since the previous `v*` tag. It never
overwrites `CHANGELOG.md`.

## `act` (already installed via `dev`)

```bash
./dots check act list
./dots check act <job>
```

Requirements:

- `act` on PATH (package group `dev`)
- A container runtime already running (`docker` or `podman`)

DOTS never forwards host secrets into `act` and never auto-starts a container GUI.

## Missing tools

If validators are not installed:

```text
Missing local validation tools.
  ./setup.sh --profile work
  ./setup.sh --packages core,modern,dev
```

## Package ownership

All Phase 1 validators live in package group **`dev`** (one authoritative owner).
There is no separate `ci` group.
