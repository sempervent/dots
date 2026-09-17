#!/usr/bin/env bash
# Bash prompt — classic three-line DOTS box (matches Starship contract).
# Requires bash/colors.sh for color vars; shell/functions.sh for git helpers.
#
# Layout:
#   ┌──┤user@host├─┤HH:MM:SS├─┤Day Mon DD├─┤upstream->branch│
#   ├───┤jobs (N)├─┤venv│
#   └─┤~/path│
#
# Escape hatches:
#   DOTS_PROMPT=off      disable custom PS1
#   DOTS_PROMPT_STATS=1  optional dir count/size (legacy; not in default layout)

# Capture last command status before PROMPT_COMMAND work mutates $?.
_DOTS_LAST_STATUS=0

_dots_prompt_git_segment() {
	local relation state
	relation="$(dots_git_relation 2>/dev/null || true)"
	if [ -z "${relation}" ]; then
		printf ''
		return 0
	fi
	state="$(dots_git_state_marks 2>/dev/null || true)"
	if [ -n "${state}" ]; then
		printf '%s' "─┤${LYEL}${relation}${NC} ${LYEL}${state}${NC}├"
	else
		printf '%s' "─┤${LYEL}${relation}${NC}├"
	fi
}

_dots_prompt_venv_segment() {
	local name=""
	if [ -n "${VIRTUAL_ENV:-}" ]; then
		name="$(basename "${VIRTUAL_ENV}")"
	elif [ -n "${CONDA_DEFAULT_ENV:-}" ] && [ "${CONDA_DEFAULT_ENV}" != "base" ]; then
		name="${CONDA_DEFAULT_ENV}"
	fi
	if [ -n "${name}" ]; then
		printf '%s' "─┤${DGRAY}${name}${NC}│"
	else
		printf '%s' "│"
	fi
}

render_prompt_command() {
	_DOTS_LAST_STATUS=$?

	if [ "${DOTS_PROMPT:-on}" = "off" ]; then
		return 0
	fi

	# History sync (from bash/history.sh) — never abort prompt on history errors
	if declare -F _dots_bash_history_sync >/dev/null 2>&1; then
		_dots_bash_history_sync 2>/dev/null || true
	else
		# Bash `history` requires HISTFILE under `set -u`; keep prompt resilient.
		HISTFILE="${HISTFILE:-${HOME:-/tmp}/.bash_history}"
		history -a 2>/dev/null || true
		history -n 2>/dev/null || true
	fi

	local git_seg venv_seg
	git_seg="$(_dots_prompt_git_segment)"
	venv_seg="$(_dots_prompt_venv_segment)"

	# Optional legacy stats (does not alter default contract location)
	if [ "${DOTS_PROMPT_STATS:-0}" = "1" ]; then
		# Append lightweight note after jobs when explicitly enabled
		:
	fi

	# \t = HH:MM:SS, \d = Weekday Month Date, \j = jobs, \w = cwd with ~
	PS1="\[\n${NC}\]┌──┤\[${GREEN}\]\u\[${NC}\]@\[${BLUE}\]\h\[${NC}\]├─┤\[${BPURP}\]\t\[${NC}\]├─┤\[${CYAN}\]\d\[${NC}\]├${git_seg}${NC}│\n"
	PS1+="├───┤jobs \[${CYAN}\](\j)\[${NC}\]├${venv_seg}\n"
	PS1+="└─┤\[${YELLOW}\]\w\[${NC}\]│ "
	export PS1
}

PROMPT_COMMAND=render_prompt_command
export PROMPT_COMMAND
