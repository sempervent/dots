#!/usr/bin/env bash
export PATH="/opt/hombrew/bin/:$PATH"
src_if() {
  [[ -r "$1" ]] && . "$1"
}
src_if "/opt/homebrew/etc/profile.d/bash_completion.sh"
