# shellcheck shell=sh
# Shared PATH bootstrap (Bash + Zsh compatible)
# Prefer $HOME over hardcoded user paths.
#
# Order (intentional):
#   1. Homebrew  — canonical hermes-agent, formulae, casks' CLI
#   2. ~/.local/bin — DOTS launchers (notify, *-mcp) that do not shadow brew
#   3. ~/scripts
#   4. fnm (zsh/fnm.zsh) prepends active Node after this file
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
unset _dots_brew_prefix

# User local bins AFTER Homebrew so brew hermes/node win over stale shims
case ":${PATH}:" in
  *":${HOME}/.local/bin:"*) ;;
  *) PATH="${PATH}:${HOME}/.local/bin" ;;
esac

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
