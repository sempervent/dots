# Oh My Zsh bootstrap.
# zsh-syntax-highlighting must load after other widgets/plugins.

export ZSH="${ZSH:-${HOME}/.oh-my-zsh}"
export ZSH_CUSTOM="${ZSH_CUSTOM:-${ZSH}/custom}"
ZSH_THEME=""

# Do NOT enable OMZ extract (custom extract() in shell/functions.sh)
# Do NOT enable OMZ z (zoxide via shell/tools.sh)

_dots_omz_plugin_available() {
  local name="$1"
  [[ -d "${ZSH}/plugins/${name}" ]] || [[ -d "${ZSH_CUSTOM}/plugins/${name}" ]]
}

_dots_omz_plugins_candidate=(
  git
  brew
  docker
  docker-compose
  kubectl
  helm
  terraform
  tmux
  fzf
  uv
  vi-mode
  sudo
  colored-man-pages
  command-not-found
  aliases
  copypath
  copyfile
  copybuffer
  dirhistory
)

if [[ "$(uname -s)" == "Darwin" ]]; then
  _dots_omz_plugins_candidate+=(macos)
fi

# Third-party clones under $ZSH_CUSTOM/plugins (syntax-highlighting last)
_dots_omz_plugins_candidate+=(
  zsh-autosuggestions
  zsh-history-substring-search
  zsh-syntax-highlighting
)

plugins=()
for _p in "${_dots_omz_plugins_candidate[@]}"; do
  if _dots_omz_plugin_available "${_p}"; then
    plugins+=("${_p}")
  fi
done
unset _p _dots_omz_plugins_candidate

# shell/tmux.sh owns autostart — keep OMZ tmux plugin from forcing it
export ZSH_TMUX_AUTOSTART=false
export ZSH_TMUX_AUTOCONNECT=false

if [[ -f "${ZSH}/oh-my-zsh.sh" ]]; then
  source "${ZSH}/oh-my-zsh.sh"
else
  print -u2 "Oh My Zsh not found at ${ZSH}. Run ./setup.sh to install."
fi

if typeset -f dots_bind_history_substring >/dev/null 2>&1; then
  dots_bind_history_substring
fi

bindkey '^ ' autosuggest-accept 2>/dev/null || true
