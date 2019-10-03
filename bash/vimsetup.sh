#!/usr/bin/env bash
# check to make sure git is installed
if [ -x "$(command -v git)" ]; then
	echo "Error: git is not installed." >&2
	exit 1
fi

mkdir -p ~/.vim/bundle
mkdir -p ~/.vim/colors

git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim

if [ -x "$(command -v wget)" ]; then
	echo "Error: wget must be installed to install colors." >&2
fi

wget --directory-prefix=~/.vim/colors https://raw.githubusercontent.com/tomasr/molokai/master/colors/molokai.vim

if [ -x "$(command -v vim)" ]; then
	echo "Error: vim must be installed to install vim plugins." >&2
	exit 1
fi

vim +PluginInstall +qall
