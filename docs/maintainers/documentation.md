# Documentation (maintainers)

How the DOTS documentation product is built, checked, and published.

## Stack

| Piece | Role |
|-------|------|
| `mkdocs.yml` | Site name, Material theme, nav, markdown extensions |
| `docs/` | Markdown sources |
| `docs/requirements.in` / `docs/requirements.txt` | Pinned MkDocs + Material |
| `scripts/docs/generate_reference.py` | Registries → `docs/reference/generated/` + maintainer copies |
| `scripts/docs/generate.sh` | Wrapper to regenerate |
| `scripts/docs/check.sh` | `--check` + `mkdocs build --strict` |
| `scripts/docs/serve.sh` | Local preview |
| `scripts/ci/docs.sh` | CI install + check (Docs workflow only) |
| `.github/workflows/docs.yml` | PR build; master deploy to GitHub Pages |

Site URL: https://sempervent.github.io/dots/

## Local workflow

```bash
./scripts/docs/generate.sh          # refresh generated pages
./scripts/docs/serve.sh             # http://127.0.0.1:8000/
./scripts/docs/check.sh             # drift + strict build
```

Create/update the venv under `.tools/docs-venv` (gitignored via `.tools/` if
present). Pin bumps:

```bash
# Prefer:
uv pip compile docs/requirements.in -o docs/requirements.txt --generate-hashes
```

## Generated pages

Do **not** hand-edit:

- `docs/reference/generated/*.md`
- `docs/maintainers/{contributing,agents,skill}.md` (copies of root files)

Each file starts with a `GENERATED — DO NOT EDIT` HTML comment naming the source.

`generate_reference.py --check` fails CI when outputs drift.

## Content rules

- Ground claims in repo TOML / scripts — no invented flags or components
- Label future work explicitly (e.g. ZFS `file-tank`, Pi OS image CI)
- No secrets or machine-local state in generated docs
- Prefer expanding pages under `docs/` over duplicating SoT in README
- Old top-level `docs/*.md` stubs point here for GitHub browsing + link checks

## Publishing

- **Pull requests:** Docs build job runs strict build; **no** deploy
- **master push / workflow_dispatch:** build + `upload-pages-artifact` + `deploy-pages`
- Do **not** use `mkdocs gh-deploy` or a `gh-pages` branch

Pages source must be **GitHub Actions** (Settings → Pages). If the live site
404s after a green deploy, check that setting.

## Related unit tests

`scripts/ci/test.sh` does **not** install MkDocs. Light contract coverage lives in
`scripts/tests/repository_contract_test.sh` (`mkdocs.yml`, `SKILL.md`, AGENTS
pointer, generator path).
