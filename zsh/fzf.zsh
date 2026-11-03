# zsh/fzf.zsh — fzf widgets + fzf-tab configuration
#
# Load AFTER Oh My Zsh (so the fzf plugin / fzf-tab may already be present)
# and BEFORE shell/tools.sh (so Atuin can own Ctrl-R afterward).
#
# Ownership after a healthy startup:
#   Tab / ^I     → fzf-tab-complete (contextual compsys candidates)
#   Ctrl-T       → fzf-file-widget
#   Alt-C        → fzf-cd-widget (when the terminal delivers Meta-c)
#   Ctrl-R       → Atuin when installed, else fzf-history-widget / native
#   Ctrl-]       → autosuggest-accept (owned by zsh/keybindings.zsh)
#   Ctrl-Space   → RESERVED tmux prefix (never shell)
#   **<Tab>      → fzf native recursive completion (via fzf-completion orig)

[[ -f "${DOTS_DIR}/shell/fzf.sh" ]] && source "${DOTS_DIR}/shell/fzf.sh"

# Ensure fzf keybindings + ** completion exist once (OMZ fzf plugin preferred).
# Do not re-run when widgets already registered — avoids duplicate hooks on reload.
if ! typeset -f fzf-file-widget >/dev/null 2>&1; then
  if command -v fzf >/dev/null 2>&1; then
    if fzf --zsh >/dev/null 2>&1; then
      source <(fzf --zsh)
    elif [[ -f "${HOME}/.fzf.zsh" ]]; then
      source "${HOME}/.fzf.zsh"
    fi
  fi
fi

# fd-backed generators for fzf's explicit ** path/dir completion
if _dots_fd_bin="$(_dots_fzf_fd_bin 2>/dev/null)"; then
  _fzf_compgen_path() {
    local fd="${_dots_fd_bin}"
    "${fd}" --hidden --follow \
      --exclude .git --exclude node_modules --exclude target \
      --exclude .venv --exclude __pycache__ --exclude dist --exclude build \
      . "$1"
  }
  _fzf_compgen_dir() {
    local fd="${_dots_fd_bin}"
    "${fd}" --type d --hidden --follow \
      --exclude .git --exclude node_modules --exclude target \
      --exclude .venv --exclude __pycache__ --exclude dist --exclude build \
      . "$1"
  }
fi
unset _dots_fd_bin

# fzf-tab configuration (plugin loaded via Oh My Zsh when installed)
if zle -l 2>/dev/null | grep -q '^fzf-tab-complete$' \
  || typeset -f enable-fzf-tab >/dev/null 2>&1; then

  # Group headers + disable classic menu so fzf-tab can capture candidates
  zstyle ':completion:*:descriptions' format '[%d]'
  zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
  zstyle ':completion:*' menu no
  zstyle ':completion:*:git-checkout:*' sort false

  # Multi-select: Ctrl-Y (Ctrl-Space is reserved for tmux prefix — never use it here)
  zstyle ':fzf-tab:*' fzf-bindings-default \
    'tab:down' \
    'btab:up' \
    'change:top' \
    'ctrl-y:toggle' \
    'bspace:backward-delete-char/eof' \
    'ctrl-h:backward-delete-char/eof'
  zstyle ':fzf-tab:*' switch-group '<' '>'
  zstyle ':fzf-tab:*' continuous-trigger '/'

  # Restrained bottom panel; colors come from FZF_DEFAULT_OPTS when safe
  zstyle ':fzf-tab:*' use-fzf-default-opts yes
  zstyle ':fzf-tab:*' fzf-flags --height=50% --layout=reverse --info=inline --border

  # tmux popup only inside real tmux (not required; Herdr falls back to height UI)
  if [[ -n "${TMUX:-}" ]] && typeset -f ftb-tmux-popup >/dev/null 2>&1; then
    zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup
  fi

  # Generic preview for file/dir candidates (subprocess-safe script)
  # fzf-tab expands $realpath / $word in the preview string.
  if [[ -n "${DOTS_FZF_PREVIEW:-}" ]]; then
    zstyle ':fzf-tab:complete:*:*' fzf-preview "${DOTS_FZF_PREVIEW}"' $realpath'
  fi
  zstyle ':fzf-tab:complete:*:options' fzf-preview
  zstyle ':fzf-tab:complete:*:argument-rest' fzf-preview

  # Git previews (best-effort; empty word → no-op)
  zstyle ':fzf-tab:complete:git-(checkout|switch|branch|merge|rebase|cherry-pick|log|show|reset):*' \
    fzf-preview 'git log --oneline --decorate --graph -20 --color=always $word 2>/dev/null || true'
  zstyle ':fzf-tab:complete:git-show:*' \
    fzf-preview 'git show --stat --oneline --decorate --color=always $word 2>/dev/null || true'

  # Environment variable names only (no values)
  zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' \
    fzf-preview 'print -r -- $word'

  # Ensure Tab is owned by fzf-tab after any later wrapping
  bindkey -M emacs '^I' fzf-tab-complete
  bindkey -M viins '^I' fzf-tab-complete
fi
