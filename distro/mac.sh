# shellcheck shell=bash
# macOS-specific initialization (portable aliases/functions live in shell/).

# Bash completion@2 via Homebrew (no-op under Zsh / if missing)
if [ -n "${BASH_VERSION:-}" ] && command -v brew >/dev/null 2>&1; then
  _bp="$(brew --prefix 2>/dev/null || true)"
  if [ -n "${_bp}" ] && [ -r "${_bp}/etc/profile.d/bash_completion.sh" ]; then
    # shellcheck disable=SC1090
    . "${_bp}/etc/profile.d/bash_completion.sh"
  fi
  unset _bp
fi

# Clipboard helpers
if command -v pbcopy >/dev/null 2>&1; then
  alias clip='pbcopy'
  alias paste='pbpaste'
fi
