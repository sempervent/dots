# Native Zsh prompt inspired by the classic Bash box-drawing prompt.
# Uses precmd + prompt expansion (NOT Bash PROMPT_COMMAND).
#
# Shows: user@host, time, date, git branch/remote, jobs, cwd
# Optional file count / size via DOTS_PROMPT_STATS=1 (default off for speed).

autoload -Uz colors && colors

# Lightweight git info — prefer vcs_info, fall back to git commands
autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats '%b'
zstyle ':vcs_info:git:*' actionformats '%b|%a'
zstyle ':vcs_info:git:*' check-for-changes false

_dots_zsh_git_segment() {
  local branch remote
  branch="${vcs_info_msg_0_:-}"
  if [[ -z "${branch}" ]]; then
    echo "─"
    return
  fi
  remote="$(git for-each-ref --format='%(upstream:short)' "$(git symbolic-ref -q HEAD 2>/dev/null)" 2>/dev/null)"
  if [[ -n "${remote}" ]]; then
    echo "─┤%F{yellow}${remote}->${branch}%f├─"
  else
    echo "─┤%F{yellow}${branch}%f├─"
  fi
}

_dots_zsh_stats_segment() {
  if [[ "${DOTS_PROMPT_STATS:-0}" != "1" ]]; then
    echo "·"
    return
  fi
  local count size
  count="$(command ls -1 2>/dev/null | wc -l | tr -d '[:space:]')"
  size="$(command ls -lah 2>/dev/null | awk '/^total/ {print $2; exit}')"
  echo "${count}⌂${size}"
}

_dots_zsh_precmd() {
  vcs_info
  local git_seg stats_seg
  git_seg="$(_dots_zsh_git_segment)"
  stats_seg="$(_dots_zsh_stats_segment)"

  PROMPT=$'\n'"%F{default}┌──┤%F{green}%n%f@%F{blue}%m%f├─┤%F{magenta}%*%f├─┤%F{cyan}%D{%a %b %d}%f├${git_seg}│"$'\n'
  PROMPT+="├───┤jobs %F{cyan}(%j)%f├─┤%F{white}${stats_seg}%f│"$'\n'
  PROMPT+="└─┤%F{yellow}%~%f│ "
  RPROMPT=""
}

# Register precmd hook without clobbering others
autoload -Uz add-zsh-hook
add-zsh-hook precmd _dots_zsh_precmd
