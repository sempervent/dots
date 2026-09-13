#!/usr/bin/env bash
# Bash history — intentional settings (single source of truth)
#
# Semantic intent:
# - ignoreboth: drop duplicates and commands starting with a space
# - histappend / prompt sync: share history across interactive sessions
# - large but reasonable HISTSIZE / HISTFILESIZE

HISTCONTROL=ignoreboth
HISTSIZE=100000
HISTFILESIZE=200000
HISTTIMEFORMAT='%F %T '
HISTIGNORE='ls:ll:la:cd:pwd:exit:clear:history'

shopt -s histappend
shopt -s cmdhist
shopt -s lithist 2>/dev/null || true

# Sync history across sessions without clobbering the custom prompt's PROMPT_COMMAND.
# Append our syncers; prompt.sh will compose the final PROMPT_COMMAND.
_dots_bash_history_sync() {
  history -a
  history -n
}
