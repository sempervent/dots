# Zsh options (interactive)
# Do NOT enable CORRECT / CORRECT_ALL — they interfere with modern/custom commands.
unsetopt CORRECT 2>/dev/null || true
unsetopt CORRECT_ALL 2>/dev/null || true

setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
setopt COMPLETE_IN_WORD
setopt ALWAYS_TO_END
setopt PATH_DIRS
setopt AUTO_MENU
setopt AUTO_LIST
setopt AUTO_PARAM_SLASH
setopt EXTENDED_GLOB
setopt NO_BEEP
setopt NO_NOMATCH
setopt INTERACTIVE_COMMENTS
setopt PROMPT_SUBST

# Deduplicate path entries; order is owned by shell/paths.sh (brew → ~/.local/bin).
# Do not prepend ~/.local/bin here — that shadows Homebrew hermes/node.
typeset -U path PATH
[[ -d "${HOME}/scripts" ]] && path+=("${HOME}/scripts")
[[ -n "${JAVA_HOME:-}" && -d "${JAVA_HOME}/bin" ]] && path+=("${JAVA_HOME}/bin")
export PATH
