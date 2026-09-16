# shellcheck shell=bash
# Interactive multiplexer auto-start (tmux | herdr | none).
#
# DOTS_MULTIPLEXER=tmux|herdr|none  (default: tmux)
# DOTS_AUTO_TMUX=0 still disables automatic tmux (compat with older configs).
#
# Never nests; skips CI, scp/sftp/rsync, noninteractive, and existing sessions.

dots_in_herdr() {
	[ -n "${HERDR_SOCKET_PATH:-}" ] && return 0
	[ -n "${HERDR_ACTIVE_PANE_ID:-}" ] && return 0
	[ -n "${HERDR_ACTIVE_TAB_ID:-}" ] && return 0
	[ -n "${HERDR_ACTIVE_WORKSPACE_ID:-}" ] && return 0
	return 1
}

dots_should_skip_multiplexer() {
	case "$-" in
	*i*) ;;
	*) return 0 ;;
	esac

	[ -n "${CI:-}" ] && return 0
	[ -n "${GITHUB_ACTIONS:-}" ] && return 0
	[ -n "${GITLAB_CI:-}" ] && return 0

	case "${SSH_ORIGINAL_COMMAND:-}" in
	scp\ * | rsync\ * | sftp\ *) return 0 ;;
	esac
	[ -n "${VSCODE_INJECTION:-}" ] && return 0
	[ "${TERM_PROGRAM:-}" = "vscode" ] && return 0

	return 1
}

dots_maybe_start_herdr() {
	# Auto-start only — never blocks the manual `herdr` command.
	# Skip automatic launch when already inside a multiplexer session.
	dots_in_herdr && return 0
	[ -n "${TMUX:-}" ] && return 0
	dots_should_skip_multiplexer && return 0
	command -v herdr >/dev/null 2>&1 || {
		echo "DOTS_MULTIPLEXER=herdr but herdr is not installed; staying in shell." >&2
		return 0
	}
	# Launch/attach persistent session (foreground)
	herdr
}

dots_maybe_start_tmux() {
	# Auto-start only — never blocks the manual `tmux` command.
	case "${DOTS_AUTO_TMUX:-1}" in
	0 | false | FALSE | no | NO | off | OFF) return 0 ;;
	esac

	[ -n "${TMUX:-}" ] && return 0
	dots_in_herdr && return 0
	case "${TERM:-}" in
	tmux* | screen*) return 0 ;;
	esac

	dots_should_skip_multiplexer && return 0
	command -v tmux >/dev/null 2>&1 || return 0

	local id
	id="$(tmux ls 2>/dev/null | awk -F: '!/attached/ {print $1; exit}')"
	if [ -z "${id}" ]; then
		tmux new-session
	else
		tmux attach-session -t "${id}"
	fi
}

dots_maybe_start_multiplexer() {
	local mode="${DOTS_MULTIPLEXER:-tmux}"

	# Compat: DOTS_AUTO_TMUX=0 forces none for tmux auto path
	case "${DOTS_AUTO_TMUX:-1}" in
	0 | false | FALSE | no | NO | off | OFF)
		if [ "${mode}" = "tmux" ]; then
			mode="none"
		fi
		;;
	esac

	case "${mode}" in
	none | off | OFF)
		return 0
		;;
	herdr)
		dots_maybe_start_herdr
		;;
	tmux | *)
		dots_maybe_start_tmux
		;;
	esac
}
