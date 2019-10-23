#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null 2>&1 && pwd )"
SYM_DIR=$DIR/syms
OLD_DOTS=~/old_dots

move_sym() {
	if [ "$#" -ne 2 ]; then
		echo "move_sym expects two arguments:"
		echo "\tsource"
		echo "\tdestination"
		exit 1
	fi
	if [ -f "$2" ]; then
		if [ ! -d "$OLD_DOTS" ]; then
			mkdir -p $OLD_DOTS
		fi
		mv $2 $OLD_DOTS/
		ln -s $1 $2
	fi
}

move_sym $SYM_DIR/bashrc ~/.bashrc
move_sym $SYM_DIR/vimrc ~/.vimrc
move_sym $SYM_DIR/tmux.conf ~/.tmux.conf

git clone https://github.com/gmarik/Vundle.vim.git ~/.vim/bundle/Vundle.vim
