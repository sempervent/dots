# shellcheck shell=sh
# Lightweight Catppuccin Mocha accents for tools that read env/config.
# Avoid expensive work at startup.

# fzf — Mocha-ish colors; preserve existing FZF_DEFAULT_OPTS when set
if [ -z "${FZF_DEFAULT_OPTS:-}" ]; then
  export FZF_DEFAULT_OPTS="--height=40% --layout=reverse --border --ansi \
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#cba6f7 \
--color=fg:#cdd6f4,header:#cba6f7,info:#89b4fa,pointer:#f5e0dc \
--color=pointer:#f38ba8,hl+:#cba6f7,fg+:#cdd6f4,marker:#a6e3a1 \
--color=prompt:#cba6f7,pointer:#f5e0dc"
fi

# Prefer bat Catppuccin theme when available (installed by setup)
if command -v bat >/dev/null 2>&1; then
  if bat --list-themes 2>/dev/null | grep -q 'Catppuccin Mocha'; then
    export BAT_THEME="${BAT_THEME:-Catppuccin Mocha}"
  fi
fi
