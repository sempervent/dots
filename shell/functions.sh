# shellcheck shell=bash
# Shared functions (Bash + Zsh compatible where possible)
# Keep custom extract(); do not enable a colliding OMZ extract plugin.

# Directory stats (used by prompts; can be expensive) {{{1
file_count() {
  command ls -1 2>/dev/null | wc -l | tr -d '[:space:]'
}

file_size() {
  local size
  size="$(command ls -lah 2>/dev/null | awk '/^total/ {print $2; exit}')"
  echo "${size:-0}"
}
# 1}}}

# Archive Swiss-army knife {{{1
extract() {
  if [ -f "$1" ]; then
    case "$1" in
      *.tar.bz2) tar xvjf "$1" ;;
      *.tar.gz)  tar xzvf "$1" ;;
      *.bz2)     bunzip2 "$1" ;;
      *.rar)     unrar x "$1" 2>/dev/null || rar x "$1" 2>/dev/null || echo "unrar/rar not installed" ;;
      *.gz)      gunzip "$1" ;;
      *.tar)     tar xvf "$1" ;;
      *.tbz2)    tar xvjf "$1" ;;
      *.tgz)     tar xzvf "$1" ;;
      *.zip)     unzip "$1" ;;
      *.Z)       uncompress "$1" ;;
      *.7z)      7z x "$1" 2>/dev/null || echo "7z not installed" ;;
      *)         echo "don't know how to extract '$1' ..." ;;
    esac
  else
    echo "'$1' is not a valid file."
  fi
}
# 1}}}

# Navigation helpers {{{1
cdmkdir() {
  if [ $# -eq 1 ]; then
    mkdir -p -v "$1" && cd "$1" || return
  else
    echo 'cdmkdir requires one argument for the new directory to create'
  fi
}

# Alias-style name used in some zsh configs
mkcd() {
  cdmkdir "$@"
}

cu() {
  local count="${1:-1}"
  local path=""
  local i
  # shellcheck disable=SC2034
  for i in $(seq 1 "${count}"); do
    path="${path}../"
  done
  cd "${path}" || return
}
# 1}}}

# Date helpers {{{1
today() {
  local DTFORMAT="+%F"
  while :; do
    case "${1:-}" in
      --help|-h|-\?|\?)
        echo "Options:"
        echo "  -f,--format    format passed to date"
        echo "  -h,--help      display this help"
        return 0
        ;;
      -f|--format)
        DTFORMAT="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done
  date "${DTFORMAT}"
}

now() {
  local DTFORMAT="${1:-+%FT%H:%M:%SZ%Z}"
  today -f "${DTFORMAT}"
}

past_today() {
  local days="${1:-1}"
  if date -v-"${days}"d +%Y-%m-%d >/dev/null 2>&1; then
    date -v-"${days}"d +%Y-%m-%d
  else
    date --date="$(date) - ${days} day" +%Y-%m-%d
  fi
}

day-from-now() {
  local days="${1:-1}"
  if date -v+"${days}"d +%F >/dev/null 2>&1; then
    date -v+"${days}"d +%F
  else
    date --date="$(date) + ${days} day" +%F
  fi
}
# 1}}}

# Docker helpers — prefer `docker compose`, fall back to `docker-compose` {{{1
_dots_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "Error: neither 'docker compose' nor 'docker-compose' found" >&2
    return 1
  fi
}

dco() {
  _dots_compose "$@"
}

dcud() {
  _dots_compose down && _dots_compose up -d "$@"
}

dre() {
  local IMAGE="python:latest"
  local VOLUME="-v $(pwd):/tmp/"
  local COMMAND="bash"
  while :; do
    case "${1:-}" in
      --help|-h|-\?)
        echo "Usage: dre [-i image] [-v host:container] [-e command]"
        echo "Defaults: image=python:latest volume=\$(pwd):/tmp/ command=bash"
        return 0
        ;;
      -i|--image)
        IMAGE="$2"
        shift 2
        ;;
      -v|--volume)
        VOLUME="-v $2"
        shift 2
        ;;
      -e|--exec)
        COMMAND="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done
  # shellcheck disable=SC2086
  docker run -it ${VOLUME} "${IMAGE}" "${COMMAND}"
}
# 1}}}

# Git helpers {{{1
parse_git_branch() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local ref
  ref="$(git symbolic-ref -q --short HEAD 2>/dev/null)" || true
  if [ -n "${ref}" ]; then
    printf '%s\n' "${ref}"
    return 0
  fi
  # Detached HEAD
  ref="$(git rev-parse --short HEAD 2>/dev/null)" || true
  [ -n "${ref}" ] && printf 'detached@%s\n' "${ref}"
}

parse_git_remote() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local head_ref
  head_ref="$(git symbolic-ref -q HEAD 2>/dev/null)" || return 0
  git for-each-ref --format='%(upstream:short)' "${head_ref}" 2>/dev/null
}

# Primary relation string: upstream->branch | branch | detached@abc1234 | empty
dots_git_relation() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local branch remote
  branch="$(parse_git_branch)"
  [ -z "${branch}" ] && return 0
  case "${branch}" in
    detached@*) printf '%s\n' "${branch}"; return 0 ;;
  esac
  remote="$(parse_git_remote)"
  if [ -n "${remote}" ]; then
    printf '%s->%s\n' "${remote}" "${branch}"
  else
    printf '%s\n' "${branch}"
  fi
}

# Compact secondary marks: ! dirty, ↑N ahead, ↓N behind (relation stays primary)
dots_git_state_marks() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local dirty="" ahead=0 behind=0 marks="" line
  # Single porcelain call for dirty + ahead/behind
  while IFS= read -r line; do
    case "${line}" in
    '## '*)
      case "${line}" in
      *ahead\ [0-9]*)
        ahead="${line#*ahead }"
        ahead="${ahead%%,*}"
        ahead="${ahead%%\]*}"
        ;;
      esac
      case "${line}" in
      *behind\ [0-9]*)
        behind="${line#*behind }"
        behind="${behind%%,*}"
        behind="${behind%%\]*}"
        ;;
      esac
      ;;
    *)
      [ -n "${line}" ] && dirty="!"
      ;;
    esac
  done < <(git status --porcelain=v1 -b 2>/dev/null || true)
  marks="${dirty}"
  [ "${ahead:-0}" -gt 0 ] 2>/dev/null && marks="${marks}↑${ahead}"
  [ "${behind:-0}" -gt 0 ] 2>/dev/null && marks="${marks}↓${behind}"
  printf '%s\n' "${marks}"
}

gac() {
  if [ $# -lt 1 ]; then
    echo "Usage: gac <file> [commit message]"
    return 1
  fi
  git diff --color=always "$1" | less -R
  printf "Proceed with the add and commit? "
  # Portable prompt (avoid bash-only `read -p`)
  # shellcheck disable=SC2162
  read yn
  case "${yn}" in
    y*|Y*) ;;
    *) return 0 ;;
  esac
  git add "$1"
  if [ -n "${2:-}" ]; then
    git commit -m "$2"
  else
    printf "Commit message: "
    # shellcheck disable=SC2162
    read commit_message
    git commit -m "${commit_message}"
  fi
}

verify_and_checkout() {
  if git rev-parse --verify "$1" >/dev/null 2>&1; then
    git checkout "$1" && git pull
  else
    return 1
  fi
}

checkout_main_or_master() {
  verify_and_checkout main || verify_and_checkout master
}

release() {
  checkout_main_or_master || {
    echo "main or master not available"
    return 1
  }
  git checkout -b "Deploy_$(today)"
}

git_checkpoint() {
  git add .
  local commit_msg
  commit_msg="checkpoint $(date +%F)"
  if command -v fortune >/dev/null 2>&1; then
    commit_msg="${commit_msg}: $(fortune | tr '\n' ' ' | sed 's/  */ /g')"
  fi
  git commit -m "${commit_msg}"
  git push
}

whatthecommit() {
  curl --silent --fail http://whatthecommit.com/index.txt
}
# 1}}}

# System {{{1
whatdistro() {
  if [ "$(uname -s)" = "Darwin" ]; then
    if [ -f '/System/Library/CoreServices/Setup Assistant.app/Contents/Resources/en.lproj/OSXSoftwareLicense.rtf' ]; then
      awk '/SOFTWARE LICENSE AGREEMENT FOR macOS/' '/System/Library/CoreServices/Setup Assistant.app/Contents/Resources/en.lproj/OSXSoftwareLicense.rtf' \
        | awk -F 'macOS ' '{print $NF}' \
        | awk '{print substr($0, 0, length($0)-1)}'
    else
      sw_vers -productName
    fi
  elif [ -f /etc/os-release ]; then
    # Prefer PRETTY_NAME without requiring GNU grep -P
    awk -F= '/^PRETTY_NAME=/ {gsub(/"/, "", $2); print $2; exit}' /etc/os-release
  elif command -v lsb_release >/dev/null 2>&1; then
    lsb_release -d | cut -f2
  else
    echo "Unknown"
  fi
}

showcolors() {
  local x i a
  for x in 0 1 4 5 7 8; do
    for i in $(seq 30 37); do
      for a in $(seq 40 47); do
        printf "\e[%s;%s;%sm\\\\e[%s;%s;%sm\e[0m " "$x" "$i" "$a" "$x" "$i" "$a"
      done
      echo
    done
  done
  echo
}
# 1}}}

# Web {{{1
open-url() {
  local url="$1"
  if [ "$(uname -s)" = "Darwin" ]; then
    open "${url}"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "${url}"
  else
    echo "Cannot open URL: ${url}"
  fi
}

websearch() {
  local SEARCH_ENGINE="${SEARCH_ENGINE:-https://google.com/search?q=}"
  local terms="$*"
  local query="${SEARCH_ENGINE}$(echo "${terms}" | tr ' ' '+')"
  if command -v w3m >/dev/null 2>&1; then
    w3m "${query}"
  else
    open-url "${query}"
  fi
}
# 1}}}

pipe-fortune() {
  if command -v fortune >/dev/null 2>&1; then
    fortune | tr '\n' ' ' | sed 's/  */ /g'
  else
    echo "Fortune not installed"
  fi
}

# Scaffolding {{{1
make_bash_script() {
  local SKELETON_URL="${BASH_SKELETON_URL:-https://gist.github.com/sempervent/4d94593e0d56f8fc1b43f92b9983d61f/raw/6e87ec5a849b0371c37e27f77d4d52296633309d/bash_skeleton.sh}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$1" "${SKELETON_URL}"
  else
    wget -O "$1" "${SKELETON_URL}"
  fi
  chmod +x "$1"
  "${EDITOR:-vim}" "$1"
}

make_pyinit() {
  local url="https://gist.githubusercontent.com/sempervent/784b6285cc8a8a79b9924a6595787316/raw/d6beed2cc4f16b883a2d1d08cfc6c7a86ca8d8dc/__init__.py"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -O "${url}"
  else
    wget "${url}"
  fi
}

mk_pymodule() {
  if [ $# -eq 1 ]; then
    mkdir -p -v "$1" && cd "$1" || return
    make_pyinit || touch __init__.py
  else
    echo "must specify a directory"
  fi
}
# 1}}}

# JSON / YAML helpers (do not shadow jq/yq) {{{1
jq-pretty() {
  if [ $# -eq 0 ]; then
    jq '.' </dev/stdin
  else
    jq '.' "$1"
  fi
}

yq-pretty() {
  if [ $# -eq 0 ]; then
    yq eval '.' </dev/stdin
  else
    yq eval '.' "$1"
  fi
}
# 1}}}

# Clipboard helpers (macOS pbcopy/pbpaste, Linux xclip/wl-copy) {{{1
clipcopy() {
  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy
  elif command -v wl-copy >/dev/null 2>&1; then
    wl-copy
  elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard
  else
    echo "No clipboard helper found" >&2
    return 1
  fi
}

clippaste() {
  if command -v pbpaste >/dev/null 2>&1; then
    pbpaste
  elif command -v wl-paste >/dev/null 2>&1; then
    wl-paste
  elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard -o
  else
    echo "No clipboard helper found" >&2
    return 1
  fi
}
# 1}}}
