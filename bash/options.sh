#!/usr/bin/env bash
# Bash-specific shell options

# Correct minor spelling errors in cd
shopt -s cdspell 2>/dev/null || true
# Include dotfiles in globbing; case-insensitive match
shopt -s dotglob 2>/dev/null || true
shopt -s nocaseglob 2>/dev/null || true
# Update LINES/COLUMNS after each command
shopt -s checkwinsize 2>/dev/null || true
# Extended globbing
shopt -s extglob 2>/dev/null || true
# ** recursive glob (Bash 4+)
shopt -s globstar 2>/dev/null || true

# Vi editing mode
set -o vi

# Show vi mode in prompt when interactive (readline)
if [[ "${-}" == *i* ]]; then
  bind 'set show-mode-in-prompt on' 2>/dev/null || true
  bind 'set vi-cmd-mode-string "\1\e[2q\2"' 2>/dev/null || true
  bind 'set vi-ins-mode-string "\1\e[6q\2"' 2>/dev/null || true
fi

# make less more friendly for non-text input files
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
