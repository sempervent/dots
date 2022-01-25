export EDITOR='vim'
export LS_OPTS='--color=auto'
export GZIP_OPT=-9
export TERM=xterm-256color
# Colored Gcc errors and warnings
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
export HSTR_CONFIG=hicolor       # get more colors
export HISTCONTROL=ignoresboth   # leading space hides commands from history
export HISTFILESIZE=10000        # increase history file size (default is 500)
export HISTSIZE=${HISTFILESIZE}  # increase history size (default is 500)
# ensure synchronization between bash memory and history file
export PROMPT_COMMAND="history -a; history -n; ${PROMPT_COMMAND}"
