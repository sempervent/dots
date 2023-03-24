#!/usr/bin/env bash
# -*- coding: utf-8 -*-
git config --global push.autoSetupRemote true
git config --global pull.rebase false
# shellcheck disable=SC2016
git config --global alias.release '!git checkout main && git pull && git checkout -b Deploy_$(date +%F)'
# shellcheck disable=SC2016
if [ -x "$(which fortune)" ]; then
  git config --global alias.fortune '!git commit -m "$(fortune)"'
  git config --global alias.yolo '!f(){ git commit -m "$(fortune)" && git push;}; f;'
fi
gitpr() { # define a git pr method {{{1
  PREFIX="release/"
  DATEFMT="%F"
  main=""
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
      -m|--main|--master)
        if [ "$1" = "--main" ]; then
          main="main"
        elif [ "$1" = "--master" ]; then
          main="master"
        else
          main="$2"
          shift 1
        fi
        shift 1
        ;;
      release)
        if [ "$main" = "" ]; then
          main="$(git branch --list | grep -oE '(master|main)')"
        fi
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
} # 1}}}
add_to_gitignore_and_remove() { # add to .gitignore and remove {{{1
  ext="$1"
  echo "$ext" | cat - .gitignore > temp && mv temp .gitignore
  git rm -r --cached "$(find . -name "*.$ext")"
} # 1}}}
git_checkpoint(){ # {{{1
  FORTUNE=$(echo "$FORTUNE" | sed 's/\n/ /g' | sed 's/\s+/ /g')
  git commit -am "$FORTUNE" && git push
} # 1}}}
git config --global alias.showbranch '!git symbolic-ref --short HEAD'
git config --global alias.showrepo "!f(){ git remote get-url --push origin | head -n 1 | sed 's/.\{4\}$//'; }; f;"
git config --global alias.prurl '! echo "https://github.com/$(git showrepo)/pull/new/$(git showbranch)"'
git config --global alias.prurl2 '!f(){ echo \"https://github.com/$(git remote -v | grep origin | awk \''{print $2}\'' | awk -F: \''{print $2}\'' | awk -F. \''{print $1}\'' | head -n 1)/pull/new/$(git symbolic-ref --short HEAD)\"; }; f;'
git config --global alias.cp "!git_checkpoint"  # FIXME should do git_checkpoint fortune
