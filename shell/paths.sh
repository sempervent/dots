# shellcheck shell=sh
# Shared PATH bootstrap (Bash + Zsh compatible)
# Prefer $HOME over hardcoded user paths.
#
# Order (intentional):
#   1. Homebrew bin/sbin — canonical hermes-agent, formulae, casks
#   2. ~/.local/bin      — DOTS launchers (img, notify, *-mcp, agent-stats, …)
#   3. remaining PATH entries (deduped)
#   4. ~/scripts
#   5. fnm (zsh/fnm.zsh) prepends active Node after this file
#
# Do NOT put ~/.local/bin ahead of Homebrew: Hermes git-install used to
# symlink node/npm/hermes there and shadowed managed tools.

# Homebrew: Apple Silicon / Intel macOS / Linuxbrew
_dots_brew_prefix=""
if command -v brew >/dev/null 2>&1; then
  _dots_brew_prefix="$(brew --prefix 2>/dev/null || true)"
elif [ -x /opt/homebrew/bin/brew ]; then
  _dots_brew_prefix="/opt/homebrew"
elif [ -x /usr/local/bin/brew ]; then
  _dots_brew_prefix="/usr/local"
elif [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  _dots_brew_prefix="/home/linuxbrew/.linuxbrew"
fi

if [ -n "${_dots_brew_prefix}" ] && [ -x "${_dots_brew_prefix}/bin/brew" ]; then
  # shellcheck disable=SC1090
  eval "$("${_dots_brew_prefix}/bin/brew" shellenv)"
fi

# Rebuild ordered PATH. Zsh and Bash need different split/join (no SH_WORD_SPLIT in zsh).
if [ -n "${ZSH_VERSION:-}" ]; then
  # shellcheck disable=SC2296,SC2206
  typeset -gU path
  _dots_rest=()
  for _dots_p in "${path[@]}"; do
    [ -z "${_dots_p}" ] && continue
    [ "${_dots_p}" = "${HOME}/.local/bin" ] && continue
    if [ -n "${_dots_brew_prefix}" ]; then
      [ "${_dots_p}" = "${_dots_brew_prefix}/bin" ] && continue
      [ "${_dots_p}" = "${_dots_brew_prefix}/sbin" ] && continue
    fi
    _dots_rest+=("${_dots_p}")
  done
  if [ -n "${_dots_brew_prefix}" ]; then
    path=("${_dots_brew_prefix}/bin" "${_dots_brew_prefix}/sbin" "${HOME}/.local/bin" "${_dots_rest[@]}")
  else
    path=("${HOME}/.local/bin" "${_dots_rest[@]}")
  fi
  unset _dots_rest _dots_p
  # PATH stays synced with path via typeset -U path PATH (options.zsh) or export:
  export PATH
else
  # Bash / POSIX: strip then prepend
  _dots_path_remove() {
    _dots_remove="$1"
    _dots_new=""
    _dots_oldifs=$IFS
    IFS=:
    # shellcheck disable=SC2086
    for _dots_p in $PATH; do
      [ -z "${_dots_p}" ] && continue
      [ "${_dots_p}" = "${_dots_remove}" ] && continue
      if [ -z "${_dots_new}" ]; then
        _dots_new="${_dots_p}"
      else
        _dots_new="${_dots_new}:${_dots_p}"
      fi
    done
    IFS=${_dots_oldifs}
    PATH="${_dots_new}"
    unset _dots_remove _dots_new _dots_oldifs _dots_p
  }
  _dots_path_remove "${HOME}/.local/bin"
  if [ -n "${_dots_brew_prefix}" ]; then
    _dots_path_remove "${_dots_brew_prefix}/bin"
    _dots_path_remove "${_dots_brew_prefix}/sbin"
    PATH="${_dots_brew_prefix}/bin:${_dots_brew_prefix}/sbin:${HOME}/.local/bin${PATH:+:${PATH}}"
  else
    PATH="${HOME}/.local/bin${PATH:+:${PATH}}"
  fi
  unset -f _dots_path_remove 2>/dev/null || true
  export PATH
fi
unset _dots_brew_prefix

# Append ~/scripts and JAVA_HOME/bin if missing (both shells)
case ":${PATH}:" in
  *":${HOME}/scripts:"*) ;;
  *) PATH="${PATH}:${HOME}/scripts" ;;
esac

if [ -n "${JAVA_HOME:-}" ]; then
  case ":${PATH}:" in
    *":${JAVA_HOME}/bin:"*) ;;
    *) PATH="${PATH}:${JAVA_HOME}/bin" ;;
  esac
fi

export PATH
