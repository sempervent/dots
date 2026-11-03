# shellcheck shell=bash
# Load generated Bash completion for `dots` (see generated/completions/dots.bash).
# GENERATED candidates come from configs/help + registries — do not edit by hand.

_dots_completion_src=""
if [[ -n ${DOTS_DIR:-} && -f ${DOTS_DIR}/generated/completions/dots.bash ]]; then
	_dots_completion_src="${DOTS_DIR}/generated/completions/dots.bash"
elif [[ -f ${HOME}/.local/share/bash-completion/completions/dots ]]; then
	_dots_completion_src="${HOME}/.local/share/bash-completion/completions/dots"
fi
if [[ -n ${_dots_completion_src} ]]; then
	# shellcheck disable=SC1090
	. "${_dots_completion_src}"
fi
unset _dots_completion_src
