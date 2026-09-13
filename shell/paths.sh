# shellcheck shell=sh
# Shared PATH bootstrap (Bash + Zsh compatible)
# Prefer $HOME over hardcoded user paths. Detect Homebrew once bootstrapped.

# Local user bins
case ":${PATH}:" in
  *":${HOME}/.local/bin:"*) ;;
  *) PATH="${HOME}/.local/bin:${PATH}" ;;
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

export PATH
