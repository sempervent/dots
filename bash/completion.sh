#!/usr/bin/env bash
mac_git_prompt="/usr/local/opt/bash-git-prompt/share/gitprompt.sh"
nix_git_prompt="/etc/bash_completion.d/git-prompt"

source_if_exists() {
	if [ -f "$1" ]; then
		source "$1"
	fi
} 

if [ -f "$mac_git_prompt" ]; then
	__GIT_PROMPT_DIR="/usr/local/opt/bash-git-prompt/share"
fi

source_if_exists "$nix_git_prompt"
source_if_exists "$mac_git_prompt"
