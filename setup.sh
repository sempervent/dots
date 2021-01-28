#!/usr/bin/env bash
# environment {{{1 ------------------------------------------------------------
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null 2>&1 && pwd )"
SYM_DIR=$DIR/syms
OLD_DOTS=~/old_dots
VUNDLE_DIR=~/.vim/bundle/Vundle.vim
# 1}}} ------------------------------------------------------------------------
# file array {{{1 -------------------------------------------------------------
# accept an environmental variable as a list
if [[ "$FILE_ARRAY" == "" ]]; then
	declare -a FILE_ARRAY=('bashrc' 'vimrc' 'tmux.conf' 'sqliterc')
fi
# 1}}} ------------------------------------------------------------------------
# ensure the $OLD_DOTS folder exists {{{1 -------------------------------------
if [ ! -d "$OLD_DOTS" ]; then
  mkdir -p $OLD_DOTS
#else
#	echo -e "$OLD_DOTS directory exists. . . exiting"
#	exit 1
fi
# 1}}} ------------------------------------------------------------------------
move_sym() { # {{{1 -----------------------------------------------------------
  if [ "$#" -ne 2 ]; then
    echo "move_sym expects two arguments:"
    printf "\t%s\n\t%s\n" "source" "destination"
    exit 1
  else
    _SOURCE="$SYM_DIR/$1"
    _DEST="$2"
    _BACKUP="$OLD_DOTS/$1"
  fi
  if [ -f "$_DEST" ]; then
    echo -e "moving \\e[33m$_DEST\\e[39m to \\e[32m$_BACKUP\\e[39m"
    mv "$_DEST" "$_BACKUP"
  fi
  if [ ! -f "$_DEST" ] && [ -f "$_SOURCE" ]; then
     ln -s "$_SOURCE" "$_DEST"
  else
     echo 'unknown error'
     exit 1
  fi
} # 1}}} ----------------------------------------------------------------------
# iterate over the array and execute move_symn {{{1 ---------------------------
for i in "${FILE_ARRAY[@]}"; do
	echo "$i"
	move_sym "$i" "$HOME/.$i"
done
# 1}}} ------------------------------------------------------------------------
# install vundle into its directory unless it is already installed {{{1 -------
if [ ! -d "$VUNDLE_DIR" ]; then
  git clone https://github.com/gmarik/Vundle.vim.git $VUNDLE_DIR
	vim +BundleInstall
fi
# 1}}} ------------------------------------------------------------------------
# install tmux tpm {{{1 -------------------------------------------------------
git clone https://gkithub.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
# have secrets
mkdir - p "$DIR/secrets"
