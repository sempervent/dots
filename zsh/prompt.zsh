# Prompt ownership: Starship (DOTS three-line layout via configs/starship/starship.toml).
# Oh My Zsh theme stays empty (ZSH_THEME="") so OMZ does not fight Starship.
# Legacy box-drawing prompt removed — do not re-enable both.

# Starship may inherit STARSHIP_SHELL from a parent Bash/tmux session even when this
# Zsh instance has never run `starship init zsh`. Detect real hook registration.
_dots_starship_zsh_active() {
  (( ${precmd_functions[(Ie)prompt_starship_precmd]:-0} )) && return 0
  typeset -f prompt_starship_precmd >/dev/null 2>&1
}

if command -v starship >/dev/null 2>&1; then
  if ! _dots_starship_zsh_active; then
    eval "$(starship init zsh)"
    export DOTS_STARSHIP_ZSH_INITIALIZED=1
  fi
else
  unset DOTS_STARSHIP_ZSH_INITIALIZED 2>/dev/null || true
  # Minimal fallback when Starship is not yet installed
  PROMPT='%F{green}%n%f@%F{blue}%m%f %F{yellow}%~%f %# '
  RPROMPT=''
fi

unset -f _dots_starship_zsh_active 2>/dev/null || true
