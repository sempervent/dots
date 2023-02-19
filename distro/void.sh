#!/usr/bin/env bash
# this is to be used on the void linux system
xbps() { # wrapper for xbps {{{1 
  while :; do
    case $1 in
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
      web) # {{{2
        package_homepage="$(xbps-query "$2" | grep -oP '(?<=homepage: ).*')"
        if [ -x "$(which w3m)" ]; then
          w3m "$package_homepage"
        else:
          echo -e "Package Homepage:\t$package_homepage"
        fi
        shift 2
        ;; # 2}}}
      *) break ;;
    esac
  done;
}
  
