#!/usr/bin/env bash
# add methods for interacting with the web

wsearch() {
  # define search URLs
  local google="https://www.google.com/search?q="
  local duckduckgo="https://duckduckgo.com/?q="
  local bing="https://www.bing.com/search?q="

  local engine="$google"
  local query=""

  while (( "$#" )); do
    case "$1" in
      --engine)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
          case "$2" in
            google)
              engine="$google"
              ;;
            bing)
              engine="$bing"
              ;;
            duckduckgo)
              engine="$duckduckgo"
              ;;
            *)
              echo "Invalid engine specified" >&2
              return 1
              ;;
          esac
          shift 2
        else
          echo "Error:rgument for --engine missing" >&2
          return 1
        fi
        ;;
      *)
        query+="$1+"
        shift
        ;;
    esac
    local url="${engine}${query%+}"
    local browsers=("w3m" "lynx" "elinks" "links")
    for browser in "${browsers[@]}"; do
      if hash "$browser" 2>/dev/null; then
        "$browser" "$url"
      return 0
      fi
    done
  done
  curl --silent "$url"
}
