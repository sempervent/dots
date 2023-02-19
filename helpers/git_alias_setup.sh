#!/usr/bin/env bash
# -*- coding: utf-8 -*-
git config --global push.autoSetupRemote true
git config --global pull.rebase true
git config --global alias.release '!git checkout main && git pull && git checkout -b Deploy_$(date +%F)'
# shellcheck disable=SC2016
if [ -x "$(which fortune)" ]; then
  git config --global alias.fortune '!git commit -m \"$(fortune)\"'
fi
gitpr() {
  PREFIX="release/"
  DATEFMT="%F"
  while :; do
    case $1 in
      -p|--prefix)
        PREFIX="$2"
        shift 2
        ;;
      -d|--datefmt)
        DATEFMT="$2"
        shift 2
        ;;
      release)
        main="$(git branch --list | grep -oP '(master|main)')"
        git checkout "$main" || exit
        git pull
        git checkout -b "${PREFIX}$(date +"${DATEFMT}")"
        shift
        ;;
      url)
        branch="$(git symbolic-ref --short HEAD)"
        url="$(git remote -v | grep 'origin.*push' | awk '{print $2}' | grep -oP '((?<=git\@)|((?=https\://)).*(?=\.git)')"
        echo -e "To make a PR visit:\thttps:$url/pull/new/$branch"
        shift
        ;;
      *) break ;;
    esac
  done
}
git config --global alias.showbranch '!git symbolic-ref --short HEAD'
git config --global alias.showrepo "!f(){ git remote get-url --push origin | head -n 1 | sed 's/.\{4\}$//'; }; f;"
git config --global alias.prurl '! echo "https://github.com/$(git showrepo)/pull/new/$(git showbranch)"'
git config --global alias.prurl2 '!f(){ echo \"https://github.com/$(git remote -v | grep origin | awk \''{print $2}\'' | awk -F: \''{print $2}\'' | awk -F. \''{print $1}\'' | head -n 1)/pull/new/$(git symbolic-ref --short HEAD)\"; }; f;'
