#!/usr/bin/env bash
# scripts/fzf-preview.sh — bounded preview for fzf / fzf-tab (never fails the picker)
set -u
target="${1:-}"
if [[ -z "${target}" ]]; then
	printf '(no selection)\n'
	exit 0
fi
if [[ -d "${target}" ]]; then
	if command -v eza >/dev/null 2>&1; then
		eza --tree --level=2 --color=always --group-directories-first "${target}" 2>/dev/null && exit 0
	fi
	if command -v tree >/dev/null 2>&1; then
		tree -L 2 -C --dirsfirst "${target}" 2>/dev/null && exit 0
	fi
	ls -la "${target}" 2>/dev/null || true
	exit 0
fi
if [[ -f "${target}" ]]; then
	if command -v file >/dev/null 2>&1; then
		case "$(file -b --mime-type "${target}" 2>/dev/null || true)" in
			text/*|application/json|application/xml|application/javascript|application/x-sh|application/x-empty|inode/x-empty) ;;
			*)
				printf '(binary file)\n'
				exit 0
				;;
		esac
	fi
	if command -v bat >/dev/null 2>&1; then
		bat --color=always --style=numbers --line-range=:200 --paging=never "${target}" 2>/dev/null && exit 0
	fi
	head -n 200 "${target}" 2>/dev/null || true
	exit 0
fi
printf '%s\n' "${target}"
exit 0
