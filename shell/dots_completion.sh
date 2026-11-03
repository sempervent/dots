# shellcheck shell=bash
# Shared ./dots / dots CLI completion (Bash + Zsh via bashcompinit).
# Sourced from bash/completion.sh and zsh/dots_completion.zsh.

_dots_help_topics() {
	# Keep in sync with configs/help/topics.toml ids (static for offline speed).
	printf '%s\n' \
		overview getting-started shell completion keybindings profiles \
		components supergroups packages ai models lsp skills backup \
		diagnostics update commands files
}

_dots_cli_commands() {
	printf '%s\n' \
		setup status components lsp ai packages backup backups restore \
		profile models check update help
}

_dots_complete() {
	local cur="${COMP_WORDS[COMP_CWORD]:-}"
	local cmd="${COMP_WORDS[1]:-}"
	local prev="${COMP_WORDS[COMP_CWORD - 1]:-}"

	if [[ ${COMP_CWORD} -eq 1 ]]; then
		COMPREPLY=($(compgen -W "$(_dots_cli_commands | tr '\n' ' ')" -- "${cur}"))
		return 0
	fi

	case "${cmd}" in
	help)
		if [[ ${cur} == -* ]]; then
			COMPREPLY=($(compgen -W "--plain --search --version --list-topics" -- "${cur}"))
		else
			COMPREPLY=($(compgen -W "$(_dots_help_topics | tr '\n' ' ')" -- "${cur}"))
		fi
		;;
	components)
		COMPREPLY=($(compgen -W "list active show help" -- "${cur}"))
		;;
	packages)
		COMPREPLY=($(compgen -W "groups group plan status explain outdated upgrade adopt help" -- "${cur}"))
		;;
	lsp)
		COMPREPLY=($(compgen -W "status check install list help" -- "${cur}"))
		;;
	models)
		COMPREPLY=($(compgen -W "discover pull plan help" -- "${cur}"))
		;;
	ai)
		COMPREPLY=($(compgen -W "status doctor up down help" -- "${cur}"))
		;;
	setup)
		COMPREPLY=($(compgen -W "--dry-run --yes --profile --with --without --help" -- "${cur}"))
		;;
	*)
		COMPREPLY=()
		;;
	esac
	return 0
}

# Bash registration (also works under Zsh bashcompinit)
if [[ -n ${BASH_VERSION:-} ]]; then
	complete -F _dots_complete dots 2>/dev/null || true
	complete -F _dots_complete ./dots 2>/dev/null || true
fi
