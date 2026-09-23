#!/usr/bin/env bash
# setup.sh — idempotent installer for sempervent/dots
#
# Usage:
#   ./setup.sh
#   ./setup.sh --with herdr,hermes,ollama,archify
#   ./setup.sh --with=herdr
#   ./setup.sh --with archify
#   ./setup.sh --dry-run
#   ./setup.sh --help
#
# Default setup does NOT install AI tooling (herdr / hermes / ollama / agent skills).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SYM_DIR="${DIR}/syms"
OLD_DOTS="${HOME}/.old_dots"
VUNDLE_DIR="${HOME}/.vim/bundle/Vundle.vim"
TMUX_PLUGIN_DIR="${HOME}/.tmux/plugins/tpm"
ZSH="${ZSH:-${HOME}/.oh-my-zsh}"
ZSH_CUSTOM="${ZSH_CUSTOM:-${ZSH}/custom}"
DRY_RUN=0
NO_INSTALL=0
DOTS_WITH_COMPONENTS=()

# Stage 0 shared with bootstrap.sh (Homebrew / Python / CLT)
# shellcheck source=helpers/bootstrap_prereqs.sh
source "${DIR}/helpers/bootstrap_prereqs.sh"

# shellcheck source=helpers/components.sh
source "${DIR}/helpers/components.sh"
SUPPORTED_WITH=()
dots_load_supported_with_into SUPPORTED_WITH

# shellcheck source=helpers/ai_consent.sh
source "${DIR}/helpers/ai_consent.sh"
# shellcheck source=helpers/agent_skills.sh
source "${DIR}/helpers/agent_skills.sh"
# shellcheck source=helpers/skills_pack.sh
source "${DIR}/helpers/skills_pack.sh"
# shellcheck source=helpers/herdr_config.sh
source "${DIR}/helpers/herdr_config.sh"
# shellcheck source=helpers/cask_apps.sh
source "${DIR}/helpers/cask_apps.sh"
# shellcheck source=helpers/optional_components.sh
source "${DIR}/helpers/optional_components.sh"
# shellcheck source=helpers/drawthings.sh
source "${DIR}/helpers/drawthings.sh"
# shellcheck source=helpers/opencode.sh
source "${DIR}/helpers/opencode.sh"
# shellcheck source=helpers/codex.sh
source "${DIR}/helpers/codex.sh"
# shellcheck source=helpers/cursor.sh
source "${DIR}/helpers/cursor.sh"
# shellcheck source=helpers/agent_router.sh
source "${DIR}/helpers/agent_router.sh"
# shellcheck source=helpers/fnm.sh
source "${DIR}/helpers/fnm.sh"
# shellcheck source=helpers/lsp.sh
source "${DIR}/helpers/lsp.sh"
# shellcheck source=helpers/ai_server.sh
source "${DIR}/helpers/ai_server.sh"
# shellcheck source=helpers/nvim.sh
source "${DIR}/helpers/nvim.sh"
# shellcheck source=helpers/notify.sh
source "${DIR}/helpers/notify.sh"
# shellcheck source=helpers/path_hygiene.sh
source "${DIR}/helpers/path_hygiene.sh"
# shellcheck source=helpers/telemetry.sh
source "${DIR}/helpers/telemetry.sh"
# shellcheck source=helpers/launchers.sh
source "${DIR}/helpers/launchers.sh"
# shellcheck source=helpers/leaf.sh
source "${DIR}/helpers/leaf.sh"
# shellcheck source=helpers/rsync.sh
source "${DIR}/helpers/rsync.sh"
# shellcheck source=helpers/packages.sh
source "${DIR}/helpers/packages.sh"
# shellcheck source=helpers/package_state.sh
source "${DIR}/helpers/package_state.sh"
# shellcheck source=helpers/links.sh
source "${DIR}/helpers/links.sh"
# shellcheck source=helpers/backup.sh
source "${DIR}/helpers/backup.sh"
# shellcheck source=helpers/mactools.sh
source "${DIR}/helpers/mactools.sh"
# shellcheck source=helpers/git_config.sh
source "${DIR}/helpers/git_config.sh"
# shellcheck source=helpers/profiles.sh
source "${DIR}/helpers/profiles.sh"

PROFILE_NAME=""
PROFILE_PACKAGES=()
PROFILE_RUNTIME_MULTIPLEXER=""
PROFILE_RUNTIME_GREETING=""
PROFILE_RUNTIME_PROMPT_STATS=""
PROFILE_RUNTIME_AUTO_TMUX=""
DOTS_SETUP_PROFILE=""

usage() {
	cat <<EOF
Usage: ./setup.sh [options]

Install / refresh dotfiles (idempotent). Safe to re-run.

Options:
  --with <list>     Comma-separated components and/or supergroups.
$(dots_print_selector_help | sed 's/^/                    /')
  --with=<list>     Same as --with <list>
  --without <list>  Exclude selectors after expansion (profile without / CLI)
  --without=<list>  Same as --without <list>
  --dry-run         Preview actions without modifying the machine
  -h, --help        Show this help

Discover selectors: ./dots components list
Docs: https://sempervent.github.io/dots/using/components/

Consent vs presence:
  A binary already on PATH does NOT authorize DOTS to configure it.
  AI client config runs only for components listed in --with this run.
  --with ai expands to every AI application supported on this machine and is
  explicit consent for those expanded members (same as listing each id).
  Prefer ./bootstrap.sh --profile {base,home,work,all|path.toml} for onboarding.
  Edit profiles with ./configure.sh (writes TOML only).

Examples:
  ./setup.sh
  ./setup.sh --with herdr
  ./setup.sh --with fluidvoice
  ./setup.sh --with mactools
  ./setup.sh --with herdr,hermes,mactools
  ./setup.sh --with ai
  ./setup.sh --with ai --without cursor
  ./setup.sh --with cursor
  ./setup.sh --with ai-skills
  ./setup.sh --with skills,ai-skills
  ./setup.sh --with hermes,skills,ai-skills
  ./setup.sh --with herdr,cursor
  ./setup.sh --with drawthings
  ./setup.sh --with hermes,drawthings
  ./setup.sh --with cursor,drawthings
  ./setup.sh --with skills
  ./setup.sh --with images,tex
  ./setup.sh --with lsp
  ./setup.sh --dry-run --with ai
  ./bootstrap.sh --profile home
  ./bootstrap.sh --profile work --with ai
  ./configure.sh --help

Default ./setup.sh installs core shell UX (fnm, Starship, Nerd Font, Neovim,
terminal-notifier) but does NOT install AI tools, agent skills, or models.

Environment (runtime shells, not installer):
  DOTS_MULTIPLEXER=tmux|herdr|none   (default: tmux)
  DOTS_AUTO_TMUX=0                   disable auto tmux (compat)
  DOTS_PROMPT_STATS=1                enable prompt dir stats (legacy)
  DOTS_GREETING=0                    silence fortune greeting
  DOTS_HERMES_NOTIFY_THRESHOLD=60    Hermes notify min session seconds
EOF
}

parse_with_list() {
	local raw="$1" item
	local -a selectors=()
	IFS=',' read -r -a _parts <<<"${raw}"
	for item in "${_parts[@]+"${_parts[@]}"}"; do
		item="$(echo "${item}" | tr -d '[:space:]')"
		[[ -z ${item} ]] && continue
		if ! dots_selector_is_known "${item}"; then
			echo "Error: unknown component or supergroup '${item}'" >&2
			dots_print_selector_help >&2
			exit 1
		fi
		selectors+=("${item}")
	done
	[[ ${#selectors[@]} -eq 0 ]] && return 0
	local _exp _cid _sel
	_exp="$(dots_expand_with_selectors "${selectors[@]}")" || exit 1
	while IFS= read -r _cid; do
		[[ -n ${_cid} ]] && DOTS_WITH_COMPONENTS+=("${_cid}")
	done <<<"${_exp}"
	for _sel in "${selectors[@]}"; do
		if dots_component_is_known "${_sel}"; then
			dots_require_explicit_component_supported "${_sel}" || exit 1
		fi
	done
}

# Deduplicate while preserving order
uniq_components() {
	local seen="|" c out=()
	for c in "${DOTS_WITH_COMPONENTS[@]+"${DOTS_WITH_COMPONENTS[@]}"}"; do
		case "${seen}" in
		*"|${c}|"*) ;;
		*)
			out+=("${c}")
			seen="${seen}${c}|"
			;;
		esac
	done
	DOTS_WITH_COMPONENTS=("${out[@]+"${out[@]}"}")
}

has_component() {
	local want="$1" c
	for c in "${DOTS_WITH_COMPONENTS[@]+"${DOTS_WITH_COMPONENTS[@]}"}"; do
		[[ ${c} == "${want}" ]] && return 0
	done
	return 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	--dry-run)
		DRY_RUN=1
		shift
		;;
	--no-install)
		NO_INSTALL=1
		shift
		;;
	--with=*)
		parse_with_list "${1#--with=}"
		shift
		;;
	--with)
		[[ $# -ge 2 ]] || {
			echo "Error: --with requires an argument" >&2
			exit 1
		}
		parse_with_list "$2"
		shift 2
		;;
	--packages=*)
		IFS=',' read -r -a PROFILE_PACKAGES <<<"${1#--packages=}"
		shift
		;;
	--packages)
		[[ $# -ge 2 ]] || {
			echo "Error: --packages requires an argument" >&2
			exit 1
		}
		IFS=',' read -r -a PROFILE_PACKAGES <<<"$2"
		shift 2
		;;
	--profile=*)
		DOTS_SETUP_PROFILE="${1#--profile=}"
		PROFILE_NAME="${DOTS_SETUP_PROFILE}"
		shift
		;;
	--profile)
		[[ $# -ge 2 ]] || {
			echo "Error: --profile requires an argument" >&2
			exit 1
		}
		DOTS_SETUP_PROFILE="$2"
		PROFILE_NAME="$2"
		shift 2
		;;
	*)
		echo "Error: unknown argument: $1" >&2
		usage >&2
		exit 1
		;;
	esac
done

uniq_components

backup_stamp() { date +%Y-%m-%d_%H%M%S; }
ensure_dir() {
	if [[ ${DRY_RUN} -eq 1 ]]; then
		echo "[dry-run] mkdir -p $1"
	else
		mkdir -p "$1"
	fi
}

run_cmd() {
	if [[ ${DRY_RUN} -eq 1 ]]; then
		echo "[dry-run] $*"
	else
		"$@"
	fi
}

move_sym() {
	local name="$1"
	local dest="$2"
	local source="${3:-${SYM_DIR}/${name}}"

	if [[ ! -e ${source} ]]; then
		echo "Skip: missing source ${source}"
		return 0
	fi

	ensure_dir "$(dirname "${dest}")"

	if [[ -L ${dest} ]] && [[ "$(readlink "${dest}")" == "${source}" ]]; then
		echo "OK: ${dest}"
		return 0
	fi

	if [[ -e ${dest} ]] || [[ -L ${dest} ]]; then
		# Safety: never replace an unmanaged target unless pre-link backup ran
		# (or dry-run). Fresh installs / already-correct links are fine.
		if [[ ${DRY_RUN} -eq 0 ]] && [[ -z ${DOTS_LAST_BACKUP_ID:-} ]]; then
			# Allow replace only when dest is already a DOTS symlink (stale retarget)
			local cur_link=""
			if [[ -L ${dest} ]]; then
				cur_link="$(readlink "${dest}" 2>/dev/null || true)"
			fi
			case "${cur_link}" in
			"${DIR}" | "${DIR}"/* | "${SYM_DIR}" | "${SYM_DIR}"/*) ;;
			*)
				if [[ -e ${dest} || -L ${dest} ]]; then
					# Unmanaged collision without backup id — abort rather than destroy
					echo "Error: refuse to replace ${dest} without a successful pre-change backup" >&2
					return 1
				fi
				;;
			esac
		fi
		if [[ ${DRY_RUN} -eq 1 ]]; then
			echo "[dry-run] replace ${dest} (pre-change snapshot covers managed targets)"
		else
			echo "Replace ${dest}"
			rm -rf "${dest}"
		fi
	fi

	if [[ ${DRY_RUN} -eq 1 ]]; then
		echo "[dry-run] link ${source} → ${dest}"
	else
		echo "Linked: ${source} → ${dest}"
		ln -s "${source}" "${dest}"
	fi
}

clone_if_missing() {
	local url="$1" dest="$2" label="${3:-$(basename "$2")}"
	if [[ -d "${dest}/.git" ]] || [[ -e "${dest}/oh-my-zsh.sh" ]] || [[ -e "${dest}/tpm" ]]; then
		echo "OK: ${label}"
		return 0
	fi
	if [[ -d ${dest} ]] && [[ -n "$(ls -A "${dest}" 2>/dev/null || true)" ]]; then
		echo "OK: ${label} (present)"
		return 0
	fi
	echo "Cloning ${label}..."
	run_cmd git clone --depth 1 "${url}" "${dest}"
}

echo "=== dots setup ==="
[[ ${DRY_RUN} -eq 1 ]] && echo "(dry-run mode — no mutations)"
[[ ${NO_INSTALL} -eq 1 ]] && echo "(--no-install — will not provision missing packages)"
if [[ ${#DOTS_WITH_COMPONENTS[@]} -gt 0 ]]; then
	echo "Optional components: ${DOTS_WITH_COMPONENTS[*]}"
else
	echo "Optional components: (none — AI tooling not installed by default)"
fi

# Stage 0: shared prerequisite layer (CLT / Homebrew / Python / native pkg mgr)
if [[ ${DRY_RUN} -eq 1 ]]; then
	dots_stage0_ensure 1 || true
elif [[ ${NO_INSTALL} -eq 1 ]]; then
	dots_stage0_report
	if [[ "$(uname -s)" == "Darwin" ]] && ! dots_find_brew >/dev/null 2>&1; then
		echo "Error: Homebrew missing (--no-install)" >&2
		exit 1
	fi
	if ! dots_stage0_python_present; then
		echo "Error: Python >=3.11 missing (--no-install)" >&2
		exit 1
	fi
	dots_activate_brew 2>/dev/null || true
else
	dots_stage0_ensure 0 || exit 1
fi

echo "=== Backup (before any config / symlink mutation) ==="
# HARD REQUIREMENT: snapshot unmanaged collisions, then abort on failure.
# Order: backup → core packages → optional packages → configure → link/relink.
if declare -F dots_backup_snapshot_collisions >/dev/null 2>&1; then
	if ! dots_backup_snapshot_collisions "pre-setup" "pre-setup"; then
		echo "Error: backup failed; setup aborted before package/config mutation" >&2
		exit 1
	fi
else
	echo "Error: backup helper missing; refusing to mutate configuration" >&2
	exit 1
fi

echo "=== Packages (core / profile groups — after backup, before config) ==="
if declare -F _dots_leaf_retire_conflicting_brew_leaf >/dev/null 2>&1; then
	_dots_leaf_retire_conflicting_brew_leaf
fi
if [[ ${NO_INSTALL:-0} -eq 1 ]]; then
	echo "Skipping package install (--no-install)"
else
	if ! dots_provision_packages; then
		echo "Error: package provisioning failed" >&2
		exit 1
	fi
fi

echo "=== Optional component packages (before configuration / links) ==="
# Optional AI/component Brewfiles (explicit --with only) + non-brew Herdr.
# Must run before symlink/config mutation so package failure aborts cleanly.
if [[ ${NO_INSTALL:-0} -eq 1 ]]; then
	echo "Skipping optional packages (--no-install)"
elif command -v brew >/dev/null 2>&1 || [[ -n ${DOTS_BREW_BIN:-} ]]; then
	brew_failed=0
	OPTIONAL_COMPONENT_FAILURES=()
	apply_brewfile() {
		local file="$1"
		if declare -F dots_apply_brewfile_packages >/dev/null 2>&1; then
			dots_apply_brewfile_packages "${file}" "$(basename "${file}")"
			return $?
		fi
		if [[ ! -f ${file} ]]; then
			echo "Warn: missing ${file}"
			return 0
		fi
		echo "brew bundle --file=${file}"
		if [[ ${DRY_RUN} -eq 1 ]]; then
			echo "[dry-run] would apply (file listing only; brew not invoked):"
			sed -n '1,200p' "${file}"
			return 0
		fi
		if ! brew bundle --file="${file}"; then
			echo "Warn: brew bundle failed for ${file}"
			return 1
		fi
		return 0
	}
	apply_optional_brewfiles
	if [[ ${brew_failed} -ne 0 ]]; then
		if declare -F dots_optional_print_failures >/dev/null 2>&1; then
			dots_optional_print_failures
		fi
		echo "Error: one or more optional components failed (see list above)" >&2
		exit 1
	fi
elif has_component herdr || has_component lsp || has_component ai-server; then
	# Linux native path: official Herdr installer (no Homebrew required)
	if has_component herdr && [[ ${NO_INSTALL:-0} -eq 1 ]]; then
		if ! command -v herdr >/dev/null 2>&1; then
			echo "Error: herdr missing (--no-install)" >&2
			exit 1
		fi
	elif has_component herdr; then
		dots_ensure_herdr || exit 1
	fi
fi

if has_component lsp; then
	echo "=== Language servers ==="
	if [[ ${NO_INSTALL:-0} -eq 1 ]]; then
		dots_lsp_check || {
			echo "Error: required language servers missing (--no-install)" >&2
			exit 1
		}
	else
		dots_lsp_install || exit 1
	fi
fi

if has_component ai-server; then
	dots_ai_server_setup || exit 1
fi

echo "=== Symlinks / configuration ==="
# Declarative authority: configs/links.toml (targets already snapshotted above)
dots_deploy_links

# Herdr: merge, not link
if has_component herdr && [[ -f "${DIR}/configs/herdr/config.toml" ]]; then
	sync_herdr_config
fi

# Neovim Lua config (authoritative; replaces legacy init.vim deploy)
dots_deploy_nvim

# Ranger executable bit
if [[ ${DRY_RUN} -eq 0 ]] && [[ -f "${HOME}/.config/ranger/scope.sh" ]]; then
	chmod +x "${HOME}/.config/ranger/scope.sh" || true
fi

echo "=== Oh My Zsh ==="
if [[ ! -f "${ZSH}/oh-my-zsh.sh" ]]; then
	clone_if_missing "https://github.com/ohmyzsh/ohmyzsh.git" "${ZSH}" "oh-my-zsh"
else
	echo "OK: oh-my-zsh"
fi
ensure_dir "${ZSH_CUSTOM}/plugins"
install_zsh_plugin() {
	local repo="$1" name="$2"
	clone_if_missing "https://github.com/${repo}.git" "${ZSH_CUSTOM}/plugins/${name}" "${name}"
}
install_zsh_plugin "zsh-users/zsh-autosuggestions" "zsh-autosuggestions"
install_zsh_plugin "zsh-users/zsh-syntax-highlighting" "zsh-syntax-highlighting"
install_zsh_plugin "zsh-users/zsh-history-substring-search" "zsh-history-substring-search"

echo "=== Vundle ==="
if [[ ! -d ${VUNDLE_DIR} ]]; then
	run_cmd git clone https://github.com/VundleVim/Vundle.vim.git "${VUNDLE_DIR}"
	if [[ ${DRY_RUN} -eq 0 ]] && command -v vim >/dev/null 2>&1; then
		vim +PluginInstall +qall || true
	fi
else
	echo "OK: Vundle"
fi

echo "=== tmux TPM ==="
clone_if_missing "https://github.com/tmux-plugins/tpm" "${TMUX_PLUGIN_DIR}" "tpm"
if [[ ${DRY_RUN} -eq 0 ]] && [[ -x "${TMUX_PLUGIN_DIR}/bin/install_plugins" ]]; then
	"${TMUX_PLUGIN_DIR}/bin/install_plugins" || echo "Warn: TPM plugin install reported errors"
elif [[ ${DRY_RUN} -eq 1 ]]; then
	echo "[dry-run] TPM install_plugins"
fi

echo "=== Optional component configuration ==="
if declare -F dots_optional_configure >/dev/null 2>&1; then
	dots_optional_configure
fi

# fnm default Node (after Brewfile so fnm exists)
dots_setup_fnm_node

# Retire Hermes-owned ~/.local/bin shims that shadow fnm / brew hermes
dots_path_hygiene

# Generic notify helper + Hermes completion hooks
dots_deploy_notify

# Private local agent telemetry (base harness — not a provider)
dots_deploy_telemetry

# Agent skills (npx skills add …) — after fnm Node is available
dots_install_requested_agent_skills || exit 1

# Hermes PATH ambiguity warning (never delete old install)
dots_check_hermes_path

# Herdr integrations (only for agents co-selected with herdr this run)
dots_ensure_herdr_integrations

# Draw Things image tool bridge (optional)
dots_setup_drawthings || exit 1

# OpenCode local coding adapter (optional)
dots_setup_opencode || exit 1

# Codex frontier coding (optional; Hermes MCP only if hermes co-selected)
dots_setup_codex || exit 1

# Cursor Agent CLI (optional — NEVER touch ~/.cursor unless selected)
dots_setup_cursor || exit 1

# Explicit routing skill (when any AI stack component requested)
dots_setup_agent_router || exit 1

# Re-link DOTS launchers (img, notify, agent-stats, …) every run so new
# scripts land on PATH without requiring another --with pass.
dots_ensure_launchers

# leaf markdown viewer + shell completions (zsh/bash/fish; any host)
dots_setup_leaf || echo "Warn: leaf setup reported errors (optional)"

# rsync: required in core — fail closed
if ! dots_ensure_rsync; then
	echo "Error: rsync setup failed (required)" >&2
	exit 1
fi

# bat theme cache (Catppuccin) if theme files present
if command -v bat >/dev/null 2>&1 && [[ -d "${DIR}/configs/bat/themes" ]]; then
	echo "=== bat theme cache ==="
	ensure_dir "${HOME}/.config/bat/themes"
	if [[ ${DRY_RUN} -eq 0 ]]; then
		# Link theme files if needed
		for t in "${DIR}/configs/bat/themes"/*.tmTheme; do
			[[ -f ${t} ]] || continue
			bn="$(basename "${t}")"
			dest="${HOME}/.config/bat/themes/${bn}"
			if [[ ! -e ${dest} ]]; then
				ln -s "${t}" "${dest}"
			fi
		done
		bat cache --build >/dev/null 2>&1 || echo "Warn: bat cache --build failed"
	else
		echo "[dry-run] bat cache --build"
	fi
fi

# Conservative Atuin local config if atuin exists and config missing
if command -v atuin >/dev/null 2>&1; then
	ensure_dir "${HOME}/.config/atuin"
	if [[ ! -f "${HOME}/.config/atuin/config.toml" ]]; then
		if [[ ${DRY_RUN} -eq 1 ]]; then
			echo "[dry-run] create local-only Atuin config"
		else
			cat >"${HOME}/.config/atuin/config.toml" <<'EOF'
## dots setup — local-first (no cloud sync required)
auto_sync = false
update_check = false
style = "compact"
search_mode = "fuzzy"
filter_mode = "global"
inline_height = 20
EOF
			echo "Created local-only Atuin config"
		fi
	fi
fi

# Git shared config + identity templates (never overwrite identity)
dots_setup_git_config

# Legacy alias helper (additive)
ensure_dir "${SECRETS_DIR:-${DIR}/.secrets}"
if [[ -f "${DIR}/helpers/git_alias_setup.sh" ]] && [[ ${DRY_RUN} -eq 0 ]]; then
	# shellcheck disable=SC1091
	source "${DIR}/helpers/git_alias_setup.sh" || true
fi

cat <<EOF

Finished installing dots$([ "${DRY_RUN}" -eq 1 ] && echo ' (dry-run)').

Core: ~/.bashrc ~/.zshrc ~/.zprofile ~/.zshenv ~/.vimrc ~/.tmux.conf ~/.npmrc
Launchers: ~/.local/bin (img, notify, agent-stats, *-mcp when configured)
Starship: ~/.config/starship.toml (Catppuccin Mocha)
Neovim: ~/.config/nvim (lazy.nvim; EDITOR/VISUAL=nvim)
Node: fnm + configs/node/default.toml (not nvm)
Notify: ~/.local/bin/notify  (smoke: ./scripts/notify-smoke.sh)
Leaf:   leaf (markdown viewer) + completions in ~/.local/share/leaf/completions
Ranger: ~/.config/ranger/{rc.conf,rifle.conf,scope.sh,colorschemes/catppuccin.py}

Optional --with: ${DOTS_WITH_COMPONENTS[*]:-none}

Consent: binary presence ≠ configuration authorization (see helpers/ai_consent.sh).
Onboarding: ./bootstrap.sh --profile {base,home,work,server}
EOF

if has_component herdr; then
	echo "Herdr: ~/.config/herdr/config.toml (merged [theme]/[keys]/ui.tab_bar_right)"
	echo "  Integrations only for co-selected agents (hermes/opencode/codex/cursor)."
fi
if has_component skills || has_component ai-skills || has_component archify; then
	cat <<'EOF'
Agent skills:
  --with archify → Archify only
  --with skills → engineering pack (includes Archify)
  --with ai-skills → AI/agent harness pack
  --with skills,ai-skills → union (deduped)
  Global store: ~/.agents/skills/
  Hermes links: only when hermes is also selected
  Update (opt-in): ./scripts/update-skills.sh
EOF
fi
if has_component drawthings; then
	cat <<'EOF'
Draw Things: CLI + MCP launcher + img helpers.
  Launchers: ~/.local/bin/drawthings-mcp  ~/.local/bin/img
  Config: ~/.config/drawthings-mcp/config.toml → ~/Pictures/AI/DrawThings/
  Client MCP only when hermes/cursor co-selected.
EOF
fi
if has_component opencode; then
	cat <<'EOF'
OpenCode: ~/.local/bin/opencode-agent  ~/.local/bin/opencode-mcp
  Config: ~/.config/dots/agents/execution.toml
EOF
fi
if has_component codex; then
	cat <<'EOF'
Codex: Homebrew cask; auth in ~/.codex/ (not copied). Hermes MCP only if hermes co-selected.
EOF
fi
if has_component cursor; then
	cat <<'EOF'
Cursor: Homebrew cask cursor-cli → agent / cursor-agent.
  Config: ~/.cursor/cli-config.json + mcp.json (merge; no tokens).
  Draw Things MCP only with --with cursor,drawthings. Auth: interactive agent login.
EOF
fi
if has_component images; then
	echo "Images toolkit: Magick/gs/rsvg/exiftool/pngquant/webp/oxipng (deterministic)."
fi
if has_component tex; then
	echo "TeX: Homebrew texlive. Validate: pdflatex --version; kpsewhich article.cls"
fi
if has_component mactools; then
	cat <<'EOF'
mactools: Vorssaint + Raycast/KM/Hazel/Little Snitch/OrbStack/Hookmark/DEVONthink/
  Ghostty/Zed + audio/PFL tools + mise/yazi/CLI utilities (Brewfile.mactools).
  Portable configs: ~/.config/{ghostty,yazi,mise,lazygit}
  Manual: licenses, macOS permissions, BlackHole reboot — see docs/MACTOOLS.md
  Export helpers: ./scripts/mactools/export-configs.sh all
  OrbStack playbook: docs/ORBSTACK_MIGRATION.md (no auto-migrate)
  mise analysis: docs/MISE_MIGRATION.md (no cutover)
EOF
fi
if agent_router_should_install 2>/dev/null; then
	cat <<'EOF'
Agent router: skills/agent-router → ~/.agents/skills/agent-router
  Explicit policy; Cursor only on "use Cursor". Tests: ./scripts/router_policy_test.sh
EOF
fi

cat <<'EOF'

No autonomous multi-agent loops. Callers follow readable routing rules.

Multiplexer: DOTS_MULTIPLEXER=tmux|herdr|none (default tmux); DOTS_AUTO_TMUX=0 disables.
Prefixes: tmux=Ctrl-Space  herdr=Ctrl-A

iTerm font (manual): JetBrainsMono Nerd Font → Profiles → Text → Font.

See README.md for details.
EOF
