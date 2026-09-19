# Repository layout

High-level map of the DOTS tree (not every file).

```text
dots/                          unified CLI
bootstrap.sh                   profile → Stage 0 → setup → check
setup.sh                       packages / links / optional components
configure.sh                   profile TOML editor only
AGENTS.md                      thin agent bootstrap → SKILL.md
SKILL.md                       canonical maintainer operating manual
CONTRIBUTING.md                branch / PR / CI policy
README.md                      human entry + ownership summary

configs/
  components.toml              optional components + supergroups
  links.toml                   managed symlinks
  models.toml                  local model registry
  agents/                      router, telemetry, execution defaults
  bootstrap/profiles/          built-in profiles
  packages/                    groups + apt/pacman/dnf/xbps maps
  skills/manifest.toml         skill packs
  mactools/                    portable GUI export notes / samples
  herdr/, mise/, nvim/, …      component configs

brew/
  groups/*.Brewfile            canonical group ownership
  Brewfile.<component>         optional component fragments
  Brewfile                     convenience aggregate

helpers/                       Bash libraries (packages, backup, models, …)
shell/                         shared interactive shell logic
bash/ zsh/                     shell-specific
skills/                        in-repo skills (e.g. agent-router)
examples/profiles/             custom profile templates
docs/                          MkDocs product (this site)
scripts/
  ci/                          lint, test, distro smoke, docs
  docs/                        generate / check / serve
  tests/                       contract + unit-style shell tests
  mactools/                    export/import / docker audit
tools/                         small Python MCP / telemetry helpers
syms/                          link sources (active ⊂ links.toml)
distro/                        mac/linux entry helpers
.github/workflows/             CI + docs Pages
```

## Documentation product

| Path | Role |
|------|------|
| `mkdocs.yml` | Site config + nav |
| `docs/` | Markdown pages |
| `docs/reference/generated/` | Generator output (do not hand-edit) |
| `scripts/docs/generate_reference.py` | Registry → Markdown |
| `.github/workflows/docs.yml` | Strict build + GitHub Pages deploy |

## Related

- [Architecture](architecture.md)
- [Documentation maintainers guide](../maintainers/documentation.md)
