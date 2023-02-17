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
  DTFORMAT="+%FT%H:%M:%SZ%Z"
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
# go back n number of days {{{2
past_today() {  
  date --date="$(date) - $1 day" +%Y-%m-%d
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
  docker run -it "$IMAGE" "$COMMAND"
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
    PREVIOUS_DIR="$PWD"
    mkdir -p -v "$1" && cd "$1" || return
    make_pylint || touch __init__.py
    cd "$PREVIOUS_DIR" || return
  else
    echo "must specify a directory"
  fi
} # 1}}}
