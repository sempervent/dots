#!/usr/bin/env bash
# -*- coding: utf-8 -*-
git config --global push.autoSetupRemote true
git config --global pull.rebase true
git config --global alias.prurl '!f(){ echo \"https://github.com/$(git remote -v | grep origin | awk \''{print $2}\'' | awk -F: \''{print $2}\'' | awk -F. \''{print $1}\'' | head -n 1)/pull/new/$(git symbolic-ref --short HEAD)\"; }; f;'
git config --global alias.release '!git checkout main && git pull && git checkout -b Deploy_$(date +%F)'
# shellcheck disable=SC2016
if [ -x "$(which fortune)" ]; then
  git config --global alias.fortune '!git commit -m \"$(fortune)\"'
fi
git config --global alias.print_branch '!git symbolic-ref --short HEAD'
git config --global alias.print_repo "!git remote -v | grep origin | awk '{print $2}' | awk -F: '{print $2}' | awk -F. '{print $1}' | head -n 1"
git config --global alias.prurl '! echo "https://github.com/$(git print_remote)/pull/new/$(git print_branch)"'

