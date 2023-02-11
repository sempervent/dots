# ignore duplicates and lines starting with a space
HISTCONTROL=ignoreboth
# append to the history file
shopt -s histappend
# save multiline command as a single command
shopt -s cmdhist
# give lots of history
HISTSIZE=10000000
HISTFILESIZE=2000000
