#!/usr/bin/env bash
# file information of directory {{{1
file_count() { # 2{{{
  ls -1 | wc -l | sed 's: ::g'
} # 2}}}
file_size() { #{{{2
  ls -lah | grep -m 1 total | sed 's/total //'
} # 2}}}
# 1}}}
# smart extract an archive file {{{1
extract() {
  if [ -f "$1" ]; then
    case $1 in
      *.tar.bz2)  tar xvjf "$1"   ;;
      *.tar.gz)   tar xzvf "$1"   ;;
      *.bz2)      bunzip2 "$1"    ;;
      *.rar)      rar x "$1"      ;;
      *.gz)       gunzip "$1"     ;;
      *.tar)      tar xvf "$1"    ;;
      *.tbz2)     tar xvjf "$1"   ;;
      *.tgz)      tar xzvf "$1"   ;;
      *.zip)      unzip "$1"      ;;
      *.Z)        uncompress "$1" ;;
      *.7z)       7z x "$1"       ;;
      *)          echo "don't know how to extract '$1' ..." ;;
    esac
  else
    echo "'$1' is not a valid file."
  fi
} # 1}}}
# make and then cd into directory {{{1
cdmkdir() {
  if [ $# -eq 1 ]; then
    mkdir -p -v "$1" && cd "$1" || return
  else
    echo 'cdmkdir requires one argument for the new directory to create'
  fi
} # 1}}}
# check to see all colors are available {{{1
showcolors() {
  for x in 0 1 4 5 7 8; do
    for i in $(seq 30 37); do
      for a in $(seq 40 47); do
        echo -ne "\e[$x;$i;$a""m\\\e[$x;$i;$a""m\e[0;37;40m "
      done
      echo
    done
  done
  echo ""
} # 1}}}
# change up a variable number of directories {{{1
cu() {
  local count=$1
  if [ -z "${count}" ]; then
    count=1
  fi
  local path=""
  for i in $(seq 1 ${count}); do
    path="${path}../"
  done
  cd $path || return
} # 1}}}
# date functions {{{1
# print today in ISO-8061 {{{2
today() {
  DTFORMAT="+%F"
  while :; do
    case "$1" in
      --help|-h|-\?|\?)
        echo "Options:"
        echo -e "\t-f,--format    the format to pass to date"
        echo -e "\t-h,--help,-?,? display this help"
        shift ;;
      -f|--format)
        DTFORMAT="$2"
        shift 2 ;;
      *) break ;;
    esac
  done
  date "$DTFORMAT"
} # 2}}}
# print now in ISO-8061 {{{2
now() {
  if [ -z "$1" ]; then
    DTFORMAT="+%FT%H:%M:%SZ%Z"
  else
    DTFORMAT="$1"
  fi
  today -f"$DTFORMAT"
} # 2}}}
# go back n number of days {{{2
past_today() {  
  if [ -n "$1" ]; then
    date --date="$(date) - $1 day" +%Y-%m-%d
  else
    date --date="$(date) - 1 day" +%Y-%m-%d
  fi
} # 2}}}
day-from-now() { # go forward n/1 number of days {{{2
  if [ -n "$1" ]; then
    date --date="$(date) + $1 day" +%F
  else
    date --date="$(date) + 1 day" +%F
  fi
} # 2}}}
# 1}}}
# Docker-related commands {{{1
# run and execute into a docker image while mounting a directory {{{2
# defaults to present working directory. Params are documented in code. 
dre() {  
  IMAGE="python:latest"
  VOLUME="-v $(pwd):/tmp/"
  COMMAND="bash"
  while :; do # {{{3
    case $1 in 
      --help|-h|-\?) # {{{4
        echo "Usage is: "
        echo "    dre -i|--image <image> -v <volume>| -e|--exec <command>"
        echo " Where options are:"
        echo "      (-v|--volume '<host dir>:<container dir>')"
        echo "      (-e|--exec 'command')"
        echo ""
        echo "Defaults are: "
        echo '   image: "python:latest"'
        echo "   volume: \"$(pwd):/tmp/\""
        echo '   command: "bash"'
        exit
        ;; # 4}}}
      -i|--image) # {{{4
        IMAGE="$2"
        shift 2
        ;; # 3}}}
      -v|--volume) # {{{4
        VOLUME="-v $2"
        shift 2
        ;; # 3}}}
      -e|--exec) # {{{4
        COMMAND="$2"
        shift 2
        ;; # 4}}}
      esac
    done # 2}}}
  docker run -it "$VOLUME" "$IMAGE" "$COMMAND"
} # 2}}}
# 1}}}
# gists pull downs {{{1
# pull down and edit the bash skeleton into a file {{{2
make_bash_script() {
  SKELETON_URL=${BASH_SKELETON_URL:-"https://gist.github.com/sempervent/4d94593e0d56f8fc1b43f92b9983d61f/raw/6e87ec5a849b0371c37e27f77d4d52296633309d/bash_skeleton.sh"}
  wget -O "$1" "$SKELETON_URL"
  chmod +x "$1"
  vim "$1"
} # 2}}}
# 1}}}
# Git function helpers {{{1
# git add and commit one-liner  {{{2
gac() {
  if [[ "$#" -lt "1" ]]; then
    echo -e "git-add-commit asserts 2 values, file to add & git commit msg"
    exit 1
  fi
  git diff --color=always "$1" | less -r
  while true; do
    read -p "Proceed with the add and commit? " yn
    case $yn in
      y*) break;;
      n*) return;;
      * ) echo "please answer yes or no.";;
    esac
  done
  git add "$1"
  if [[ -n "$2" ]]; then
    git commit -m "$2"
  else
    echo -e "Please enter a ${YELLOW}commit message${NC}:"
    read -p "" commit_message
    git commit -m "$commit_message"
  fi
} # 2}}}
# stuff to get git info {{{2
parse_git_branch() { # {{{3
  git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'
} # 3}}}
parse_git_remote() { # {{{3
  git for-each-ref --format='%(upstream:short)' $(git symbolic-ref --q HEAD 2> /dev/null) 2> /dev/null
} # 3}}}
render_git_info() { # {{{3
  branch=$(parse_git_branch)
  if [ "$branch" ]; then
    echo "─┤${LYEL}$(parse_git_remote)->$(parse_git_branch)├─"
  else
    echo "─"
  fi
} # 3}}}
# 2}}}
# git manipulation commands
verify_and_checkout() { # verify if a branch exists and checkout and pull {{{3
  if git rev-parse --verify "$1" > /dev/null 2>&1; then
    git checkout "$1" && git pull
  else
    exit 1
  fi
} # 3}}}
checkout_main_or_master() {  # perform a git release {{{3
  verify_and_checkout main || verify_and_checkout master
} # 3}}}
release() {  # make a release commit {{{3
  checkout_main_or_master || echo "main or master not available" && exit 1
  git checkout -b "Deploy_$(today)"
} # 3}}}
git_checkpoint() {  # make a random checkpoint
  git add .
  commit_msg="adding all, .gitignore should have blocked unnecessary files"
  commit_msg="$commit_msg on $(date +%F): "
  commit_msg="$commit_msg $(fortune | sed 's/(\s{2,}|\n)/ /g')"
  git commit -m "$(commit_msg)"
  git push
}
# 2}}}
# 1}}}
# prompt command {{{1
render_prompt_command() {
  history -a
  history -c
  history -r
  git_info="$(render_git_info)"
  pwd_file_count="$(file_count)"
  pwd_file_size="$(file_size)"
  LINE_1="\[\n$NC\]┌──┤\[$GREEN\]\u\[$NC\]@\[$BLUE\]\h\[$NC\]├─┤\[$BPURP\]"
  LINE_2="\@\[$NC\]├─┤\[$CYAN\]\d\[$NC\]├${git_info}$NC\]│\n"
  LINE_3="├───┤jobs \[$CYAN\](\j)\[$NC\]├─┤${DGRAY}${pwd_file_count}⌂"
  LINE_4="$pwd_file_size\[$NC\]│\n"
  LINE_5="└─┤\[$YELLOW\]\w\[$NC\]│ "
  PS1="${LINE_1}${LINE_2}${LINE_3}${LINE_4}${LINE_5}"
}
# 1}}}
# grab gists quickly  # {{{2
make_pyinit() { # {{{1
  wget https://gist.githubusercontent.com/sempervent/784b6285cc8a8a79b9924a6595787316/raw/d6beed2cc4f16b883a2d1d08cfc6c7a86ca8d8dc/__init__.py
} # 3}}} 2}}}
# whatthecommit {{{2
whatthecommit() {
  curl --silent --fail http://whatthecommit.com/index.txt
} # 2}}}
# quickly make a python module {{{1
mk_pymodule() {
  if [ $# -eq 1 ]; then
    #PREVIOUS_DIR="$PWD"
    mkdir -p -v "$1" && cd "$1" || return
    make_pyinit || touch __init__.py
    #cd "$PREVIOUS_DIR" || return
  else
    echo "must specify a directory"
  fi
} # 1}}}
# web-related {{{1
open-url() { # open a webpage {{2
  if [ "$OS" = "Mac" ]; then
    open "$1"
  elif [ "$OS" = "Nix" ]; then
    if [ -x "$(which xdg-open)" ]; then
      xdg-open "$1"
    fi
  fi
} # 2}}}
websearch() { # google a query {{{2
  if [ -z "$SEARCH_ENGINE" ]; then
    SEARCH_ENGINE="https://google.com/search?q="
  fi
  terms="$@"
  query="${SEARCH_ENGINE}$(echo "$terms" | tr ' ' '+')"
  if [ -x "$(which w3m)" ]; then
    w3m "$query"
  else
    open-url "$query"
  fi
} # 2}}}
# 1}}
# system functions {{{1
whatdistro() {
  if [ "$OS" = "Mac" ]; then
    distro=$(awk '/SOFTWARE LICENSE AGREEMENT FOR macOS/' '/System/Library/CoreServices/Setup Assistant.app/Contents/Resources/en.lproj/OSXSoftwareLicense.rtf' | awk -F 'macOS ' '{print $NF}' | awk '{print substr($0, 0, length($0)-1)}')
  elif [ -f /etc/os-release ]; then
    distro=$(cat /etc/os-release | grep -oP "(?<=^PRETTY_NAME\=\").*(?=\")")
  else
    distro=$(lsb_release -a | grep "Description" | awk -F: '{print $2}' | \
      sed -e 's/^[ \t]*//' -e 's/[ \t]*$'
  )
  fi
  echo "$distro"
}
# 1}}}
pipe-fortune(){ # make pipe fortune {{{1
  echo "$(fortune | sed 's/\n/ /g' | sed 's/\s+/ /g')"
} # 1}}}

# DOCKER related functions: {{{1
get_docker_swap_usage() {
  if [[ -n "$(command -v docker)" ]]; then
      # Get the container ID(s) from the container name or ID.
      container_ids=$(docker ps -q)
      for container_id in $container_ids; do
          container_name=$(docker inspect --format='{{.Name}}' "$container_id")
          swap_usage=$(docker inspect --format='{{.State.Pid}}' "$container_id" | xargs -I{} sh -c 'awk "/Swap/{ sum += \$2 } END { print sum }" /proc/{}/smaps 2>/dev/null')
          echo "Container ID: $container_id, Container Name: $container_name, Swap usage: $swap_usage bytes"
      done
  else
      echo "Docker is not installed. Cannot check container swap usage."
  fi
}
list_docker_images() {
  docker images  --format "table {{.Repository}}:{{.Tag}} {{.Size}}"
}
# 1}}
convert_bytes_to_human() {
  local bytes=$1
  if [[ $bytes -lt 1024 ]]; then
      echo "${bytes}B"
  elif [[ $bytes -lt 1048576 ]]; then
      echo "$(bc <<< "scale=2; $bytes/1024")K"
  elif [[ $bytes -lt 1073741824 ]]; then
      echo "$(bc <<< "scale=2; $bytes/1048576")M"
  elif [[ $bytes -lt 1099511627776 ]]; then
      echo "$(bc <<< "scale=2; $bytes/1073741824")G"
  else
      echo "$(bc <<< "scale=2; $bytes/1099511627776")T"
  fi
}

show_nas_storage_size() {
  output=$(df -Pk | grep '^//')
  # Summing the values and using bc for arithmetic to avoid overflow
  total_size=$(echo "$output" | awk '{print $2}' | paste -sd+ - | bc)
  total_size=$((total_size * 1024))  # Convert from KB to Bytes
  total_used=$(echo "$output" | awk '{print $3}' | paste -sd+ - | bc)
  total_used=$((total_used * 1024))
  total_avail=$(echo "$output" | awk '{print $4}' | paste -sd+ - | bc)
  total_avail=$((total_avail * 1024))
  echo "Total Size: $(convert_bytes_to_human "$total_size")"
  echo "Total Used: $(convert_bytes_to_human "$total_used")"
  echo "Total Available: $(convert_bytes_to_human "$total_avail")"
}
