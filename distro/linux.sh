# shellcheck shell=bash
# Linux-specific initialization (portable aliases/functions live in shell/).

if [ -n "${BASH_VERSION:-}" ]; then
  if [ -r /usr/share/bash-completion/bash_completion ]; then
    # shellcheck disable=SC1091
    . /usr/share/bash-completion/bash_completion
  elif [ -r /etc/bash_completion ]; then
    # shellcheck disable=SC1091
    . /etc/bash_completion
  fi
fi

if command -v xclip >/dev/null 2>&1; then
  alias clip='xclip -selection clipboard'
  alias paste='xclip -selection clipboard -o'
elif command -v wl-copy >/dev/null 2>&1; then
  alias clip='wl-copy'
  alias paste='wl-paste'
fi
