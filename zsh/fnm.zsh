# fnm — fast Node version manager (DOTS default)
# Order target: Homebrew PATH → fnm → project Node (.nvmrc / .node-version)
# Re-assert after Oh My Zsh: OMZ brew/path helpers often prepend ~/.local/bin,
# which would otherwise shadow fnm with a legacy ~/.local/bin/node.

_dots_fnm_init() {
  command -v fnm >/dev/null 2>&1 || return 0
  eval "$(fnm env --use-on-cd --shell zsh)"
}

_dots_fnm_init
