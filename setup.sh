#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null 2>&1 && pwd )"
SYM_DIR=$DIR/syms
OLD_DOTS=~/old_dots
VUNDLE_DIR=~/.vim/bundle/Vundle.vim

if [ ! -d "$OLD_DOTS" ]; then
  mkdir -p $OLD_DOTS
fi

move_sym() {
  if [ "$#" -ne 2 ]; then
    echo "move_sym expects two arguments:"
    echo "\tsource"
    echo "\tdestination"
    exit 1
  fi
  if [ -f "$2" ]; then
    mv $2 $OLD_DOTS/
    ln -s $1 $2
  fi
}

move_sym $SYM_DIR/bashrc ~/.bashrc
move_sym $SYM_DIR/vimrc ~/.vimrc
move_sym $SYM_DIR/tmux.conf ~/.tmux.conf

# install vundle into its directory unless it is already installed
if [ ! -d "$VUNDLE_DIR" ]; then
  git clone https://github.com/gmarik/Vundle.vim.git $VUNDLE_DIR
fi
