# Bash configuration

Bash-only modules. Shared aliases/functions/paths live in `../shell/`.

| File | Role |
|------|------|
| `options.sh` | `shopt`, vi mode, readline mode indicator |
| `history.sh` | Intentional Bash history (ignoreboth, histappend, large HISTSIZE) |
| `completion.sh` | bash-completion + optional git-prompt |
| `colors.sh` | Color vars for the classic prompt |
| `prompt.sh` | Box-drawing `PROMPT_COMMAND` prompt |
| `bash_only.sh` | `ffs`, `so` / `reload` |
| `exports.sh` | Legacy stub (not sourced; see `shell/exports.sh`) |
| `functions.sh` | Legacy duplicates — **not sourced**; logic moved to `shell/functions.sh` |
| `aliases.sh` | Legacy duplicates — **not sourced**; logic moved to `shell/aliases.sh` |

Entrypoint: `syms/bashrc`.
