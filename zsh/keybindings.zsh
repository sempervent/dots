# Zsh keybindings — vi mode with usable arrows + history-substring-search

# Short KEYTIMEOUT so Esc feels snappy in vi mode (units of 10ms; 1 = 10ms)
KEYTIMEOUT=1

# Native vi keymap (OMZ vi-mode plugin also sets this; safe either way)
bindkey -v

# Keep backspace / delete usable in insert mode
bindkey '^?' backward-delete-char
bindkey '^[[3~' delete-char
bindkey -M vicmd '^[[3~' delete-char

# Arrow keys in both insert and command mode
bindkey '^[[A' up-line-or-history
bindkey '^[[B' down-line-or-history
bindkey -M vicmd '^[[A' up-line-or-history
bindkey -M vicmd '^[[B' down-line-or-history

# Word movement
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[b' backward-word
bindkey '^[f' forward-word

# History search (Ctrl-R); Atuin may also bind this when enabled
bindkey '^R' history-incremental-search-backward

# Integrate history-substring-search when the widget exists (plugin loaded later
# may rebind; we also call dots_bind_history_substring from zshrc after plugins).
dots_bind_history_substring() {
  if zle -l | grep -q history-substring-search-up; then
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down
    bindkey -M vicmd 'k' history-substring-search-up
    bindkey -M vicmd 'j' history-substring-search-down
    bindkey -M viins '^[[A' history-substring-search-up
    bindkey -M viins '^[[B' history-substring-search-down
  fi
}
