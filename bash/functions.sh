#!/usr/bin/env bash
# smart extract an archive file {{{1
extract() {
  if [ -f $1 ]; then
    case $1 in
      *.tar.bz2)  tar xvjf $1   ;;
      *.tar.gz)   tar xzvf $1   ;;
      *.bz2)      bunzip2 $1    ;;
      *.rar)      rar x $1      ;;
      *.gz)       gunzip $1     ;;
      *.tar)      tar xvf $1    ;;
      *.tbz2)     tar xvjf $1   ;;
      *.tgz)      tar xzvf $1   ;;
      *.zip)      unzip $1      ;;
      *.Z)        uncompress $1 ;;
      *.7z)       7z x $1       ;;
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
    echo 'cdmkdir requires one argument'
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
# create a bash skeleton script {{{1
make_bash_script() {
	wget -O "$1" https://gist.githubusercontent.com/sempervent/4d94593e0d56f8fc1b43f92b9983d61f/raw/dfaed9bc4b9dc4f007f8b22072ec92eb94de7004/bash_skeleton.sh
}
# 1}}}
