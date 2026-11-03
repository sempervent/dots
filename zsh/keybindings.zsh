# Zsh keybindings — vi mode + DOTS key policy (single ownership layer)
#
# Reserved multiplexer prefixes (do NOT claim in Zsh):
#   Ctrl-Space  → tmux prefix
#   Ctrl-A      → Herdr prefix
#
# Shell map (v1.5.0):
#   Ctrl-R      → fuzzy/history (Atuin may own later)
#   Ctrl-T      → fzf-file-widget (configured in zsh/fzf.zsh)
#   Alt-C       → fzf-cd-widget
#   Tab /^I     → fzf-tab-complete
#   Ctrl-] /^]  → autosuggest-accept (ASCII 0x1D; passes through tmux)

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
# may rebind; re-applied from dots_bind_keybindings after plugins).
dots_bind_history_substring() {
  if zle -l 2>/dev/null | grep -q history-substring-search-up; then
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down
    bindkey -M vicmd 'k' history-substring-search-up
    bindkey -M vicmd 'j' history-substring-search-down
    bindkey -M viins '^[[A' history-substring-search-up
    bindkey -M viins '^[[B' history-substring-search-down
  fi
}

# Final DOTS key policy — call AFTER Oh My Zsh plugins (and after fzf-tab).
# Idempotent across `source ~/.zshrc`.
dots_bind_keybindings() {
  dots_bind_history_substring

  # Accept full autosuggestion on Ctrl-] (not Ctrl-Space — reserved for tmux).
  # zle -l may print "autosuggest-accept (_zsh_autosuggest_widget_accept)".
  if zle -l 2>/dev/null | grep -Eq '^autosuggest-accept([[:space:](]|$)'; then
    bindkey -M viins '^]' autosuggest-accept
    bindkey -M emacs '^]' autosuggest-accept 2>/dev/null || true
    # Also bind on main keymap when it aliases viins
    bindkey '^]' autosuggest-accept 2>/dev/null || true
  fi

  # Explicitly release Ctrl-Space / ^@ from any shell widget so tmux can own it.
  # Zsh often displays Ctrl-Space as ^@.
  if bindkey '^ ' 2>/dev/null | grep -q 'autosuggest-accept'; then
    bindkey -r '^ ' 2>/dev/null || true
    bindkey -M viins -r '^ ' 2>/dev/null || true
    bindkey -M emacs -r '^ ' 2>/dev/null || true
  fi
  if bindkey '^@' 2>/dev/null | grep -q 'autosuggest-accept'; then
    bindkey -r '^@' 2>/dev/null || true
    bindkey -M viins -r '^@' 2>/dev/null || true
    bindkey -M emacs -r '^@' 2>/dev/null || true
  fi
}
