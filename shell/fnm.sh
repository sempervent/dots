# shellcheck shell=bash
# shell/fnm.sh — shared fnm init for Bash and Zsh (DOTS Node policy)
# Do NOT source NVM. Existing ~/.nvm data is left untouched.
#
# Usage: sourced after paths.sh; DOTS_SHELL=bash|zsh

_dots_fnm_init() {
	if ! command -v fnm >/dev/null 2>&1; then
		if [ -x /opt/homebrew/bin/fnm ]; then
			# shellcheck disable=SC2098,SC2097
			PATH="/opt/homebrew/bin:${PATH}"
		elif [ -x /usr/local/bin/fnm ]; then
			PATH="/usr/local/bin:${PATH}"
		else
			return 0
		fi
	fi
	case "${DOTS_SHELL:-bash}" in
	zsh)
		eval "$(fnm env --use-on-cd --shell zsh)"
		;;
	*)
		eval "$(fnm env --use-on-cd --shell bash)"
		;;
	esac
}

_dots_fnm_init
