# shellcheck shell=bash
# shellcheck disable=SC1091
# shell/runtime.sh — load profile runtime + machine-local overrides with correct precedence
#
# Precedence (highest wins):
#   1. Process environment already set before shell init
#   2. ~/.config/dots/local.sh  (machine overrides)
#   3. ~/.config/dots/runtime.env  (profile policy)
#   4. shell/exports.sh defaults
#
# Implementation: snapshot locked DOTS_* vars, apply runtime + local, restore locks.

_dots_runtime_snapshot_locks() {
	# Record which managed vars were already set in the process environment.
	_DOTS_LOCK_PROFILE="${DOTS_PROFILE+1}"
	_DOTS_LOCK_MULTIPLEXER="${DOTS_MULTIPLEXER+1}"
	_DOTS_LOCK_GREETING="${DOTS_GREETING+1}"
	_DOTS_LOCK_PROMPT_STATS="${DOTS_PROMPT_STATS+1}"
	_DOTS_LOCK_AUTO_TMUX="${DOTS_AUTO_TMUX+1}"
	_DOTS_LOCK_PACKAGE_GROUPS="${DOTS_PACKAGE_GROUPS+1}"
	_DOTS_VAL_PROFILE="${DOTS_PROFILE-}"
	_DOTS_VAL_MULTIPLEXER="${DOTS_MULTIPLEXER-}"
	_DOTS_VAL_GREETING="${DOTS_GREETING-}"
	_DOTS_VAL_PROMPT_STATS="${DOTS_PROMPT_STATS-}"
	_DOTS_VAL_AUTO_TMUX="${DOTS_AUTO_TMUX-}"
	_DOTS_VAL_PACKAGE_GROUPS="${DOTS_PACKAGE_GROUPS-}"
}

_dots_runtime_restore_locks() {
	[ "${_DOTS_LOCK_PROFILE:-}" = 1 ] && DOTS_PROFILE="${_DOTS_VAL_PROFILE}" && export DOTS_PROFILE
	[ "${_DOTS_LOCK_MULTIPLEXER:-}" = 1 ] && DOTS_MULTIPLEXER="${_DOTS_VAL_MULTIPLEXER}" && export DOTS_MULTIPLEXER
	[ "${_DOTS_LOCK_GREETING:-}" = 1 ] && DOTS_GREETING="${_DOTS_VAL_GREETING}" && export DOTS_GREETING
	[ "${_DOTS_LOCK_PROMPT_STATS:-}" = 1 ] && DOTS_PROMPT_STATS="${_DOTS_VAL_PROMPT_STATS}" && export DOTS_PROMPT_STATS
	[ "${_DOTS_LOCK_AUTO_TMUX:-}" = 1 ] && DOTS_AUTO_TMUX="${_DOTS_VAL_AUTO_TMUX}" && export DOTS_AUTO_TMUX
	[ "${_DOTS_LOCK_PACKAGE_GROUPS:-}" = 1 ] && DOTS_PACKAGE_GROUPS="${_DOTS_VAL_PACKAGE_GROUPS}" && export DOTS_PACKAGE_GROUPS
	unset _DOTS_LOCK_PROFILE _DOTS_LOCK_MULTIPLEXER _DOTS_LOCK_GREETING \
		_DOTS_LOCK_PROMPT_STATS _DOTS_LOCK_AUTO_TMUX _DOTS_LOCK_PACKAGE_GROUPS \
		_DOTS_VAL_PROFILE _DOTS_VAL_MULTIPLEXER _DOTS_VAL_GREETING \
		_DOTS_VAL_PROMPT_STATS _DOTS_VAL_AUTO_TMUX _DOTS_VAL_PACKAGE_GROUPS
}

_dots_runtime_snapshot_locks

# 3) Profile runtime policy
if [ -f "${HOME}/.config/dots/runtime.env" ]; then
	# shellcheck disable=SC1090
	. "${HOME}/.config/dots/runtime.env"
fi

# 2) Machine-local overrides (may export DOTS_* and other non-secrets)
if [ -f "${HOME}/.config/dots/local.sh" ]; then
	# shellcheck disable=SC1090
	. "${HOME}/.config/dots/local.sh"
fi

# 1) Process environment wins
_dots_runtime_restore_locks
