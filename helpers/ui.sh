#!/usr/bin/env bash
# shellcheck shell=bash
# helpers/ui.sh — pure-Bash interactive prompts (no gum/dialog/fzf required)
#
# Test injection:
#   Feed answers on stdin, or set DOTS_UI_ANSWERS to a newline-separated queue.
#   Answers are consumed via FD 8 so $(prompt) subshells still advance the queue
#   (file offset is shared). Works on Bash 3.2 (macOS).
#   DOTS_UI_NONINTERACTIVE=1 refuses prompts that need input.

# Fixed FD for scripted answers (Bash 3.2 has no {var} exec redirects)
DOTS_UI_ANSWER_FD=""

dots_ui_load_answers() {
	if [[ -n ${DOTS_UI_ANSWER_FD:-} ]]; then
		exec 8<&- 2>/dev/null || true
		DOTS_UI_ANSWER_FD=""
	fi
	[[ -n ${DOTS_UI_ANSWERS:-} ]] || return 0

	local tmp
	tmp="$(mktemp "${TMPDIR:-/tmp}/dots-ui-answers.XXXXXX")"
	# Write non-empty answer lines only
	local line
	while IFS= read -r line || [[ -n ${line} ]]; do
		[[ -z ${line} && ! -s ${tmp} ]] && continue
		printf '%s\n' "${line}" >>"${tmp}"
	done <<<"${DOTS_UI_ANSWERS}"
	# Strip trailing empty lines
	if [[ -f ${tmp} ]]; then
		while [[ -s ${tmp} ]]; do
			line="$(tail -n 1 "${tmp}")"
			[[ -n ${line} ]] && break
			# delete last line (portable)
			sed '$d' "${tmp}" >"${tmp}.n" && mv "${tmp}.n" "${tmp}"
		done
	fi
	exec 8<"${tmp}"
	DOTS_UI_ANSWER_FD=8
	rm -f "${tmp}"
}

dots_ui_next_answer() {
	if [[ -n ${DOTS_UI_ANSWER_FD:-} ]]; then
		local ans
		if IFS= read -r -u "${DOTS_UI_ANSWER_FD}" ans; then
			printf '%s\n' "${ans}"
			return 0
		fi
	fi
	return 1
}

dots_ui_read_line() {
	local prompt="$1" def="${2:-}" ans
	if ans="$(dots_ui_next_answer)"; then
		[[ -z ${ans} && -n ${def} ]] && ans="${def}"
		printf '%s\n' "${ans}"
		return 0
	fi
	if [[ ${DOTS_UI_NONINTERACTIVE:-0} -eq 1 ]]; then
		if [[ -n ${def} ]]; then
			printf '%s\n' "${def}"
			return 0
		fi
		echo "Error: noninteractive prompt needs input: ${prompt}" >&2
		return 1
	fi
	# Prompt on stderr so $(capture) of answers stays clean
	if [[ -n ${def} ]]; then
		printf '%s [%s]: ' "${prompt}" "${def}" >&2
		read -r ans || return 1
		[[ -z ${ans} ]] && ans="${def}"
	else
		printf '%s: ' "${prompt}" >&2
		read -r ans || return 1
	fi
	printf '%s\n' "${ans}"
}

# Prompt yes/no. Default y|n via second arg (default n). Prints y or n on stdout.
dots_prompt_yesno() {
	local prompt="$1" def="${2:-n}" ans
	local hint="y/N"
	[[ ${def} == y || ${def} == Y ]] && hint="Y/n"
	ans="$(dots_ui_read_line "${prompt} [${hint}]" "")" || return 1
	[[ -z ${ans} ]] && ans="${def}"
	case "${ans}" in
	y | Y | yes | YES) printf 'y\n' ;;
	*) printf 'n\n' ;;
	esac
}

# Prompt for a numbered choice. Args: prompt, then "label" options.
# Prints 1-based index on stdout. Menu goes to stderr.
# Default via DOTS_UI_CHOICE_DEFAULT (1-based) or 1.
dots_prompt_choice() {
	local prompt="$1"
	shift
	local -a opts=("$@")
	local i n="${#opts[@]}" ans def="${DOTS_UI_CHOICE_DEFAULT:-1}"
	echo "" >&2
	echo "${prompt}" >&2
	i=1
	while [[ ${i} -le ${n} ]]; do
		echo "  ${i}) ${opts[$((i - 1))]}" >&2
		i=$((i + 1))
	done
	while true; do
		ans="$(dots_ui_read_line "Choice" "${def}")" || return 1
		case "${ans}" in
		*[!0-9]*)
			echo "Enter a number 1-${n}" >&2
			continue
			;;
		esac
		if [[ ${ans} -ge 1 && ${ans} -le ${n} ]]; then
			printf '%s\n' "${ans}"
			return 0
		fi
		echo "Enter a number 1-${n}" >&2
	done
}

dots_prompt_text() {
	local prompt="$1" def="${2:-}"
	dots_ui_read_line "${prompt}" "${def}"
}

dots_ui_header() {
	echo ""
	echo "════════════════════════════════════════"
	echo " $1"
	echo "════════════════════════════════════════"
}

dots_ui_section() {
	echo ""
	echo "── $1 ──"
}

dots_ui_info() { echo "  $1"; }
dots_ui_ok() { echo "  OK: $1"; }
dots_ui_warn() { echo "  WARN: $1" >&2; }
dots_ui_err() { echo "  ERROR: $1" >&2; }
dots_ui_manual() { echo "  MANUAL: $1"; }

dots_ui_stage() {
	local cur="$1" total="$2" name="$3" status="${4:-}"
	if [[ -n ${status} ]]; then
		printf '[%s/%s] %-32s %s\n' "${cur}" "${total}" "${name}" "${status}"
	else
		printf '[%s/%s] %s\n' "${cur}" "${total}" "${name}"
	fi
}
