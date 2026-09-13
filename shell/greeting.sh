# shellcheck shell=bash
# Shared welcome greeting (fortune | cowsay | lolcat when available).

dots_greeting() {
  case "${DOTS_GREETING:-1}" in
    0|false|FALSE|no|NO|off|OFF) return 0 ;;
  esac

  # Avoid repeating the banner in every nested pane if already shown
  [ -n "${DOTS_GREETING_SHOWN:-}" ] && return 0
  export DOTS_GREETING_SHOWN=1

  echo "Welcome, $(whoami)!"
  if command -v fortune >/dev/null 2>&1; then
    if command -v cowsay >/dev/null 2>&1; then
      if command -v lolcat >/dev/null 2>&1; then
        pipe-fortune | cowsay | lolcat
      else
        pipe-fortune | cowsay
      fi
    else
      fortune
    fi
  fi
}
