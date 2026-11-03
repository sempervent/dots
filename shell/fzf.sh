# shellcheck shell=sh
# Shared fzf defaults for Bash and Zsh.
# Sourced from zsh/fzf.zsh and bash/fzf.sh — not from every shell entrypoint.

# Prefer fd (or Debian fdfind) for filesystem walks. Hidden files included;
# .git internals and common junk trees excluded. Searching from inside an
# excluded directory name (e.g. cwd is .venv) still lists that tree's contents
# because path components relative to the start dir do not include the name.
_dots_fzf_fd_bin() {
  if command -v fd >/dev/null 2>&1; then
    command -v fd
  elif command -v fdfind >/dev/null 2>&1; then
    command -v fdfind
  else
    return 1
  fi
}

_dots_fzf_fd_common_args='--hidden --follow --exclude .git --exclude node_modules --exclude target --exclude .venv --exclude __pycache__ --exclude dist --exclude build'

# Preview script path (fzf runs previews in a subprocess — shell functions are invisible there)
if [ -z "${DOTS_FZF_PREVIEW:-}" ]; then
  if [ -n "${DOTS_DIR:-}" ] && [ -x "${DOTS_DIR}/scripts/fzf-preview.sh" ]; then
    DOTS_FZF_PREVIEW="${DOTS_DIR}/scripts/fzf-preview.sh"
  elif [ -n "${DOTS_DIR:-}" ] && [ -f "${DOTS_DIR}/scripts/fzf-preview.sh" ]; then
    DOTS_FZF_PREVIEW="bash ${DOTS_DIR}/scripts/fzf-preview.sh"
  else
    DOTS_FZF_PREVIEW=""
  fi
  export DOTS_FZF_PREVIEW
fi

# Shell-callable wrapper (fzf-tab zstyles / interactive debugging)
dots_fzf_preview() {
  if [ -n "${DOTS_FZF_PREVIEW:-}" ]; then
    # shellcheck disable=SC2086
    eval "${DOTS_FZF_PREVIEW}" "$1"
    return $?
  fi
  printf '%s\n' "${1:-}"
  return 0
}

# Default commands — only set when unset so user/local overrides win.
if [ -z "${FZF_DEFAULT_COMMAND:-}" ]; then
  if _fd="$(_dots_fzf_fd_bin)"; then
    export FZF_DEFAULT_COMMAND="${_fd} ${_dots_fzf_fd_common_args}"
  fi
  unset _fd
fi

if [ -z "${FZF_CTRL_T_COMMAND:-}" ] && [ -n "${FZF_DEFAULT_COMMAND:-}" ]; then
  export FZF_CTRL_T_COMMAND="${FZF_DEFAULT_COMMAND}"
fi

if [ -z "${FZF_ALT_C_COMMAND:-}" ]; then
  if _fd="$(_dots_fzf_fd_bin)"; then
    export FZF_ALT_C_COMMAND="${_fd} --type d ${_dots_fzf_fd_common_args}"
  fi
  unset _fd
fi

if [ -z "${FZF_CTRL_T_OPTS:-}" ] && [ -n "${DOTS_FZF_PREVIEW:-}" ]; then
  export FZF_CTRL_T_OPTS="--preview '${DOTS_FZF_PREVIEW} {}' --preview-window=right:50%:wrap"
fi

if [ -z "${FZF_ALT_C_OPTS:-}" ] && [ -n "${DOTS_FZF_PREVIEW:-}" ]; then
  export FZF_ALT_C_OPTS="--preview '${DOTS_FZF_PREVIEW} {}' --preview-window=right:50%:wrap"
fi
