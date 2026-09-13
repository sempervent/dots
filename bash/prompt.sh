#!/usr/bin/env bash
# Bash prompt — preserves the classic box-drawing aesthetic.
# Requires bash/colors.sh for color vars.
#
# Directory file count / size are gated by DOTS_PROMPT_STATS=1 (default off)
# because they can be expensive on large directories.

render_git_info() {
  local branch remote
  branch="$(parse_git_branch)"
  if [ -n "${branch}" ]; then
    remote="$(parse_git_remote)"
    if [ -n "${remote}" ]; then
      echo "─┤${LYEL}${remote}->${branch}├─"
    else
      echo "─┤${LYEL}${branch}├─"
    fi
  else
    echo "─"
  fi
}

render_prompt_command() {
  # History sync (from bash/history.sh)
  if declare -F _dots_bash_history_sync >/dev/null 2>&1; then
    _dots_bash_history_sync
  else
    history -a
    history -n
  fi

  local git_info pwd_file_count pwd_file_size
  git_info="$(render_git_info)"

  if [ "${DOTS_PROMPT_STATS:-0}" = "1" ]; then
    pwd_file_count="$(file_count)"
    pwd_file_size="$(file_size)"
  else
    pwd_file_count="·"
    pwd_file_size=""
  fi

  local LINE_1 LINE_2 LINE_3 LINE_4 LINE_5
  LINE_1="\[\n${NC}\]┌──┤\[${GREEN}\]\u\[${NC}\]@\[${BLUE}\]\h\[${NC}\]├─┤\[${BPURP}\]"
  LINE_2="\@\[${NC}\]├─┤\[${CYAN}\]\d\[${NC}\]├${git_info}${NC}\]│\n"
  LINE_3="├───┤jobs \[${CYAN}\](\j)\[${NC}\]├─┤${DGRAY}${pwd_file_count}⌂"
  LINE_4="${pwd_file_size}\[${NC}\]│\n"
  LINE_5="└─┤\[${YELLOW}\]\w\[${NC}\]│ "
  PS1="${LINE_1}${LINE_2}${LINE_3}${LINE_4}${LINE_5}"
}

# Compose PROMPT_COMMAND carefully (single assignment)
PROMPT_COMMAND=render_prompt_command
export PROMPT_COMMAND
