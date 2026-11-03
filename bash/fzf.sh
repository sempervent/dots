# shellcheck shell=bash
# bash/fzf.sh — official fzf Bash integration (no fzf-tab; Zsh-only).
#
# Load BEFORE shell/tools.sh so Atuin can own Ctrl-R when present.
# Provides: Ctrl-R (until Atuin), Ctrl-T, Alt-C, **<Tab> completion.

# shellcheck disable=SC1091
[ -f "${DOTS_DIR}/shell/fzf.sh" ] && . "${DOTS_DIR}/shell/fzf.sh"

if ! command -v fzf >/dev/null 2>&1; then
  return 0
fi

# Idempotent: skip full init when widgets already registered (reload-safe)
if ! declare -F __fzf_select__ >/dev/null 2>&1 && ! bind -q '\C-t' 2>/dev/null; then
  if fzf --bash >/dev/null 2>&1; then
    # shellcheck disable=SC1090
    eval "$(fzf --bash)"
  elif [ -f "${HOME}/.fzf.bash" ]; then
    # shellcheck disable=SC1091
    . "${HOME}/.fzf.bash"
  fi
fi

# fd-backed generators for ** completion (override fzf defaults when fd exists)
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

# Extra path/dir completion for common tools when the helper exists
if declare -F _fzf_setup_completion >/dev/null 2>&1; then
  _fzf_setup_completion path git kubectl helm terraform docker npm cargo go uv 2>/dev/null || true
  _fzf_setup_completion dir cd 2>/dev/null || true
fi
