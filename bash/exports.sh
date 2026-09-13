#!/usr/bin/env bash
# Bash environment leftovers — prefer shell/exports.sh + bash/history.sh.
# Kept for reference; bashrc no longer sources this file.
export EDITOR="${EDITOR:-vim}"
export LS_OPTS="${LS_OPTS:---color=auto}"
export GZIP_OPT="${GZIP_OPT:--9}"
export GCC_COLORS="${GCC_COLORS:-error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01}"
# NOTE: Do not force TERM here. History lives in bash/history.sh.
