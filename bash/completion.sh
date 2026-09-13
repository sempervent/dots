#!/usr/bin/env bash
# Bash completion — prefer Homebrew bash-completion@2 when present.
# Degrades gracefully if completion is unavailable.

source_if_exists() {
  [ -r "$1" ] && . "$1"
}

# System completions (Linux packages, etc.)
if ! shopt -oq posix 2>/dev/null; then
  source_if_exists /usr/share/bash-completion/bash_completion
  source_if_exists /etc/bash_completion
fi

# Homebrew bash-completion@2 (Apple Silicon / Intel / Linuxbrew)
# Caveat from the formula: source profile.d/bash_completion.sh
if command -v brew >/dev/null 2>&1; then
  _brew_prefix="$(brew --prefix 2>/dev/null || true)"
  if [ -n "${_brew_prefix}" ]; then
    source_if_exists "${_brew_prefix}/etc/profile.d/bash_completion.sh"
  fi
  unset _brew_prefix
fi

# Optional bash-git-prompt (via brew --prefix when installed)
if command -v brew >/dev/null 2>&1; then
  _bgp="$(brew --prefix bash-git-prompt 2>/dev/null || true)"
  if [ -n "${_bgp}" ]; then
    source_if_exists "${_bgp}/share/gitprompt.sh"
  fi
  unset _bgp
fi
source_if_exists /etc/bash_completion.d/git-prompt

# sudo completion when available
if [[ -n "${PS1:-}" ]]; then
  complete -cf sudo 2>/dev/null || true
fi
