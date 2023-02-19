#!/usr/bin/env bash
# this is to be used on the void linux system
xbps() { # wrapper for xbps packager operations {{{1
  while :; do
    case $1 in
      list) # list all installed packages without versions {{{2
        xbps-query -l | awk '{print $2}' | xargs -n1 xbps-uhelper-getpkgname
        shift
        ;; # 2}}}
      where) # list files provided by package {{{2
        xbps-query -f "$2"
        shift 2
        ;; # 2}}}
      update) # {{{2
        sudo xbps-install -Su
        xcheckrestart
        shift
        ;; # 2}}}
      install) # {{{2
        shift
        packages=("$@")
        sudo xbps-install "${packages[@]}"
        break
        ;; # 2}}}
      search) # {{{2
        xbps-query -Rs "$2"
        shift 2
        ;; # 2}}}
      web) # open package homepage {{{2
        package_homepage="$(xbps-query "$2" | grep -oP '(?<=homepage: ).*')"
        if [ -x "$(which w3m)" ]; then
          w3m "$package_homepage"
        else
          open-url "$package_homepage" || echo -e "Package Homepage:\t$package_homepage"
        fi
        shift 2
        ;; # 2}}}
      *) break ;;
    esac
  done;
} # 1}}}
# if vim-huge is available use it {{{1
if [ -x "$(which vim-huge)" ]; then
  alias vim="vim-huge"
fi # 1}}}
