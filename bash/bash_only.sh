#!/usr/bin/env bash
# Bash-only helpers that are not safe/portable in shared shell/functions.sh

# Re-run previous command with sudo (Bash history expansion)
# In Zsh, prefer the Oh My Zsh `sudo` plugin (Esc Esc).
ffs() {
  sudo "$BASH" -c "$(history -p '!!')"
}

# Reload bashrc
so() {
  # shellcheck disable=SC1090
  source "${HOME}/.bashrc"
}
alias reload='so'
