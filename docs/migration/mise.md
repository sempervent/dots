# mise / runtime-manager consolidation (analysis only)

`--with mactools` installs **mise** with a minimal `configs/mise/config.toml` and
**does not** activate it in shell init. This document maps current ownership so
any future migration stays intentional and reversible.

## Current runtime-manager map

| Runtime / tool | Current manager | Shell integration | Repo dependencies | Candidate for mise? |
|----------------|-----------------|-------------------|-------------------|---------------------|
| Node.js | **fnm** | `shell/fnm.sh` (`fnm env --use-on-cd`) | `brew "fnm"`, `configs/node/default.toml`, `helpers/fnm.sh` | Later (optional) — fnm is first-class today |
| npm/npx | via fnm Node | same | agent skills / Archify | Follows Node |
| Python interpreter | system / Homebrew / Stage 0 | none dedicated | `helpers/python_runtime.sh`, `helpers/bootstrap_prereqs.sh` | Possible for version pins |
| Python projects | **uv** (preferred) | none required | `brew "uv"`, packages groups | Keep **uv** for projects; mise may only pin interpreters |
| Go | not managed by dots | — | — | Optional later |
| Ruby | not managed | — | — | Optional later |
| Terraform | Homebrew `hashicorp/tap/terraform` + `terraform-ls` | PATH via brew | infra Brewfile | Prefer Homebrew (CLI plugins/taps) |
| Docker engine | Docker Desktop and/or OrbStack | docker context | infra Brewfile + mactools OrbStack | N/A (not a mise concern) |
| nvm | **retired** | explicitly not sourced | leftover `~/.nvm` may exist | Do not revive |
| pyenv / rbenv / asdf | not wired by DOTS | — | — | Only if user already depends on them locally |

## Suggested end state

- **Keep:** fnm for Node until a deliberate cutover; Homebrew for system CLIs; **uv** for Python packaging.
- **mise role:** optional version manager for languages you choose to migrate (Python toolchains, one-off CLIs), activated per-shell or per-project — not a silent global replacement.
- **Do not:** put Terraform/taps, Docker, or Homebrew formulae under mise “because we can.”

## Migration sequence (future work)

```text
Stage 1: mise installed, config linked, no shell activation   ← current with mactools
Stage 2: activate mise alongside fnm for a throwaway Node pin (non-default shell)
Stage 3: migrate one test project (.tool-versions / mise.toml)
Stage 4: remove duplicate init only after PATH smoke tests
Stage 5: repeat per runtime (Python interpreter ≠ uv projects)
Stage 6: uninstall obsolete managers only with explicit consent
```

## Rollback

1. Remove any `mise activate` lines from personal shell overlays (not committed by DOTS).
2. Confirm `shell/fnm.sh` still initializes Node.
3. `hash -r` / new shell; verify `command -v node` and `fnm current`.
4. Leave `~/.local/share/mise` in place or delete only after backups.

## See also

- `configs/mise/config.toml`
- `shell/fnm.sh`, `helpers/fnm.sh`, `configs/node/default.toml`
- [mactools](../macos/mactools.md)
