# shellcheck shell=bash
# helpers/shell_diag.sh — shell / keybinding / completion diagnostics (read-only)

dots_shell_is_zsh() { [[ -n ${ZSH_VERSION:-} ]]; }
dots_shell_is_bash() { [[ -n ${BASH_VERSION:-} ]]; }

dots_cmd_shell() {
	local sub="${1:-status}"
	shift || true
	case "${sub}" in
	"" | status) dots_shell_status "$@" ;;
	keys) dots_shell_keys "$@" ;;
	startup) dots_shell_startup "$@" ;;
	-h | --help | help)
		cat <<'EOF'
Usage:
  ./dots shell status    prompt / Tab / Ctrl-R ownership
  ./dots shell keys      keybinding table for this machine
  ./dots shell startup   timed interactive shell samples
EOF
		;;
	*)
		echo "Unknown shell subcommand: ${sub}" >&2
		echo "Try: ./dots shell status|keys|startup" >&2
		return 1
		;;
	esac
}

dots_cmd_completion() {
	local sub="${1:-status}"
	shift || true
	case "${sub}" in
	"" | status) dots_completion_status "$@" ;;
	paths) dots_completion_paths "$@" ;;
	-h | --help | help)
		cat <<'EOF'
Usage:
  ./dots completion status   fzf-tab / compsys / _dots
  ./dots completion paths    installed completion script paths
EOF
		;;
	*)
		echo "Unknown completion subcommand: ${sub}" >&2
		echo "Try: ./dots completion status|paths" >&2
		return 1
		;;
	esac
}

dots_shell_detect_name() {
	if [[ -n ${DOTS_SHELL:-} ]]; then
		printf '%s\n' "${DOTS_SHELL}"
	elif [[ -n ${ZSH_VERSION:-} ]]; then
		printf 'zsh\n'
	elif [[ -n ${BASH_VERSION:-} ]]; then
		printf 'bash\n'
	else
		basename "${SHELL:-unknown}"
	fi
}

# Probe Zsh bindkey owners in a clean-ish interactive child (best-effort).
dots_shell_zsh_bind_probe() {
	command -v zsh >/dev/null 2>&1 || return 1
	DOTS_GREETING=0 DOTS_AUTO_TMUX=0 TERM="${TERM:-xterm-256color}" zsh -ic '
bindkey "^R" 2>/dev/null | head -1
bindkey "^T" 2>/dev/null | head -1
bindkey -M viins "^I" 2>/dev/null | head -1
bindkey "^I" 2>/dev/null | head -1
bindkey -M viins "^ " 2>/dev/null | head -1
bindkey "^ " 2>/dev/null | head -1
typeset -f fzf-file-widget >/dev/null && echo FZF_FILE_OK
typeset -f fzf-cd-widget >/dev/null && echo FZF_CD_OK
[[ -n ${STARSHIP_SHELL:-} ]] && echo STARSHIP_OK
[[ -n ${ZSH:-} ]] && echo OMZ_OK
typeset -f _dots >/dev/null && echo DOTS_COMP_OK
command -v fzf >/dev/null && echo FZF_BIN_OK
command -v fd >/dev/null || command -v fdfind >/dev/null && echo FD_OK
' 2>/dev/null
}

dots_shell_bash_bind_probe() {
	command -v bash >/dev/null 2>&1 || return 1
	DOTS_GREETING=0 DOTS_AUTO_TMUX=0 TERM="${TERM:-xterm-256color}" bash -ic '
bind -q history-search-backward 2>/dev/null | head -1
bind -q complete 2>/dev/null | head -1
type fzf-file-widget 2>/dev/null | head -1
command -v fzf >/dev/null && echo FZF_BIN_OK
command -v fd >/dev/null || command -v fdfind >/dev/null && echo FD_OK
complete -p dots 2>/dev/null | head -1
[[ -n ${STARSHIP_SHELL:-} ]] && echo STARSHIP_OK
' 2>/dev/null
}

dots_shell_classify_bind() {
	# stdin: bindkey line; args: expected patterns (regex)
	local line expected
	line="$(cat)"
	[[ -z ${line} ]] && {
		echo "missing"
		return 0
	}
	shift || true
	for expected in "$@"; do
		if printf '%s\n' "${line}" | grep -Eq "${expected}"; then
			echo "ok:${line}"
			return 0
		fi
	done
	echo "unexpected:${line}"
}

dots_shell_status() {
	local shell_name probe mux prompt_owner tab_owner hist_owner file_owner space_owner
	shell_name="$(dots_shell_detect_name)"
	mux="${DOTS_MULTIPLEXER:-}"
	[[ -z ${mux} && -f ${HOME}/.config/dots/runtime.env ]] && \
		mux="$(grep -E '^DOTS_MULTIPLEXER=' "${HOME}/.config/dots/runtime.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d \"\')"
	mux="${mux:-unknown}"

	dots_ui_header "DOTS Shell" 2>/dev/null || echo "DOTS Shell"
	echo "────────────────────────────────"
	echo "shell              ${shell_name}${ZSH_VERSION:+ ${ZSH_VERSION}}${BASH_VERSION:+ ${BASH_VERSION}}"
	if [[ -t 0 ]]; then
		echo "interactive        yes"
	else
		echo "interactive        no (probes use child shells)"
	fi

	prompt_owner="unknown"
	tab_owner="unknown"
	hist_owner="unknown"
	file_owner="unknown"
	space_owner="unknown"

	if command -v zsh >/dev/null 2>&1; then
		probe="$(dots_shell_zsh_bind_probe || true)"
		if echo "${probe}" | grep -q STARSHIP_OK; then
			prompt_owner="Starship"
		elif echo "${probe}" | grep -q OMZ_OK; then
			prompt_owner="Oh My Zsh theme / custom"
		fi
		echo "${probe}" | grep -q OMZ_OK && echo "Oh My Zsh          active" || echo "Oh My Zsh          inactive"
		echo "prompt             ${prompt_owner}"
		echo "completion         Zsh compsys"

		local r_line t_line i_line sp_line
		r_line="$(echo "${probe}" | sed -n '1p')"
		t_line="$(echo "${probe}" | sed -n '2p')"
		i_line="$(echo "${probe}" | sed -n '3p')"
		[[ -z ${i_line} || ${i_line} == *"undefined"* ]] && i_line="$(echo "${probe}" | sed -n '4p')"
		sp_line="$(echo "${probe}" | sed -n '5p')"
		[[ -z ${sp_line} || ${sp_line} == *"undefined"* ]] && sp_line="$(echo "${probe}" | sed -n '6p')"

		if echo "${r_line}" | grep -Eq 'atuin'; then
			hist_owner="Atuin"
		elif echo "${r_line}" | grep -Eq 'fzf-history'; then
			hist_owner="fzf"
		elif echo "${r_line}" | grep -Eq 'history-incremental'; then
			hist_owner="zsh history-incremental-search (unexpected)"
		else
			hist_owner="${r_line:-missing}"
		fi

		if echo "${i_line}" | grep -Eq 'fzf-tab-complete'; then
			tab_owner="fzf-tab"
		elif echo "${i_line}" | grep -Eq 'expand-or-complete|complete-word'; then
			tab_owner="normal compsys (fzf-tab inactive)"
		else
			tab_owner="${i_line:-missing}"
		fi

		if echo "${t_line}" | grep -Eq 'fzf-file-widget' || echo "${probe}" | grep -q FZF_FILE_OK; then
			file_owner="fzf-file-widget"
		else
			file_owner="${t_line:-missing}"
		fi

		if echo "${sp_line}" | grep -Eq 'autosuggest-accept'; then
			space_owner="autosuggest-accept"
		elif [[ -z ${sp_line} || ${sp_line} == *"undefined"* ]]; then
			space_owner="unavailable"
		else
			space_owner="${sp_line}"
		fi

		echo "Tab selector       ${tab_owner}"
		echo ""
		echo "History"
		echo "  Ctrl-R           ${hist_owner}"
		echo ""
		echo "Files"
		echo "  Ctrl-T           ${file_owner}"
		if echo "${probe}" | grep -q FZF_CD_OK; then
			echo "  Alt-C            fzf-cd-widget"
		else
			echo "  Alt-C            unknown/missing"
		fi
		echo ""
		echo "Other"
		echo "  Ctrl-Space       ${space_owner}"

		# Conflict warnings
		echo ""
		echo "Checks"
		if echo "${i_line}" | grep -Eq 'expand-or-complete' && ! echo "${i_line}" | grep -Eq 'fzf-tab'; then
			echo "WARN: Tab is bound to expand-or-complete, expected fzf-tab"
			echo "  Reapply: ./dots setup"
		fi
		if echo "${r_line}" | grep -Eq 'history-incremental-search' && ! echo "${r_line}" | grep -Eq 'atuin|fzf-history'; then
			echo "WARN: Ctrl-R is bound to history-incremental-search-backward, expected Atuin/fzf"
			echo "  Reapply: ./dots setup"
		fi
		if [[ ${space_owner} == unavailable ]]; then
			echo "WARN: Ctrl-Space is unavailable"
		fi
		if echo "${probe}" | grep -q DOTS_COMP_OK; then
			echo "OK: _dots completion function loaded in probe"
		else
			echo "WARN: _dots completion not loaded in probe shell"
			echo "  Install: ./dots setup  (links generated/completions/_dots)"
		fi
	elif command -v bash >/dev/null 2>&1; then
		probe="$(dots_shell_bash_bind_probe || true)"
		echo "${probe}" | grep -q STARSHIP_OK && prompt_owner="Starship" || prompt_owner="bash/PS1"
		echo "prompt             ${prompt_owner}"
		echo "completion         bash-completion / compspec"
		echo "${probe}" | grep -q FZF_BIN_OK && echo "fzf                installed" || echo "fzf                missing"
		if echo "${probe}" | grep -q '_dots_complete\|complete -F'; then
			echo "dots completion    registered"
		else
			echo "WARN: dots Bash completion not registered in probe"
		fi
	fi

	echo ""
	echo "Multiplexer"
	case "${mux}" in
	herdr) echo "  Herdr             active" ;;
	tmux) echo "  tmux              active" ;;
	none | "") echo "  (none / unset)" ;;
	*) echo "  ${mux}" ;;
	esac
	if [[ ${mux} != tmux ]] && command -v tmux >/dev/null 2>&1; then
		echo "  tmux              installed, not selected"
	fi
	if [[ ${mux} != herdr ]] && command -v herdr >/dev/null 2>&1; then
		echo "  Herdr             installed, not selected"
	fi
}

dots_shell_keys() {
	dots_ui_header "DOTS Keybindings" 2>/dev/null || echo "DOTS Keybindings"
	echo "────────────────────────────────────────────"
	printf '%-14s %-14s %s\n' "Key" "Context" "Action"
	# Prefer metadata file when present
	if [[ -f ${DIR}/configs/help/keybindings.toml ]] && command -v python3 >/dev/null 2>&1; then
		DIR="${DIR}" python3 - <<'PY'
import tomllib, os
from pathlib import Path
data = tomllib.loads((Path(os.environ["DIR"]) / "configs/help/keybindings.toml").read_text())
for b in data.get("bindings") or []:
    key = (b.get("key") or "").strip()
    ctx = (b.get("context") or "").strip()
    desc = (b.get("description") or "").strip()
    print(f"{key:<14} {ctx:<14} {desc}")
PY
	else
		printf '%-14s %-14s %s\n' "Ctrl-R" "shell" "fuzzy history"
		printf '%-14s %-14s %s\n' "Ctrl-T" "shell" "fuzzy file insert"
		printf '%-14s %-14s %s\n' "Alt-C" "shell" "fuzzy directory"
		printf '%-14s %-14s %s\n' "Tab" "zsh" "contextual fuzzy completion"
		printf '%-14s %-14s %s\n' "Ctrl-Space" "zsh vi insert" "accept autosuggestion"
	fi
	echo ""
	echo "Runtime ownership: ./dots shell status"
}

# Aggregate timing helper (pure; used by tests + startup command)
dots_shell_timing_stats() {
	# stdin: one duration_ms per line → prints min median max count
	local -a vals=()
	local v
	while IFS= read -r v; do
		[[ ${v} =~ ^[0-9]+$ ]] || continue
		vals+=("${v}")
	done
	((${#vals[@]} == 0)) && {
		echo "0 0 0 0"
		return 0
	}
	local sorted
	sorted="$(printf '%s\n' "${vals[@]}" | LC_ALL=C sort -n)"
	local -a s=()
	while IFS= read -r v; do
		s+=("${v}")
	done <<<"${sorted}"
	local -i n=${#s[@]}
	local -i min=${s[0]}
	local -i max=${s[n - 1]}
	local -i mid
	if ((n % 2 == 1)); then
		mid=${s[n / 2]}
	else
		mid=$(((s[n / 2 - 1] + s[n / 2]) / 2))
	fi
	printf '%s %s %s %s\n' "${min}" "${mid}" "${max}" "${n}"
}

dots_shell_startup() {
	local shell_bin="${SHELL:-/bin/zsh}"
	local name runs=5 i
	name="$(basename "${shell_bin}")"
	local -a samples=()
	echo "Measuring ${name} interactive startup (${runs} runs)…"
	for ((i = 0; i < runs; i++)); do
		local start end ms
		start="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || date +%s)"
		DOTS_GREETING=0 DOTS_AUTO_TMUX=0 TERM=dumb \
			"${shell_bin}" -i -c 'exit' >/dev/null 2>&1 || true
		end="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || date +%s)"
		if [[ ${#start} -gt 9 || ${#end} -gt 9 ]]; then
			ms=$((end - start))
		else
			# second resolution fallback
			ms=$(((end - start) * 1000))
		fi
		((ms < 0)) && ms=0
		samples+=("${ms}")
		echo "  run $((i + 1)): ${ms} ms"
	done
	local stats min mid max n
	stats="$(printf '%s\n' "${samples[@]}" | dots_shell_timing_stats)"
	read -r min mid max n <<<"${stats}"
	echo ""
	echo "${name} startup"
	echo "  runs      ${n}"
	echo "  min       ${min} ms"
	echo "  median    ${mid} ms"
	echo "  max       ${max} ms"
	if ((mid > 500)); then
		echo "WARN: median startup > 500 ms (informational)"
	elif ((mid > 300)); then
		echo "NOTE: median startup > 300 ms"
	else
		echo "OK: startup looks reasonable"
	fi
}

dots_completion_paths() {
	echo "DOTS completion paths"
	echo "────────────────────────────────"
	echo "generated Zsh:  ${DIR}/generated/completions/_dots"
	echo "generated Bash: ${DIR}/generated/completions/dots.bash"
	echo "user Zsh:       ${HOME}/.local/share/zsh/site-functions/_dots"
	echo "user Bash:      ${HOME}/.local/share/bash-completion/completions/dots"
	local p
	for p in \
		"${DIR}/generated/completions/_dots" \
		"${HOME}/.local/share/zsh/site-functions/_dots" \
		"${DIR}/generated/completions/dots.bash" \
		"${HOME}/.local/share/bash-completion/completions/dots"; do
		if [[ -e ${p} ]]; then
			echo "  present: ${p}"
		else
			echo "  missing: ${p}"
		fi
	done
}

dots_completion_status() {
	dots_ui_header "DOTS Completion" 2>/dev/null || echo "DOTS Completion"
	echo "────────────────────────────────"
	local shell_name
	shell_name="$(dots_shell_detect_name)"
	echo "Shell           ${shell_name}"
	if [[ ${shell_name} == zsh ]]; then
		echo "Native engine   zsh compsys"
	else
		echo "Native engine   bash-completion"
	fi
	local fzf_tab="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}/plugins/fzf-tab"
	if [[ -f ${fzf_tab}/fzf-tab.plugin.zsh || -f ${fzf_tab}/fzf-tab.zsh ]]; then
		echo "Fuzzy selector  fzf-tab"
	else
		echo "Fuzzy selector  (fzf-tab not installed)"
	fi
	command -v fzf >/dev/null 2>&1 && echo "fzf             installed" || echo "fzf             missing"
	if command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1; then
		echo "fd              installed"
	else
		echo "fd              missing"
	fi
	echo ""
	echo "Bindings (from ./dots shell status probe)"
	if command -v zsh >/dev/null 2>&1; then
		local probe
		probe="$(dots_shell_zsh_bind_probe || true)"
		echo "  Tab           $(echo "${probe}" | sed -n '3p' | tr -s ' ' | cut -c1-60)"
		echo "  Ctrl-R        $(echo "${probe}" | sed -n '1p' | tr -s ' ' | cut -c1-60)"
		echo "  Ctrl-T        $(echo "${probe}" | sed -n '2p' | tr -s ' ' | cut -c1-60)"
	fi
	echo ""
	echo "DOTS completion"
	if [[ -e ${HOME}/.local/share/zsh/site-functions/_dots ]]; then
		echo "  _dots         ${HOME}/.local/share/zsh/site-functions/_dots"
	elif [[ -f ${DIR}/generated/completions/_dots ]]; then
		echo "  _dots         ${DIR}/generated/completions/_dots (repo; not yet installed)"
	else
		echo "  _dots         missing — run ./setup.sh"
	fi
	dots_completion_paths | sed 's/^/  /' | tail -n +3
}

# Install generated completion scripts into user paths (called from setup).
dots_completion_install() {
	local zsh_src bash_src zsh_dest bash_dest fpath_line
	zsh_src="${DIR}/generated/completions/_dots"
	bash_src="${DIR}/generated/completions/dots.bash"
	zsh_dest="${HOME}/.local/share/zsh/site-functions"
	bash_dest="${HOME}/.local/share/bash-completion/completions"
	echo "=== dots CLI completions ==="
	if [[ ! -f ${zsh_src} || ! -f ${bash_src} ]]; then
		echo "Warn: generated completions missing — run: python3 scripts/docs/generate_completions.py" >&2
		return 0
	fi
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] link ${zsh_dest}/_dots"
		echo "[dry-run] link ${bash_dest}/dots"
		return 0
	fi
	ensure_dir "${zsh_dest}"
	ensure_dir "${bash_dest}"
	ln -sfn "${zsh_src}" "${zsh_dest}/_dots"
	ln -sfn "${bash_src}" "${bash_dest}/dots"
	echo "OK: ${zsh_dest}/_dots"
	echo "OK: ${bash_dest}/dots"
}
