#!/usr/bin/env bash
# environment {{{1 ------------------------------------------------------------
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null 2>&1 && pwd )"
SYM_DIR="$DIR/syms"
OLD_DOTS="$HOME/.old_dots"
VUNDLE_DIR="$HOME/.vim/bundle/Vundle.vim"
TMUX_PLUGIN_DIR="$HOME/.tmux/plugins/tpm"
# 1}}} ------------------------------------------------------------------------
# file array {{{1 -------------------------------------------------------------
# accept an environmental variable as a list
if [[ "$FILE_ARRAY" == "" ]]; then
	declare -a FILE_ARRAY=('bashrc' 'vimrc' 'tmux.conf' 'sqliterc' 'psqlrc')
fi
# 1}}} ------------------------------------------------------------------------
# ensure the $OLD_DOTS folder exists {{{1 -------------------------------------
if [ ! -d "$OLD_DOTS" ]; then
  mkdir -p "$OLD_DOTS"
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
    _BACKUP="$OLD_DOTS/$1_$(date +%F)"
  fi
  if [ -f "$_DEST" ]; then
    echo -e "moving \\e[33m$_DEST\\e[39m to \\e[32m$_BACKUP\\e[39m"
    mv "$_DEST" "$_BACKUP"
  fi
  if [ ! -f "$_DEST" ] && [ -f "$_SOURCE" ]; then
     ln -s "$_SOURCE" "$_DEST"
  else
     echo 'unknown error'
     echo "\\e[32mSource\\e[39m:  $_SOURCE"
     echo "\\e[33mDesitnation\\e[39m:  $_DEST"
     echo "\\e[32mBackup:\\39m:  $_BACKUP"
     exit 1
  fi
} # 1}}} ----------------------------------------------------------------------
# iterate over the array and execute move_symn {{{1 ---------------------------
for i in "${FILE_ARRAY[@]}"; do
	echo "Symlinking $i to $HOME/.$i"
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
git clone https://github.com/tmux-plugins/tpm "$TMUX_PLUGIN_DIR"
# have secrets
export SECRETS_DIR="${SECRETS_DIR:"$DIR/.secrets"}"
mkdir -p "$SECRETS_DIR"
# git settings
source "${DIR}/helpers/git_alias_setup.sh"
echo "Finished installing dots!"
