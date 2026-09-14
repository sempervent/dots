# Prompt ownership: Starship (Catppuccin Mocha Powerline).
# Oh My Zsh theme stays empty (ZSH_THEME="") so OMZ does not fight Starship.
# Legacy box-drawing prompt removed — do not re-enable both.

if command -v starship >/dev/null 2>&1; then
  # Avoid double-init if something else already hooked Starship
  if [[ -z "${STARSHIP_SHELL:-}" ]]; then
    eval "$(starship init zsh)"
  fi
else
  # Minimal fallback when Starship is not yet installed
  PROMPT='%F{green}%n%f@%F{blue}%m%f %F{yellow}%~%f %# '
  RPROMPT=''
fi
