# shellcheck shell=bash
# Optional modern CLI integrations shared by Bash and Zsh.
# Each block is a no-op when the tool is missing.

# zoxide — smarter cd (prefer over OMZ `z` plugin)
if command -v zoxide >/dev/null 2>&1; then
  case "${DOTS_SHELL:-}" in
    zsh)
      eval "$(zoxide init zsh)"
      ;;
    bash|*)
      eval "$(zoxide init bash)"
      ;;
  esac
fi

# direnv
if command -v direnv >/dev/null 2>&1; then
  case "${DOTS_SHELL:-}" in
    zsh)
      eval "$(direnv hook zsh)"
      ;;
    bash|*)
      eval "$(direnv hook bash)"
      ;;
  esac
fi

# leaf (markdown viewer) — completions dumped by setup into XDG share
# (do not run `leaf --auto-complete`; it mutates shell rc files)
_dots_leaf_comp_dir="${HOME}/.local/share/leaf/completions"
case "${DOTS_SHELL:-}" in
  zsh)
    if [ -f "${_dots_leaf_comp_dir}/_leaf" ]; then
      # shellcheck disable=SC1090
      . "${_dots_leaf_comp_dir}/_leaf"
    fi
    ;;
  bash)
    if [ -f "${_dots_leaf_comp_dir}/leaf.bash" ]; then
      # shellcheck disable=SC1090
      . "${_dots_leaf_comp_dir}/leaf.bash"
    fi
    ;;
esac
unset _dots_leaf_comp_dir

# atuin — local history search; config is provisioned by setup (not shell startup)
if command -v atuin >/dev/null 2>&1; then
  export ATUIN_CONFIG_DIR="${ATUIN_CONFIG_DIR:-${HOME}/.config/atuin}"
  case "${DOTS_SHELL:-}" in
    zsh)
      eval "$(atuin init zsh --disable-up-arrow)"
      ;;
    bash|*)
      eval "$(atuin init bash --disable-up-arrow)"
      ;;
  esac
fi
