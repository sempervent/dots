# shellcheck shell=bash
# Shared interactive tmux auto-attach / create helper.
#
# Controlled by DOTS_AUTO_TMUX (default 1).
# Skips: non-interactive shells, nested tmux, CI, scp/rsync/sftp sessions,
# and when explicitly disabled.

dots_maybe_start_tmux() {
  # Disabled?
  case "${DOTS_AUTO_TMUX:-1}" in
    0|false|FALSE|no|NO|off|OFF) return 0 ;;
  esac

  # Already inside tmux / screen
  [ -n "${TMUX:-}" ] && return 0
  [ "${TERM:-}" = "screen" ] && return 0
  case "${TERM:-}" in
    tmux*|screen*) return 0 ;;
  esac

  # Non-interactive / automation
  case "$-" in
    *i*) ;;
    *) return 0 ;;
  esac

  [ -n "${CI:-}" ] && return 0
  [ -n "${GITHUB_ACTIONS:-}" ] && return 0
  [ -n "${GITLAB_CI:-}" ] && return 0

  # Remote file transfer / restricted sessions
  case "${SSH_ORIGINAL_COMMAND:-}" in
    scp\ *|rsync\ *|sftp\ *) return 0 ;;
  esac
  [ -n "${VSCODE_INJECTION:-}" ] && return 0
  [ "${TERM_PROGRAM:-}" = "vscode" ] && return 0

  command -v tmux >/dev/null 2>&1 || return 0

  # Prefer attaching to an unattached session; otherwise create one.
  # Avoid exec so a failed tmux still leaves a usable shell.
  local id
  id="$(tmux ls 2>/dev/null | awk -F: '!/attached/ {print $1; exit}')"
  if [ -z "${id}" ]; then
    tmux new-session
  else
    tmux attach-session -t "${id}"
  fi
}
