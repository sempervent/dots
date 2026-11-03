# Zsh: ensure generated `_dots` is on fpath and registered.
# Primary install path: ~/.local/share/zsh/site-functions/_dots (setup symlink).
# Repo fallback: $DOTS_DIR/generated/completions for developers before setup.

_dots_site="${HOME}/.local/share/zsh/site-functions"
_dots_repo="${DOTS_DIR}/generated/completions"

if [[ -d ${_dots_site} ]]; then
  case " ${fpath} " in
    *" ${_dots_site} "*) ;;
    *) fpath=("${_dots_site}" ${fpath}) ;;
  esac
fi
if [[ -f ${_dots_repo}/_dots ]]; then
  case " ${fpath} " in
    *" ${_dots_repo} "*) ;;
    *) fpath=("${_dots_repo}" ${fpath}) ;;
  esac
fi

autoload -Uz compinit 2>/dev/null || true
# Avoid heavy re-init if already done; still ensure _dots is known
if ! typeset -f _dots >/dev/null 2>&1; then
  autoload -Uz _dots 2>/dev/null || true
fi
compdef _dots dots 2>/dev/null || true
compdef _dots ./dots 2>/dev/null || true

unset _dots_site _dots_repo
