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
DOTS_WITH_COMPONENTS=()

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
# shellcheck source=helpers/links.sh
source "${DIR}/helpers/links.sh"
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
  cat <<'EOF'
Usage: ./setup.sh [options]

Install / refresh dotfiles (idempotent). Safe to re-run.

Options:
  --with <list>     Comma-separated optional components. Supported:
                      herdr      — terminal multiplexer (Brewfile.herdr)
                      hermes     — Hermes agent CLI (+ macOS hermes-desktop)
                      ollama     — local LLM runtime (no models pulled)
                      archify    — agent skill: architecture / workflow /
                                   sequence / data-flow / lifecycle diagrams
                                   (requires Node via fnm; Brewfile.archify)
                      skills     — curated Engineering Pack (manifest
                                   + security-review + Archify + magnus919 set)
                      ai-skills  — curated AI/agent harness skill pack
                                   (evals, litellm, ml-engineering, …)
                      drawthings — Draw Things image tool bridge (CLI + MCP
                                   launchers; GUI app must already be installed)
                      opencode   — local/general coding adapter (+ Hermes MCP
                                   only if hermes also selected)
                      codex      — frontier coding via Homebrew cask Codex
                                   (+ Hermes MCP only if hermes also selected)
                      cursor     — Cursor Agent CLI (Homebrew cask cursor-cli;
                                   configures ~/.cursor ONLY when selected)
                      images     — deterministic image toolkit (Magick, etc.;
                                   not generative — see drawthings)
                      tex        — Homebrew TeX Live (CLI LaTeX)
  --with=<list>     Same as --with <list>
  --dry-run         Preview actions without modifying the machine
  -h, --help        Show this help

Consent vs presence:
  A binary already on PATH does NOT authorize DOTS to configure it.
  AI client config runs only for components listed in --with this run.
  Prefer ./bootstrap.sh --profile {base,home,work,all|path.toml} for onboarding.
  Edit profiles with ./configure.sh (writes TOML only).

Examples:
  ./setup.sh
  ./setup.sh --with herdr
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
  ./setup.sh --dry-run --with ai-skills
  ./bootstrap.sh --profile home
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
  IFS=',' read -r -a _parts <<<"${raw}"
  for item in "${_parts[@]}"; do
    item="$(echo "${item}" | tr -d '[:space:]')"
    [[ -z "${item}" ]] && continue
    local ok=0 s
    for s in "${SUPPORTED_WITH[@]}"; do
      if [[ "${item}" == "${s}" ]]; then
        ok=1
        break
      fi
    done
    if [[ "${ok}" -ne 1 ]]; then
      echo "Error: unknown --with component '${item}'" >&2
      echo "Supported: ${SUPPORTED_WITH[*]}" >&2
      exit 1
    fi
    DOTS_WITH_COMPONENTS+=("${item}")
  done
}

# Deduplicate while preserving order
uniq_components() {
  local seen="|" c out=()
  for c in "${DOTS_WITH_COMPONENTS[@]}"; do
    case "${seen}" in
      *"|${c}|"*) ;;
      *)
        out+=("${c}")
        seen="${seen}${c}|"
        ;;
    esac
  done
  DOTS_WITH_COMPONENTS=("${out[@]}")
}

has_component() {
  local want="$1" c
  for c in "${DOTS_WITH_COMPONENTS[@]+"${DOTS_WITH_COMPONENTS[@]}"}"; do
    [[ "${c}" == "${want}" ]] && return 0
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --with=*)
      parse_with_list "${1#--with=}"
      shift
      ;;
    --with)
      [[ $# -ge 2 ]] || { echo "Error: --with requires an argument" >&2; exit 1; }
      parse_with_list "$2"
      shift 2
      ;;
    --packages=*)
      IFS=',' read -r -a PROFILE_PACKAGES <<<"${1#--packages=}"
      shift
      ;;
    --packages)
      [[ $# -ge 2 ]] || { echo "Error: --packages requires an argument" >&2; exit 1; }
      IFS=',' read -r -a PROFILE_PACKAGES <<<"$2"
      shift 2
      ;;
    --profile=*)
      DOTS_SETUP_PROFILE="${1#--profile=}"
      PROFILE_NAME="${DOTS_SETUP_PROFILE}"
      shift
      ;;
    --profile)
      [[ $# -ge 2 ]] || { echo "Error: --profile requires an argument" >&2; exit 1; }
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
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] mkdir -p $1"
  else
    mkdir -p "$1"
  fi
}

run_cmd() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

move_sym() {
  local name="$1"
  local dest="$2"
  local source="${3:-${SYM_DIR}/${name}}"
  local backup

  if [[ ! -e "${source}" ]]; then
    echo "Skip: missing source ${source}"
    return 0
  fi

  ensure_dir "$(dirname "${dest}")"
  ensure_dir "${OLD_DOTS}"
  backup="${OLD_DOTS}/${name}_$(backup_stamp)"

  if [[ -L "${dest}" ]] && [[ "$(readlink "${dest}")" == "${source}" ]]; then
    echo "OK: ${dest}"
    return 0
  fi

  if [[ -e "${dest}" ]] || [[ -L "${dest}" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] backup ${dest} → ${backup}"
    else
      echo "Backup ${dest} → ${backup}"
      mv "${dest}" "${backup}"
    fi
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
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
  if [[ -d "${dest}" ]] && [[ -n "$(ls -A "${dest}" 2>/dev/null || true)" ]]; then
    echo "OK: ${label} (present)"
    return 0
  fi
  echo "Cloning ${label}..."
  run_cmd git clone --depth 1 "${url}" "${dest}"
}

echo "=== dots setup ==="
[[ "${DRY_RUN}" -eq 1 ]] && echo "(dry-run mode — no mutations)"
if [[ ${#DOTS_WITH_COMPONENTS[@]} -gt 0 ]]; then
  echo "Optional components: ${DOTS_WITH_COMPONENTS[*]}"
else
  echo "Optional components: (none — AI tooling not installed by default)"
fi

echo "=== Symlinks ==="
# Declarative authority: configs/links.toml
dots_deploy_links

# Herdr: merge, not link
if has_component herdr && [[ -f "${DIR}/configs/herdr/config.toml" ]]; then
  sync_herdr_config
fi

# Neovim Lua config (authoritative; replaces legacy init.vim deploy)
dots_deploy_nvim

# Ranger executable bit
if [[ "${DRY_RUN}" -eq 0 ]] && [[ -f "${HOME}/.config/ranger/scope.sh" ]]; then
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
if [[ ! -d "${VUNDLE_DIR}" ]]; then
  run_cmd git clone https://github.com/VundleVim/Vundle.vim.git "${VUNDLE_DIR}"
  if [[ "${DRY_RUN}" -eq 0 ]] && command -v vim >/dev/null 2>&1; then
    vim +PluginInstall +qall || true
  fi
else
  echo "OK: Vundle"
fi

echo "=== tmux TPM ==="
clone_if_missing "https://github.com/tmux-plugins/tpm" "${TMUX_PLUGIN_DIR}" "tpm"
if [[ "${DRY_RUN}" -eq 0 ]] && [[ -x "${TMUX_PLUGIN_DIR}/bin/install_plugins" ]]; then
  "${TMUX_PLUGIN_DIR}/bin/install_plugins" || echo "Warn: TPM plugin install reported errors"
elif [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "[dry-run] TPM install_plugins"
fi

echo "=== Packages ==="
# leaf-markdown-viewer conflicts with deprecated formula `leaf` (reloader)
if declare -F _dots_leaf_retire_conflicting_brew_leaf >/dev/null 2>&1; then
  _dots_leaf_retire_conflicting_brew_leaf
fi

# Profile-aware groups (brew/groups/*.Brewfile or Linux native maps)
if ! dots_provision_packages; then
  echo "Error: package provisioning failed" >&2
  exit 1
fi

# Optional AI/component Brewfiles (explicit --with only)
if command -v brew >/dev/null 2>&1; then
  brew_failed=0
  apply_brewfile() {
    local file="$1"
    if [[ ! -f "${file}" ]]; then
      echo "Warn: missing ${file}"
      return 0
    fi
    echo "brew bundle --file=${file}"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] would apply:"
      brew bundle list --file="${file}" 2>/dev/null || cat "${file}"
      return 0
    fi
    if ! brew bundle --file="${file}"; then
      brew_failed=1
      echo "Warn: brew bundle failed for ${file}"
    fi
  }
  apply_optional_brewfiles
  if [[ "${brew_failed}" -ne 0 ]]; then
    echo "Error: optional component Brewfile(s) failed" >&2
    exit 1
  fi
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
dots_setup_leaf || echo "Warn: leaf setup reported errors"

# rsync: Homebrew on macOS/Linuxbrew; native packages on Linux without brew
dots_ensure_rsync || echo "Warn: rsync setup reported errors"

# bat theme cache (Catppuccin) if theme files present
if command -v bat >/dev/null 2>&1 && [[ -d "${DIR}/configs/bat/themes" ]]; then
  echo "=== bat theme cache ==="
  ensure_dir "${HOME}/.config/bat/themes"
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    # Link theme files if needed
    for t in "${DIR}/configs/bat/themes"/*.tmTheme; do
      [[ -f "${t}" ]] || continue
      bn="$(basename "${t}")"
      dest="${HOME}/.config/bat/themes/${bn}"
      if [[ ! -e "${dest}" ]]; then
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
    if [[ "${DRY_RUN}" -eq 1 ]]; then
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
if [[ -f "${DIR}/helpers/git_alias_setup.sh" ]] && [[ "${DRY_RUN}" -eq 0 ]]; then
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
