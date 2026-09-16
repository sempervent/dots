# shellcheck shell=sh
# Shared environment exports (Bash + Zsh compatible)
# Do NOT force TERM here — leave terminal/tmux negotiation alone.
#
# Precedence (multiplexer / greeting / prompt):
#   process env (already set) > ~/.config/dots/local.sh > runtime.env > these defaults

# Neovim is the DOTS-managed default editor (system /usr/bin/vim untouched)
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-nvim}"
export PAGER="${PAGER:-less}"
export LESS="${LESS:--R}"
export GZIP_OPT="${GZIP_OPT:--9}"

# Colored GCC diagnostics when available
export GCC_COLORS="${GCC_COLORS:-error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01}"

# Quiet OS detection (no echo on every shell launch)
case "$(uname -s 2>/dev/null)" in
  Darwin*)
    export OS="${OS:-Mac}"
    ;;
  CYGWIN*|MSYS*|MINGW*)
    export OS="${OS:-Win}"
    ;;
  *)
    export OS="${OS:-Nix}"
    export LS_OPTS="${LS_OPTS:---color=auto}"
    ;;
esac

# Modern tool defaults (graceful when tools absent)
if command -v bat >/dev/null 2>&1; then
  export BAT_THEME="${BAT_THEME:-ansi}"
  export MANPAGER="${MANPAGER:-sh -c 'col -bx | bat -l man -p'}"
fi

if command -v delta >/dev/null 2>&1; then
  export GIT_PAGER="${GIT_PAGER:-delta}"
fi

# Soft defaults — runtime.env / local.sh / process env win when already set
export DOTS_PROMPT_STATS="${DOTS_PROMPT_STATS:-0}"
export DOTS_AUTO_TMUX="${DOTS_AUTO_TMUX:-1}"
export DOTS_MULTIPLEXER="${DOTS_MULTIPLEXER:-tmux}"
export DOTS_GREETING="${DOTS_GREETING:-1}"
