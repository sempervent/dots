#!/usr/bin/env bash
# Health check for sempervent/dots — profile-aware ERROR / WARN / INFO.
#
# Usage:
#   ./scripts/check.sh
#   ./scripts/check.sh --profile server
#   ./scripts/check.sh --profile home
#
# Exit nonzero only when ERROR (fail) count > 0. Warnings never fail the run.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASSED=0; FAILED=0; WARNINGS=0

# Resolve repo root from this script (do not assume ~/dots).
_CHECK_SRC="${BASH_SOURCE[0]}"
DOTS_DIR="${DOTS_DIR:-$(cd "$(dirname "${_CHECK_SRC}")/.." && pwd)}"
DIR="${DOTS_DIR}"
SYM_DIR="${DOTS_DIR}/syms"
CONFIG_DIR="${DOTS_DIR}/configs"
CHECK_PROFILE="${DOTS_PROFILE:-}"
PROFILE_NAME=""
PROFILE_PACKAGES=()
EFFECTIVE_WITH=()

# shellcheck source=../helpers/toml.sh
source "${DOTS_DIR}/helpers/toml.sh"
# shellcheck source=../helpers/components.sh
source "${DOTS_DIR}/helpers/components.sh"
# shellcheck source=../helpers/profiles.sh
source "${DOTS_DIR}/helpers/profiles.sh"
# shellcheck source=../helpers/packages.sh
source "${DOTS_DIR}/helpers/packages.sh"

ok() { echo -e "${GREEN}✓${NC} $1"; PASSED=$((PASSED + 1)); }
warn() { echo -e "${YELLOW}⚠${NC} $1"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo -e "${RED}✗${NC} $1"; FAILED=$((FAILED + 1)); }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

profile_has_group() {
  local g="$1" x
  for x in "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; do
    [[ "${x}" == "${g}" ]] && return 0
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) CHECK_PROFILE="${2:-}"; shift 2 ;;
    --profile=*) CHECK_PROFILE="${1#*=}"; shift ;;
    -h|--help)
      echo "Usage: $0 [--profile base|home|work|server|all|current|/path/to/profile.toml]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${CHECK_PROFILE}" && -f "${HOME}/.config/dots/active-profile" ]]; then
  # shellcheck disable=SC1090
  source "${HOME}/.config/dots/active-profile"
  CHECK_PROFILE="${DOTS_PROFILE:-base}"
fi
CHECK_PROFILE="${CHECK_PROFILE:-base}"

if PROFILE_FILE="$(dots_resolve_profile_path "${CHECK_PROFILE}" 2>/dev/null)"; then
  CLI_WITH=(); CLI_WITHOUT=()
  dots_load_profile_file "${PROFILE_FILE}" >/dev/null
  dots_compute_effective_with >/dev/null || true
else
  PROFILE_NAME="${CHECK_PROFILE}"
  case "${CHECK_PROFILE}" in
    server) PROFILE_PACKAGES=(core modern server) ;;
    work) PROFILE_PACKAGES=(core modern workstation) ;;
    home|all) PROFILE_PACKAGES=(core modern workstation infra media gui) ;;
    *) PROFILE_PACKAGES=(core modern) ;;
  esac
fi

echo -e "${BLUE}dotfiles health check${NC} (profile=${PROFILE_NAME:-${CHECK_PROFILE}})\n"

check_symlink() {
  local target="$1" source="$2" name="$3"
  if [[ ! -e "${target}" ]]; then
    fail "${name}: missing ${target}"
  elif [[ ! -L "${target}" ]]; then
    warn "${name}: ${target} exists but is not a symlink"
  elif [[ "$(readlink "${target}")" != "${source}" ]] && [[ "$(realpath "${target}" 2>/dev/null || true)" != "$(realpath "${source}" 2>/dev/null || true)" ]]; then
    # Accept either exact link text or same realpath
    if [[ "$(realpath "${target}" 2>/dev/null || echo x)" == "$(realpath "${source}" 2>/dev/null || echo y)" ]]; then
      ok "${name}"
    else
      fail "${name}: wrong target ($(readlink "${target}"))"
    fi
  else
    ok "${name}"
  fi
}

echo -e "${BLUE}Core layout${NC}"
[[ -f "${DOTS_DIR}/brew/Brewfile" ]] && ok "Brewfile present" || fail "Brewfile missing"
[[ -d "${DOTS_DIR}/brew/groups" ]] && ok "brew/groups present" || fail "brew/groups missing"
[[ ! -e "${DOTS_DIR}/brew/packages.txt" ]] && ok "packages.txt absent" || fail "packages.txt still present (should be removed)"
[[ -d "${DOTS_DIR}/shell" ]] && ok "shell/ present" || fail "shell/ missing"
[[ -d "${DOTS_DIR}/zsh" ]] && ok "zsh/ present" || fail "zsh/ missing"
[[ -f "${DOTS_DIR}/configs/links.toml" ]] && ok "links.toml present" || fail "links.toml missing"
[[ -f "${DOTS_DIR}/configs/components.toml" ]] && ok "components.toml present" || fail "components.toml missing"
[[ ! -e "${DOTS_DIR}/tools/toml_min.py" ]] && ok "toml_min.py removed (tomllib-only)" || fail "toml_min.py still present (unsupported)"

echo -e "\n${BLUE}Symlinks${NC}"
check_symlink "${HOME}/.bashrc" "${SYM_DIR}/bashrc" "bashrc"
check_symlink "${HOME}/.zshrc" "${SYM_DIR}/zshrc" "zshrc"
check_symlink "${HOME}/.zprofile" "${SYM_DIR}/zprofile" "zprofile"
check_symlink "${HOME}/.tmux.conf" "${SYM_DIR}/tmux.conf" "tmux.conf"
check_symlink "${HOME}/.vimrc" "${SYM_DIR}/vimrc" "vimrc"

echo -e "\n${BLUE}Broken symlink scan (home configs)${NC}"
broken=0
for p in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.zprofile" "${HOME}/.tmux.conf" \
         "${HOME}/.config/ranger/rc.conf" "${HOME}/.config/herdr/config.toml" \
         "${HOME}/.config/bat/config"; do
  if [[ -L "${p}" ]] && [[ ! -e "${p}" ]]; then
    fail "broken symlink: ${p}"
    broken=1
  fi
done
[[ "${broken}" -eq 0 ]] && ok "no broken core config symlinks"

echo -e "\n${BLUE}Shell${NC}"
if bash -n "${SYM_DIR}/bashrc" 2>/dev/null; then ok "bashrc syntax"; else fail "bashrc syntax"; fi
if zsh -n "${SYM_DIR}/zshrc" 2>/dev/null; then ok "zshrc syntax"; else fail "zshrc syntax"; fi
if zsh -n "${SYM_DIR}/zprofile" 2>/dev/null; then ok "zprofile syntax"; else fail "zprofile syntax"; fi

# Required CLI tools for selected package groups (profile-aware)
echo -e "\n${BLUE}Required tools (profile groups)${NC}"
DOTS_RESOLVED_GROUPS=("${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}")
if [[ ${#DOTS_RESOLVED_GROUPS[@]} -eq 0 ]]; then
  dots_resolve_package_groups || true
fi
while IFS= read -r _tool; do
  [[ -z "${_tool}" ]] && continue
  _cmd="${_tool}"
  case "${_tool}" in
    ripgrep) _cmd=rg ;;
    fd) _cmd=fd; command -v fd >/dev/null 2>&1 || _cmd=fdfind ;;
    neovim) _cmd=nvim ;;
    bat) _cmd=bat; command -v bat >/dev/null 2>&1 || _cmd=batcat ;;
    git-delta) _cmd=delta ;;
    font-jetbrains-mono-nerd-font) continue ;;
    terminal-notifier)
      if [[ "$(uname -s)" != "Darwin" ]]; then
        info "terminal-notifier not applicable on $(uname -s)"
        continue
      fi
      ;;
    docker-compose) _cmd=docker ;;
  esac
  if command -v "${_cmd}" >/dev/null 2>&1; then
    ok "required ${_tool}"
  else
    fail "required tool missing: ${_tool}"
  fi
done < <(dots_tools_for_groups required 2>/dev/null || true)

while IFS= read -r _tool; do
  [[ -z "${_tool}" ]] && continue
  _cmd="${_tool}"
  case "${_tool}" in
    ripgrep) _cmd=rg ;;
    fd) _cmd=fd; command -v fd >/dev/null 2>&1 || _cmd=fdfind ;;
    neovim) _cmd=nvim ;;
    bat) _cmd=bat; command -v bat >/dev/null 2>&1 || _cmd=batcat ;;
    git-delta) _cmd=delta ;;
    font-jetbrains-mono-nerd-font) continue ;;
    terminal-notifier)
      [[ "$(uname -s)" != "Darwin" ]] && continue
      ;;
  esac
  if command -v "${_cmd}" >/dev/null 2>&1; then
    ok "optional ${_tool}"
  else
    warn "optional tool missing: ${_tool}"
  fi
done < <(dots_tools_for_groups optional 2>/dev/null || true)
echo -e "\n${BLUE}Node / fnm${NC}"
if command -v fnm >/dev/null 2>&1; then
  ok "fnm $(fnm --version 2>/dev/null | head -1)"
else
  warn "fnm missing (optional per package policy; install via brew/curl when needed)"
fi
if command -v node >/dev/null 2>&1; then
  ok "node $(node --version 2>/dev/null) @ $(command -v node)"
  case "$(command -v node)" in
    *fnm_multishells*|*fnm*)
      ok "node resolves via fnm"
      ;;
    "${HOME}/.local/bin/node")
      fail "node still shadowed by ~/.local/bin/node (run ./setup.sh PATH hygiene)"
      ;;
    *)
      # brew node is acceptable fallback when fnm env not active in this shell
      if [[ "$(command -v node)" == /opt/homebrew/* ]] || [[ "$(command -v node)" == /usr/local/* ]]; then
        ok "node is Homebrew (fnm may not be active in this non-interactive shell)"
      else
        warn "node not clearly fnm-managed ($(command -v node))"
      fi
      ;;
  esac
else
  if command -v fnm >/dev/null 2>&1; then
    warn "node missing (run setup to fnm install default)"
  else
    info "node missing (fnm not provisioned on this host)"
  fi
fi

# NVM must not be auto-activated by DOTS
if bash -ic 'type nvm 2>/dev/null | head -1' 2>/dev/null | rg -q 'nvm is a function|nvm is aliased'; then
  # Only fail if our bashrc still sources nvm
  if rg -q 'nvm\.sh' "${SYM_DIR}/bashrc" 2>/dev/null; then
    fail "bashrc still sources NVM (DOTS policy is fnm-only)"
  else
    warn "nvm function visible in bash (user local config?); DOTS does not source NVM"
  fi
else
  ok "bash does not auto-load NVM via DOTS"
fi
if [[ -d "${HOME}/.nvm" ]]; then
  info "~/.nvm present (left alone; not sourced by DOTS)"
fi
if command -v npm >/dev/null 2>&1; then
  ok "npm $(npm --version 2>/dev/null)"
else
  if command -v fnm >/dev/null 2>&1; then
    warn "npm missing"
  else
    info "npm missing"
  fi
fi
[[ -f "${CONFIG_DIR}/node/default.toml" ]] && ok "node default policy present" || fail "configs/node/default.toml missing"

# Stale Hermes node shims should be retired from ~/.local/bin
if [[ -L "${HOME}/.local/bin/node" ]] && readlink "${HOME}/.local/bin/node" 2>/dev/null | rg -q '\.hermes/node'; then
  fail "~/.local/bin/node still points at Hermes private Node (should be retired)"
else
  ok "no Hermes node shim in ~/.local/bin"
fi

# Non-interactive probe that zsh initializes fnm + starship once
if command -v zsh >/dev/null 2>&1; then
  zsh_probe="$(zsh -ic 'command -v fnm >/dev/null && echo FNM_OK; echo NODE=$(command -v node); command -v starship >/dev/null && echo STARSHIP_OK; [[ -n ${STARSHIP_SHELL:-} ]] && echo STARSHIP_INIT; [[ -n ${ZSH:-} ]] && echo OMZ_OK; typeset -f _dots_fnm_init >/dev/null && echo FNM_FN' 2>/dev/null | tr '\n' ' ')"
  echo "${zsh_probe}" | rg -q 'FNM_OK' && ok "zsh: fnm available in interactive shell" || warn "zsh: fnm not visible (open new shell after setup)"
  echo "${zsh_probe}" | rg -q 'fnm_multishells|NODE=.*/fnm' && ok "zsh: node is fnm-managed" || warn "zsh: node may not be fnm-managed (${zsh_probe})"
  echo "${zsh_probe}" | rg -q 'STARSHIP_OK' && ok "zsh: starship available" || warn "zsh: starship missing"
  echo "${zsh_probe}" | rg -q 'STARSHIP_INIT' && ok "zsh: Starship initialized" || warn "zsh: Starship not initialized (STARSHIP_SHELL unset)"
  echo "${zsh_probe}" | rg -q 'OMZ_OK' && ok "zsh: Oh My Zsh still loads" || warn "zsh: Oh My Zsh not detected"
fi

echo -e "\n${BLUE}Starship / font / editor / notify (default)${NC}"
if command -v starship >/dev/null 2>&1; then
  ok "starship $(starship --version 2>/dev/null | head -1)"
else
  # starship is optional in configs/packages/groups.toml (SKIP on apt)
  warn "starship missing (optional; install via brew or platform package when desired)"
fi
[[ -f "${HOME}/.config/starship.toml" ]] || [[ -L "${HOME}/.config/starship.toml" ]] && ok "starship.toml deployed" || warn "starship.toml not deployed (run setup.sh)"
[[ -f "${CONFIG_DIR}/starship/starship.toml" ]] && ok "starship repo config present" || fail "configs/starship/starship.toml missing"

if command -v nvim >/dev/null 2>&1; then
  ok "nvim $(nvim --version 2>/dev/null | head -1)"
else
  fail "neovim missing (required in core package group)"
fi
if [[ -f "${HOME}/.config/nvim/init.lua" ]]; then
  ok "Neovim init.lua present"
  if nvim --headless "+lua require('lazy')" "+qa" >/dev/null 2>&1; then
    ok "Neovim lazy.nvim loads headlessly"
  else
    warn "Neovim lazy.nvim headless load inconclusive (run nvim once)"
  fi
  # Read-only probe only — do not mutate plugin state during health check
  if nvim --headless \
      "+lua assert(package.loaded['lazy'] ~= nil or true)" \
      "+qa" >/dev/null 2>&1; then
    ok "Neovim headless startup OK"
  else
    warn "Neovim headless startup reported issues"
  fi
else
  warn "Neovim Lua config not deployed (run setup.sh)"
fi

if command -v terminal-notifier >/dev/null 2>&1 || [[ -x /opt/homebrew/bin/terminal-notifier ]]; then
  ok "terminal-notifier available"
else
  if profile_has_group workstation || profile_has_group gui; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
      fail "terminal-notifier missing (workstation/gui profile)"
    else
      info "terminal-notifier skipped (not macOS)"
    fi
  else
    info "terminal-notifier not required for profile ${PROFILE_NAME:-${CHECK_PROFILE}}"
  fi
fi
if [[ -L "${HOME}/.local/bin/notify" ]] || [[ -x "${HOME}/.local/bin/notify" ]]; then
  ok "notify helper present (~/.local/bin/notify)"
else
  warn "notify helper missing (run setup.sh)"
fi

echo -e "\n${BLUE}leaf (markdown viewer)${NC}"
if command -v leaf >/dev/null 2>&1 && leaf -V >/dev/null 2>&1 && leaf --help 2>&1 | grep -q -- '--auto-complete'; then
  ok "leaf markdown viewer: $(leaf -V 2>/dev/null | head -1)"
  if [[ -f "${HOME}/.local/share/leaf/completions/_leaf" ]] \
    && [[ -f "${HOME}/.local/share/leaf/completions/leaf.bash" ]]; then
    ok "leaf completions installed (~/.local/share/leaf/completions)"
  else
    warn "leaf completions missing (re-run ./setup.sh)"
  fi
  if [[ -f "${HOME}/.config/fish/completions/leaf.fish" ]]; then
    ok "leaf fish completion present"
  else
    info "leaf fish completion not present (optional)"
  fi
elif brew list --formula leaf >/dev/null 2>&1; then
  warn "Homebrew leaf (reloader) installed — conflicts with leaf-markdown-viewer; re-run ./setup.sh"
else
  warn "leaf markdown viewer missing (default Brewfile / setup.sh)"
fi

echo -e "\n${BLUE}rsync${NC}"
if command -v rsync >/dev/null 2>&1; then
  rsync_bin="$(command -v rsync)"
  rsync_ver="$(rsync --version 2>/dev/null | head -1 || true)"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if brew list --formula rsync >/dev/null 2>&1 \
      || [[ "${rsync_bin}" == /opt/homebrew/* ]] \
      || [[ "${rsync_bin}" == /usr/local/* ]]; then
      ok "Homebrew rsync: ${rsync_bin} (${rsync_ver})"
    else
      warn "system openrsync only (${rsync_bin}) — prefer: brew install rsync"
    fi
  else
    ok "rsync: ${rsync_bin} (${rsync_ver})"
  fi
else
  fail "rsync missing (macOS: Brewfile; Linux: apt/dnf/pacman/apk install rsync)"
fi

# Font check (macOS) — PASS if files/cask present; INFO if cache may lag GUI apps
info() { echo -e "${BLUE}ℹ${NC} $1"; }

if [[ "$(uname -s)" == "Darwin" ]]; then
  font_files=0
  font_cask=0
  font_listed=0
  if ls "${HOME}/Library/Fonts"/JetBrainsMonoNerdFont*.ttf >/dev/null 2>&1 \
    || ls /Library/Fonts/JetBrainsMonoNerdFont*.ttf >/dev/null 2>&1; then
    font_files=1
  fi
  if brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
    font_cask=1
  fi
  if fc-list 2>/dev/null | rg -qi 'JetBrainsMono.*Nerd|JetBrainsMono Nerd Font'; then
    font_listed=1
  fi

  if [[ "${font_files}" -eq 1 ]] || [[ "${font_cask}" -eq 1 ]]; then
    ok "JetBrainsMono Nerd Font present (cask=${font_cask} files=${font_files})"
    if [[ "${font_listed}" -eq 0 ]]; then
      info "font cache may need app restart for iTerm/GUI to enumerate JetBrainsMono Nerd Font"
    fi
  else
    if profile_has_group gui; then
      fail "JetBrainsMono Nerd Font absent (gui package group)"
    else
      info "Nerd Font not required for profile ${PROFILE_NAME:-${CHECK_PROFILE}}"
    fi
  fi
fi

echo -e "\n${BLUE}Ranger (optional)${NC}"
if command -v ranger >/dev/null 2>&1; then
  ok "ranger installed ($(ranger --version 2>/dev/null | head -1))"
  for f in rc.conf rifle.conf scope.sh; do
    [[ -e "${HOME}/.config/ranger/${f}" ]] && ok "ranger ${f}" || warn "ranger ${f} not deployed (run setup.sh)"
  done
  if [[ -f "${HOME}/.config/ranger/colorschemes/catppuccin.py" ]]; then
    if python3 -m py_compile "${HOME}/.config/ranger/colorschemes/catppuccin.py" 2>/dev/null; then
      ok "ranger catppuccin colorscheme compiles"
    else
      fail "ranger catppuccin colorscheme compile failed"
    fi
  else
    warn "ranger catppuccin colorscheme not deployed"
  fi
  [[ -x "${HOME}/.config/ranger/scope.sh" ]] && ok "scope.sh executable" || warn "scope.sh not executable"
else
  warn "ranger not installed (optional)"
fi

echo -e "\n${BLUE}tmux${NC}"
if command -v tmux >/dev/null 2>&1; then
  ok "tmux $(tmux -V)"
  if rg -q 'prefix C-Space' "${SYM_DIR}/tmux.conf"; then
    ok "tmux prefix C-Space preserved"
  else
    fail "tmux prefix C-Space missing"
  fi
  if rg -q 'catppuccin/tmux' "${SYM_DIR}/tmux.conf"; then
    ok "tmux Catppuccin plugin declared"
  else
    fail "tmux Catppuccin plugin missing"
  fi
  if [[ -f "${HOME}/.tmux/plugins/tmux/catppuccin.tmux" ]] || [[ -d "${HOME}/.tmux/plugins/tmux" ]]; then
    ok "Catppuccin tmux plugin present under ~/.tmux/plugins"
  else
    warn "Catppuccin tmux plugin not installed yet (TPM install_plugins)"
  fi
  if tmux -L "dotscheck$$" -f "${SYM_DIR}/tmux.conf" start-server \; list-commands >/dev/null 2>&1; then
    ok "tmux config loads"
    tmux -L "dotscheck$$" kill-server >/dev/null 2>&1 || true
  else
    tmux -L "dotscheck$$" -f "${SYM_DIR}/tmux.conf" new-session -d -s check 'true' 2>/dev/null && {
      ok "tmux config loads (temp session)"
      tmux -L "dotscheck$$" kill-server >/dev/null 2>&1 || true
    } || warn "tmux config validation inconclusive (plugins may be pending)"
  fi
else
  if [[ "${PROFILE_RUNTIME_MULTIPLEXER:-tmux}" == "tmux" ]] || profile_has_group server; then
    fail "tmux missing (required by resolved profile)"
  else
    warn "tmux not installed"
  fi
fi

echo -e "\n${BLUE}Herdr${NC}"
_herdr_required=0
for _c in "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; do
  [[ "${_c}" == "herdr" ]] && _herdr_required=1 && break
done
[[ "${PROFILE_RUNTIME_MULTIPLEXER:-}" == "herdr" ]] && _herdr_required=1

HERDR_REPO="${CONFIG_DIR}/herdr/config.toml"
HERDR_LIVE="${HOME}/.config/herdr/config.toml"

expect_herdr_bind() {
  local file="$1" pattern="$2" label="$3"
  if [[ ! -f "${file}" ]]; then
    warn "herdr ${label}: missing ${file}"
    return 1
  fi
  if rg -q -- "${pattern}" "${file}"; then
    ok "herdr ${label}"
  else
    fail "herdr ${label} (expected /${pattern}/ in ${file})"
  fi
}

if [[ -f "${HERDR_REPO}" ]]; then
  ok "herdr repo config present"
  expect_herdr_bind "${HERDR_REPO}" 'prefix = "ctrl\+a"' "repo prefix ctrl+a"
  expect_herdr_bind "${HERDR_REPO}" 'toggle_sidebar = "prefix\+b"' "repo sidebar prefix+b"
  expect_herdr_bind "${HERDR_REPO}" 'split_vertical = "prefix\+ampersand"' "repo split_vertical prefix+&"
  expect_herdr_bind "${HERDR_REPO}" 'split_horizontal = "prefix\+double_quote"' 'repo split_horizontal prefix+"'
  expect_herdr_bind "${HERDR_REPO}" 'focus_pane_left = "prefix\+h"' "repo focus h"
  expect_herdr_bind "${HERDR_REPO}" 'focus_pane_down = "prefix\+j"' "repo focus j"
  expect_herdr_bind "${HERDR_REPO}" 'focus_pane_up = "prefix\+k"' "repo focus k"
  expect_herdr_bind "${HERDR_REPO}" 'focus_pane_right = "prefix\+l"' "repo focus l"
  if rg -q 'tab_bar_right' "${HERDR_REPO}"; then
    ok "herdr repo tab_bar_right configured"
  else
    fail "herdr repo tab_bar_right missing"
  fi
  if command -v herdr >/dev/null 2>&1; then
    if HERDR_CONFIG_PATH="${HERDR_REPO}" herdr config check >/dev/null 2>&1; then
      ok "herdr repo config check"
    else
      fail "herdr repo config check failed"
      HERDR_CONFIG_PATH="${HERDR_REPO}" herdr config check 2>&1 | head -20 || true
    fi
  fi
else
  warn "herdr repo config missing (${HERDR_REPO})"
fi

if command -v herdr >/dev/null 2>&1; then
  ok "herdr $(herdr --version 2>/dev/null | head -1)"
  if [[ -f "${HERDR_LIVE}" ]]; then
    if [[ -L "${HERDR_LIVE}" ]]; then
      warn "herdr live config is a symlink (setup should merge into a regular file)"
    else
      ok "herdr live config is a regular file"
    fi
    expect_herdr_bind "${HERDR_LIVE}" 'prefix = "ctrl\+a"' "live prefix ctrl+a"
    expect_herdr_bind "${HERDR_LIVE}" 'toggle_sidebar = "prefix\+b"' "live sidebar prefix+b"
    expect_herdr_bind "${HERDR_LIVE}" 'split_vertical = "prefix\+ampersand"' "live split_vertical prefix+&"
    expect_herdr_bind "${HERDR_LIVE}" 'split_horizontal = "prefix\+double_quote"' 'live split_horizontal prefix+"'
    expect_herdr_bind "${HERDR_LIVE}" 'focus_pane_left = "prefix\+h"' "live focus h"
    expect_herdr_bind "${HERDR_LIVE}" 'focus_pane_down = "prefix\+j"' "live focus j"
    expect_herdr_bind "${HERDR_LIVE}" 'focus_pane_up = "prefix\+k"' "live focus k"
    expect_herdr_bind "${HERDR_LIVE}" 'focus_pane_right = "prefix\+l"' "live focus l"
    if herdr config check >/dev/null 2>&1; then
      ok "herdr live config check"
    else
      fail "herdr live config check failed"
      herdr config check 2>&1 | head -20 || true
    fi
  else
    warn "herdr live config missing (run setup.sh)"
  fi
  herdr integration status 2>/dev/null | head -20 || true
elif [[ "${_herdr_required}" -eq 1 ]]; then
  fail "herdr missing (required by resolved profile components/multiplexer)"
else
  info "herdr not selected by resolved profile (optional)"
fi

echo -e "\n${BLUE}Agent skills (optional)${NC}"
# shellcheck source=../helpers/agent_skills.sh
if [[ -f "${DOTS_DIR}/helpers/agent_skills.sh" ]]; then
  # shellcheck disable=SC1091
  source "${DOTS_DIR}/helpers/agent_skills.sh"
  # shellcheck source=../helpers/skills_pack.sh
  if [[ -f "${DOTS_DIR}/helpers/skills_pack.sh" ]]; then
    # shellcheck disable=SC1091
    source "${DOTS_DIR}/helpers/skills_pack.sh"
  fi

  MANIFEST="${CONFIG_DIR}/skills/manifest.toml"
  if [[ -f "${MANIFEST}" ]]; then
    ok "skills manifest present"
  else
    warn "skills manifest missing (configs/skills/manifest.toml)"
  fi

  # Soft: only enforce curated set when pack appears installed (security-review + archify)
  pack_selected=0
  if agent_skill_is_installed skill-security-review 2>/dev/null || agent_skill_is_installed systematic-debugging 2>/dev/null; then
    pack_selected=1
  fi

  if [[ "${pack_selected}" -eq 1 ]]; then
    ok "skills pack appears installed — verifying curated set"
    missing=0
    while IFS=$'\t' read -r sname _ssource; do
      [[ -z "${sname}" ]] && continue
      if agent_skill_is_installed "${sname}"; then
        ok "skill present: ${sname}"
      else
        fail "skill missing: ${sname}"
        missing=1
      fi
    done < <(dots_skills_manifest_entries 2>/dev/null || true)
    if [[ -f "${HOME}/.agents/.skill-lock.json" ]] || [[ -f "${HOME}/.config/dots/skills/skills-lock.json" ]]; then
      ok "skills lock/provenance metadata present"
    else
      warn "skills lock metadata missing"
    fi
    if command -v hermes >/dev/null 2>&1; then
      if [[ -L "${HOME}/.hermes/skills/systematic-debugging" ]] || [[ -e "${HOME}/.hermes/skills/archify" ]]; then
        ok "Hermes discovers pack skills"
      else
        warn "Hermes skill links incomplete"
      fi
    fi
    [[ "${missing}" -eq 0 ]] || true
  else
    warn "curated skills pack not installed (use: ./setup.sh --with skills)"
  fi

  if agent_skill_is_installed archify; then
    ok "archify skill present (~/.agents/skills/archify)"
    if command -v node >/dev/null 2>&1; then
      major="$(node_major_version 2>/dev/null || true)"
      if [[ -n "${major}" ]] && [[ "${major}" -ge 18 ]]; then
        ok "Node $(node -v 2>/dev/null) meets Archify requirement (>=18)"
      else
        warn "Node present but major < 18 (Archify needs >=18)"
      fi
      if [[ -x "${HOME}/.agents/skills/archify/bin/archify.mjs" ]]; then
        if node "${HOME}/.agents/skills/archify/bin/archify.mjs" doctor >/dev/null 2>&1; then
          ok "archify doctor"
        else
          warn "archify doctor reported issues"
        fi
      fi
    else
      warn "archify installed but node missing on PATH"
    fi
    if [[ -L "${HOME}/.hermes/skills/archify" ]] || [[ -e "${HOME}/.hermes/skills/archify" ]]; then
      ok "Hermes archify skill link present"
    else
      warn "Hermes archify link missing (run: ./setup.sh --with archify or --with skills)"
    fi
  else
    warn "archify skill not installed (use: ./setup.sh --with archify or --with skills)"
  fi

  if agent_skill_is_installed skill-security-review 2>/dev/null; then
    ok "security-review skill present"
  else
    warn "security-review skill not installed (included in --with skills)"
  fi
else
  warn "helpers/agent_skills.sh missing"
fi

echo -e "\n${BLUE}Draw Things (optional)${NC}"
DT_REPO_CFG="${CONFIG_DIR}/drawthings/config.toml"
DT_LIVE_CFG="${HOME}/.config/drawthings-mcp/config.toml"
DT_LAUNCHER="${HOME}/.local/bin/drawthings-mcp"
DT_PROJECT="${DOTS_DIR}/tools/drawthings_mcp"

[[ -f "${DT_REPO_CFG}" ]] && ok "drawthings repo config present" || warn "drawthings repo config missing"
if [[ -f "${DT_LIVE_CFG}" ]]; then
  ok "drawthings live config (${DT_LIVE_CFG})"
else
  warn "drawthings live config missing (run: ./setup.sh --with drawthings)"
fi

if [[ -L "${DT_LAUNCHER}" ]] || [[ -x "${DT_LAUNCHER}" ]]; then
  ok "stable launcher: ${DT_LAUNCHER}"
  if command -v drawthings-mcp >/dev/null 2>&1; then
    ok "drawthings-mcp on PATH ($(command -v drawthings-mcp))"
  else
    warn "drawthings-mcp not on PATH (ensure ~/.local/bin is on PATH)"
  fi
else
  warn "stable launcher missing (${DT_LAUNCHER})"
fi

if [[ -f "${DT_PROJECT}/pyproject.toml" ]] && [[ -f "${DT_PROJECT}/uv.lock" ]]; then
  ok "drawthings MCP pyproject + uv.lock present"
else
  fail "drawthings MCP dependency manifest incomplete"
fi

if command -v uv >/dev/null 2>&1 && [[ -f "${DT_PROJECT}/pyproject.toml" ]]; then
  if uv run --directory "${DT_PROJECT}" --python-preference system python -c 'from mcp.server.fastmcp import FastMCP' >/dev/null 2>&1; then
    ok "MCP Python deps resolvable via uv"
  else
    local _dt_sel=0
    local _c
    for _c in "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; do
      [[ "${_c}" == "drawthings" ]] && _dt_sel=1 && break
    done
    if [[ "${_dt_sel}" -eq 1 ]]; then
      fail "MCP Python deps not resolvable (uv sync --directory tools/drawthings_mcp)"
    else
      warn "drawthings MCP Python deps not resolvable (optional until --with drawthings)"
    fi
  fi
else
  warn "uv missing — cannot verify MCP Python deps"
fi

if [[ -d "/Applications/Draw Things.app" ]]; then
  ok "Draw Things.app present (optional at runtime)"
else
  warn "Draw Things.app missing (optional; CLI can still run with DRAWTHINGS_MODELS_DIR)"
fi

if command -v draw-things-cli >/dev/null 2>&1; then
  ok "draw-things-cli $(draw-things-cli --version 2>/dev/null | head -1)"
  model_n="$(draw-things-cli models list --downloaded-only --offline 2>/dev/null | python3 -c '
import re,sys
print(sum(1 for line in sys.stdin if re.match(r"^\S+\.ckpt\b", line.strip())))
' || echo 0)"
  if [[ "${model_n}" -gt 0 ]]; then
    ok "${model_n} downloaded Draw Things model(s)"
  else
    warn "no downloaded Draw Things models (CLI OK; generate will fail until models exist)"
  fi
else
  warn "draw-things-cli not installed (use: ./setup.sh --with drawthings)"
fi

DT_OUT="${HOME}/Pictures/AI/DrawThings"
if [[ -d "${DT_OUT}" ]]; then
  if [[ -w "${DT_OUT}" ]]; then
    ok "output dir writable (${DT_OUT})"
  else
    fail "output dir not writable (${DT_OUT})"
  fi
else
  warn "output dir missing (${DT_OUT}) — run: ./setup.sh --with drawthings"
fi

# GUI HTTP API is intentionally unused by the CLI bridge — informational only.
if curl -fsS -m 1 "http://127.0.0.1:7860/" >/dev/null 2>&1; then
  ok "info: Draw Things GUI HTTP API listening on 127.0.0.1:7860 (unused by CLI bridge)"
fi

if command -v hermes >/dev/null 2>&1; then
  if hermes mcp list 2>/dev/null | rg -q 'drawthings'; then
    ok "Hermes MCP 'drawthings' registered"
    if hermes mcp test drawthings >/dev/null 2>&1; then
      ok "Hermes MCP 'drawthings' connects"
    else
      fail "Hermes MCP 'drawthings' registered but cannot connect"
    fi
  else
    info "Hermes present; MCP 'drawthings' not registered (requires --with hermes,drawthings)"
  fi
else
  info "Hermes not installed — Draw Things bridge can exist without MCP registration"
fi

if [[ -f "${HOME}/.config/dots/drawthings-mcp.client.json" ]]; then
  ok "reusable MCP client snippet (~/.config/dots/drawthings-mcp.client.json)"
fi

if [[ -L "${HOME}/.local/bin/img" ]] || [[ -x "${HOME}/.local/bin/img" ]]; then
  ok "img launcher present (~/.local/bin/img)"
  command -v img >/dev/null 2>&1 && ok "img on PATH" || info "img not on PATH (ensure ~/.local/bin via ~/.zshenv)"
else
  if [[ -f "${DT_LIVE_CFG}" ]]; then
    info "img launcher missing (re-run: ./setup.sh — launchers pass)"
  fi
fi

if [[ -L "${HOME}/.zshenv" ]] || [[ -f "${HOME}/.zshenv" ]]; then
  ok "~/.zshenv present (PATH for non-interactive zsh)"
else
  info "~/.zshenv missing — new zsh sessions may miss ~/.local/bin (re-run ./setup.sh)"
fi
echo -e "\n${BLUE}Hermes (optional)${NC}"
if command -v hermes >/dev/null 2>&1; then
  hermes_win="$(command -v hermes)"
  ok "hermes resolved: ${hermes_win}"
  hermes --version 2>/dev/null | head -2 || true
  brew_hermes=""
  [[ -x /opt/homebrew/bin/hermes ]] && brew_hermes="/opt/homebrew/bin/hermes"
  [[ -z "${brew_hermes}" ]] && [[ -x /usr/local/bin/hermes ]] && brew_hermes="/usr/local/bin/hermes"
  if [[ -n "${brew_hermes}" ]]; then
    if [[ "${hermes_win}" == "${brew_hermes}" ]] \
      || [[ "$(realpath "${hermes_win}" 2>/dev/null || true)" == "$(realpath "${brew_hermes}" 2>/dev/null || true)" ]]; then
      ok "canonical Hermes is Homebrew hermes-agent"
    else
      fail "Hermes PATH shadowing: ${hermes_win} wins over ${brew_hermes}"
    fi
  fi
  if [[ -e "${HOME}/.local/bin/hermes" ]] || [[ -L "${HOME}/.local/bin/hermes" ]]; then
    fail "stale ~/.local/bin/hermes still present (should be retired by PATH hygiene)"
  else
    ok "no git-install Hermes shim in ~/.local/bin"
  fi
else
  warn "hermes not installed (use: ./setup.sh --with hermes)"
fi

echo -e "\n${BLUE}Ollama (optional)${NC}"
if command -v ollama >/dev/null 2>&1; then
  ok "ollama client: $(ollama --version 2>/dev/null | head -1)"
  if ollama list >/dev/null 2>&1; then
    n="$(ollama list 2>/dev/null | tail -n +2 | awk 'NF' | wc -l | tr -d ' ')"
    ok "ollama server reachable (${n} models listed)"
  else
    warn "ollama server not reachable (brew services start ollama) — not a hard failure"
  fi
else
  warn "ollama not installed (use: ./setup.sh --with ollama)"
fi

echo -e "\n${BLUE}OpenCode adapter (optional)${NC}"
OC_REPO_EXEC="${CONFIG_DIR}/agents/execution.toml"
OC_LIVE_EXEC="${HOME}/.config/dots/agents/execution.toml"
OC_AGENT_LAUNCHER="${HOME}/.local/bin/opencode-agent"
OC_MCP_LAUNCHER="${HOME}/.local/bin/opencode-mcp"
OC_PROJECT="${DOTS_DIR}/tools/opencode_mcp"

[[ -f "${OC_REPO_EXEC}" ]] && ok "agents execution.toml present" || warn "configs/agents/execution.toml missing"
if [[ -f "${OC_LIVE_EXEC}" ]]; then
  ok "live execution config (${OC_LIVE_EXEC})"
  if rg -q 'mode = "standalone"' "${OC_LIVE_EXEC}" 2>/dev/null; then
    ok "opencode mode=standalone (default policy)"
  fi
  if rg -q 'default_model = "ollama/qwen-hermes:latest"' "${OC_LIVE_EXEC}" 2>/dev/null; then
    ok "default_model ollama/qwen-hermes:latest configured"
  fi
  if rg -q 'default_agent = "build"' "${OC_LIVE_EXEC}" 2>/dev/null; then
    ok "default_agent build configured"
  fi
else
  warn "live execution config missing (run: ./setup.sh --with opencode)"
fi

if [[ -L "${OC_AGENT_LAUNCHER}" ]] || [[ -x "${OC_AGENT_LAUNCHER}" ]]; then
  ok "stable launcher: ${OC_AGENT_LAUNCHER}"
  if [[ "$(realpath "${OC_AGENT_LAUNCHER}" 2>/dev/null || true)" == "$(realpath "${DOTS_DIR}/scripts/opencode-agent" 2>/dev/null || true)" ]]; then
    ok "opencode-agent symlink target correct"
  else
    warn "opencode-agent symlink target unexpected ($(readlink "${OC_AGENT_LAUNCHER}" 2>/dev/null || true))"
  fi
else
  warn "opencode-agent launcher missing (run: ./setup.sh --with opencode)"
fi

if [[ -L "${OC_MCP_LAUNCHER}" ]] || [[ -x "${OC_MCP_LAUNCHER}" ]]; then
  ok "stable launcher: ${OC_MCP_LAUNCHER}"
else
  warn "opencode-mcp launcher missing (run: ./setup.sh --with opencode)"
fi

if [[ -f "${OC_PROJECT}/pyproject.toml" ]]; then
  ok "opencode MCP pyproject present"
else
  fail "opencode MCP pyproject missing"
fi

if command -v opencode >/dev/null 2>&1; then
  ok "opencode $(opencode --version 2>/dev/null | head -1)"
  if opencode models 2>/dev/null | rg -q 'ollama/qwen-hermes'; then
    ok "opencode models includes ollama/qwen-hermes"
  else
    warn "ollama/qwen-hermes not listed by opencode models (check ~/.config/opencode + ollama)"
  fi
  if opencode agent list 2>/dev/null | rg -q '^build \(primary\)'; then
    ok "opencode agent 'build' present"
  else
    warn "opencode agent 'build' not found"
  fi
else
  warn "opencode not installed (use: ./setup.sh --with opencode)"
fi

if command -v hermes >/dev/null 2>&1; then
  if hermes mcp list 2>/dev/null | rg -q 'opencode'; then
    ok "Hermes MCP 'opencode' registered"
    if hermes mcp test opencode >/dev/null 2>&1; then
      ok "Hermes MCP 'opencode' connects"
    else
      fail "Hermes MCP 'opencode' registered but cannot connect"
    fi
  else
    info "Hermes present; MCP 'opencode' not registered (requires --with hermes,opencode)"
  fi
fi

echo -e "\n${BLUE}Codex adapter (optional)${NC}"
if command -v codex >/dev/null 2>&1; then
  ok "codex $(codex --version 2>/dev/null | head -1)"
  codex_real="$(realpath "$(command -v codex)" 2>/dev/null || readlink "$(command -v codex)" 2>/dev/null || true)"
  if [[ "${codex_real}" == *"/node_modules/@openai/codex/"* ]]; then
    warn "Codex is npm-backed (${codex_real}); prefer Homebrew cask (./setup.sh --with codex)"
  elif brew list --cask codex >/dev/null 2>&1; then
    ok "Codex install source: Homebrew cask"
  else
    warn "Codex present but not detected as Homebrew cask"
  fi
  if [[ -f "${HOME}/.codex/auth.json" ]]; then
    ok "Codex auth file present (~/.codex/auth.json; contents not inspected)"
  else
    warn "Codex auth file missing — MCP discovery may work; cloud tasks need login"
  fi
else
  warn "codex not installed (use: ./setup.sh --with codex)"
fi

if command -v hermes >/dev/null 2>&1; then
  if hermes mcp list 2>/dev/null | rg -q 'codex'; then
    ok "Hermes MCP 'codex' registered"
    # Validate registration: native mcp-server OR DOTS bridge launcher
    hermes_py="${HOME}/.hermes/hermes-agent/venv/bin/python"
    if [[ -x "${hermes_py}" ]]; then
      if "${hermes_py}" - <<'PY'
import os
import sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / ".hermes" / "hermes-agent"))
from hermes_cli.mcp_config import _get_mcp_servers
cfg = _get_mcp_servers().get("codex") or {}
cmd = cfg.get("command") or ""
args = cfg.get("args") or []
enabled = cfg.get("enabled", True) in (True, "true", "1", "yes", None)
if cfg.get("url") or not enabled or not cmd:
    sys.exit(1)
base = os.path.basename(cmd)
# Native: .../codex + ["mcp-server"]  OR bridge: .../codex-mcp + []
native = base == "codex" and args == ["mcp-server"]
bridge = base == "codex-mcp" and args == []
sys.exit(0 if native or bridge else 1)
PY
      then
        ok "Hermes MCP 'codex' command/args/enabled match expected (native or DOTS bridge)"
      else
        fail "Hermes MCP 'codex' registration drifted"
      fi
    fi
    if [[ -L "${HOME}/.local/bin/codex-mcp" ]] || [[ -x "${HOME}/.local/bin/codex-mcp" ]]; then
      ok "DOTS codex-mcp launcher present (used when native mcp-server absent)"
    fi
    if hermes mcp test codex >/dev/null 2>&1; then
      ok "Hermes MCP 'codex' connects"
    else
      fail "Hermes MCP 'codex' registered but cannot connect"
    fi
  else
    info "Hermes present; MCP 'codex' not registered (requires --with hermes,codex)"
  fi
fi

if command -v herdr >/dev/null 2>&1; then
  if herdr integration status 2>/dev/null | rg -q '^opencode:[[:space:]]*current'; then
    ok "herdr integration opencode current"
  else
    info "herdr opencode integration not current (requires --with herdr,opencode)"
  fi
  if herdr integration status 2>/dev/null | rg -q '^codex:[[:space:]]*current'; then
    ok "herdr integration codex current"
  else
    info "herdr codex integration not current (requires --with herdr,codex)"
  fi
  if herdr integration status 2>/dev/null | rg -q '^cursor:[[:space:]]*current'; then
    ok "herdr integration cursor current"
  else
    info "herdr cursor integration not current (requires --with herdr,cursor)"
  fi
  if herdr integration status 2>/dev/null | rg -q '^hermes:[[:space:]]*current'; then
    ok "herdr integration hermes current"
  else
    info "herdr hermes integration not current (requires --with herdr,hermes)"
  fi
fi

echo -e "\n${BLUE}Cursor Agent (optional; managed only)${NC}"
CURSOR_MANAGED="${HOME}/.config/dots/managed/cursor"
if [[ -f "${CURSOR_MANAGED}" ]]; then
  ok "Cursor managed by DOTS (${CURSOR_MANAGED})"
  if command -v agent >/dev/null 2>&1; then
    ok "agent on PATH ($(command -v agent))"
    agent --version 2>/dev/null | head -1 || true
  else
    warn "managed Cursor but 'agent' not on PATH"
  fi
  if [[ -f "${HOME}/.cursor/cli-config.json" ]]; then
    if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "${HOME}/.cursor/cli-config.json" 2>/dev/null; then
      ok "Cursor cli-config.json parses"
    else
      fail "Cursor cli-config.json invalid JSON"
    fi
  else
    warn "managed Cursor but ~/.cursor/cli-config.json missing"
  fi
  if [[ -f "${HOME}/.cursor/mcp.json" ]]; then
    if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "${HOME}/.cursor/mcp.json" 2>/dev/null; then
      ok "Cursor mcp.json parses"
      if rg -q '"drawthings"' "${HOME}/.cursor/mcp.json" 2>/dev/null; then
        ok "Cursor MCP includes drawthings"
      else
        info "Cursor MCP has no drawthings (add with --with cursor,drawthings)"
      fi
    else
      fail "Cursor mcp.json invalid JSON"
    fi
  else
    info "Cursor mcp.json absent (optional until MCP servers co-selected)"
  fi
else
  if command -v agent >/dev/null 2>&1 || command -v cursor-agent >/dev/null 2>&1; then
    info "Cursor CLI present on machine but not DOTS-managed (presence ≠ consent)"
  else
    info "Cursor not managed (use: ./setup.sh --with cursor)"
  fi
fi

echo -e "\n${BLUE}FluidVoice (optional; macOS)${NC}"
_fv_selected=0
for _c in "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; do
  [[ "${_c}" == "fluidvoice" ]] && _fv_selected=1 && break
done
if [[ "${_fv_selected}" -eq 1 ]]; then
  if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "fluidvoice selected but host is not macOS"
  elif [[ -d "/Applications/FluidVoice.app" ]]; then
    ok "FluidVoice.app present"
  elif command -v brew >/dev/null 2>&1 && brew list --cask fluidvoice >/dev/null 2>&1; then
    ok "fluidvoice cask installed (brew)"
  else
    fail "fluidvoice selected but not installed (./setup.sh --with fluidvoice)"
  fi
else
  info "FluidVoice not selected by resolved profile (optional)"
fi

echo -e "\n${BLUE}Local models (optional; not pulled by bootstrap)${NC}"
if command -v ollama >/dev/null 2>&1; then
  _om_count="$(ollama ls 2>/dev/null | awk 'NR>1 && NF{c++} END{print c+0}')"
  info "ollama installed; ${_om_count} model(s) present (pull: ./scripts/pull_models.sh --provider ollama)"
else
  info "ollama not installed"
fi
if command -v llama-cli >/dev/null 2>&1 || command -v llama >/dev/null 2>&1; then
  info "llama.cpp installed; model cache via llama-cli --cache-list (pull: ./scripts/pull_models.sh --provider llamacpp)"
else
  info "llama.cpp not installed"
fi
_dt_sel=0
for _c in "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; do
  [[ "${_c}" == "drawthings" ]] && _dt_sel=1 && break
done
if [[ "${_dt_sel}" -eq 1 ]]; then
  if command -v draw-things-cli >/dev/null 2>&1; then
    if draw-things-cli models list --downloaded-only 2>/dev/null | awk 'NF{c++} END{exit !(c>0)}'; then
      ok "drawthings has downloaded generation model(s)"
    else
      warn "drawthings selected but no generation model installed (./scripts/pull_models.sh --provider drawthings)"
    fi
  else
    warn "drawthings selected but draw-things-cli missing"
  fi
fi
_fv_sel=0
for _c in "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; do
  [[ "${_c}" == "fluidvoice" ]] && _fv_sel=1 && break
done
if [[ "${_fv_sel}" -eq 1 ]]; then
  info "FluidVoice installed; model state managed by the app (no supported CLI pull)"
fi

echo -e "\n${BLUE}Images toolkit (optional)${NC}"
# Soft checks: warn when missing (base Brewfile already has magick/exiftool for many users)
for cmd in magick exiftool pngquant rsvg-convert gs; do
  if command -v "${cmd}" >/dev/null 2>&1; then
    ok "${cmd} available ($(command -v ${cmd}))"
  else
    warn "${cmd} missing (use: ./setup.sh --with images)"
  fi
done
command -v oxipng >/dev/null 2>&1 && ok "oxipng available" || warn "oxipng missing (optional via --with images)"
command -v cwebp >/dev/null 2>&1 && ok "cwebp available" || warn "cwebp missing (webp via --with images)"

echo -e "\n${BLUE}TeX Live (optional)${NC}"
if command -v pdflatex >/dev/null 2>&1; then
  ok "pdflatex $(pdflatex --version 2>/dev/null | head -1)"
  for cmd in tex latex xelatex lualatex bibtex kpsewhich; do
    if command -v "${cmd}" >/dev/null 2>&1; then
      ok "${cmd} available"
    else
      warn "${cmd} missing (expected with --with tex / brew texlive)"
    fi
  done
  if kpsewhich article.cls >/dev/null 2>&1; then
    ok "kpsewhich article.cls → $(kpsewhich article.cls)"
  else
    warn "kpsewhich article.cls failed"
  fi
  if command -v latexmk >/dev/null 2>&1; then
    ok "latexmk available"
  else
    warn "latexmk not on PATH (may still be inside texlive; not a separate Homebrew formula)"
  fi
else
  warn "TeX Live not installed (use: ./setup.sh --with tex)"
fi

echo -e "\n${BLUE}Agent router (optional)${NC}"
ROUTER_REPO="${DOTS_DIR}/skills/agent-router"
ROUTER_AGENTS="${HOME}/.agents/skills/agent-router"
ROUTER_HERMES="${HOME}/.hermes/skills/agent-router"
ROUTER_CFG_REPO="${CONFIG_DIR}/agents/router.toml"
ROUTER_CFG_LIVE="${HOME}/.config/dots/agents/router.toml"

[[ -f "${ROUTER_REPO}/SKILL.md" ]] && ok "router skill in repo" || fail "skills/agent-router/SKILL.md missing"
[[ -f "${ROUTER_REPO}/route.py" ]] && ok "router route.py present" || fail "skills/agent-router/route.py missing"
[[ -f "${ROUTER_CFG_REPO}" ]] && ok "router.toml template present" || warn "configs/agents/router.toml missing"

if [[ -L "${ROUTER_AGENTS}" ]] || [[ -d "${ROUTER_AGENTS}" ]]; then
  ok "router skill linked (~/.agents/skills/agent-router)"
else
  warn "router skill not linked (install AI stack: ./setup.sh --with hermes,…)"
fi
if [[ -L "${ROUTER_HERMES}" ]] || [[ -e "${ROUTER_HERMES}" ]]; then
  ok "Hermes sees agent-router (~/.hermes/skills/agent-router)"
else
  info "Hermes agent-router link absent (requires --with hermes + router install)"
fi
if [[ -f "${ROUTER_CFG_LIVE}" ]]; then
  ok "live router config (${ROUTER_CFG_LIVE})"
fi

if [[ -x "${DOTS_DIR}/scripts/router_policy_test.sh" ]]; then
  if "${DOTS_DIR}/scripts/router_policy_test.sh" >/tmp/dots-router-policy.$$ 2>&1; then
    ok "router policy tests"
    rm -f /tmp/dots-router-policy.$$
  else
    fail "router policy tests failed"
    cat /tmp/dots-router-policy.$$ >&2 || true
    rm -f /tmp/dots-router-policy.$$
  fi
fi

if [[ -x "${DOTS_DIR}/scripts/provider_isolation_test.sh" ]]; then
  if "${DOTS_DIR}/scripts/provider_isolation_test.sh" >/tmp/dots-isolation.$$ 2>&1; then
    ok "provider isolation dry-run tests"
    rm -f /tmp/dots-isolation.$$
  else
    fail "provider isolation tests failed"
    cat /tmp/dots-isolation.$$ >&2 || true
    rm -f /tmp/dots-isolation.$$
  fi
fi

if [[ -x "${DOTS_DIR}/scripts/profile_resolution_test.sh" ]]; then
  if "${DOTS_DIR}/scripts/profile_resolution_test.sh" >/tmp/dots-profiles.$$ 2>&1; then
    ok "profile resolution tests"
    rm -f /tmp/dots-profiles.$$
  else
    fail "profile resolution tests failed"
    cat /tmp/dots-profiles.$$ >&2 || true
    rm -f /tmp/dots-profiles.$$
  fi
fi

echo -e "\n${BLUE}Agent telemetry (local)${NC}"
[[ -f "${CONFIG_DIR}/agents/telemetry.toml" ]] && ok "telemetry.toml present" || fail "configs/agents/telemetry.toml missing"
[[ -d "${DOTS_DIR}/tools/agent_telemetry/dots_telemetry" ]] && ok "telemetry package present" || fail "tools/agent_telemetry missing"
if [[ -L "${HOME}/.local/bin/agent-telemetry" ]] || [[ -x "${HOME}/.local/bin/agent-telemetry" ]] || [[ -x "${DOTS_DIR}/scripts/agent-telemetry" ]]; then
  ok "agent-telemetry CLI present"
else
  warn "agent-telemetry not linked (run ./setup.sh)"
fi
if [[ -L "${HOME}/.local/bin/agent-stats" ]] || [[ -x "${HOME}/.local/bin/agent-stats" ]] || [[ -x "${DOTS_DIR}/scripts/agent-stats" ]]; then
  ok "agent-stats CLI present"
else
  warn "agent-stats not linked (run ./setup.sh)"
fi
TELE_DATA="${HOME}/.local/share/dots/telemetry"
if [[ -d "${TELE_DATA}" ]]; then
  ok "telemetry data dir present (${TELE_DATA})"
else
  info "telemetry data dir absent (created on first agent-telemetry use)"
fi
if DOTS_DIR="${DOTS_DIR}" "${DOTS_DIR}/scripts/agent-telemetry" doctor >/tmp/dots-tele-doc.$$ 2>&1; then
  ok "agent-telemetry doctor"
  rm -f /tmp/dots-tele-doc.$$
else
  warn "agent-telemetry doctor failed"
  cat /tmp/dots-tele-doc.$$ >&2 || true
  rm -f /tmp/dots-tele-doc.$$
fi
if DOTS_DIR="${DOTS_DIR}" "${DOTS_DIR}/scripts/agent-stats" --json >/tmp/dots-tele-stats.$$ 2>&1; then
  ok "agent-stats works (empty DB OK)"
  rm -f /tmp/dots-tele-stats.$$
else
  warn "agent-stats failed"
  cat /tmp/dots-tele-stats.$$ >&2 || true
  rm -f /tmp/dots-tele-stats.$$
fi
if [[ -x "${DOTS_DIR}/scripts/telemetry_test.sh" ]]; then
  if "${DOTS_DIR}/scripts/telemetry_test.sh" >/tmp/dots-tele-test.$$ 2>&1; then
    ok "telemetry unit/integration tests"
    rm -f /tmp/dots-tele-test.$$
  else
    fail "telemetry tests failed"
    cat /tmp/dots-tele-test.$$ >&2 || true
    rm -f /tmp/dots-tele-test.$$
  fi
fi

# Destination availability when components are present (partial installs OK; info not warn)
if command -v hermes >/dev/null 2>&1; then
  hermes mcp list 2>/dev/null | rg -q 'opencode' && ok "router dest opencode MCP present" || info "router dest opencode MCP absent (opt-in)"
  hermes mcp list 2>/dev/null | rg -q 'codex' && ok "router dest codex MCP present" || info "router dest codex MCP absent (opt-in)"
  hermes mcp list 2>/dev/null | rg -q 'drawthings' && ok "router dest drawthings MCP present" || info "router dest drawthings MCP absent (opt-in)"
fi
if [[ -e "${HOME}/.agents/skills/archify/SKILL.md" ]]; then
  ok "router dest archify skill present"
else
  info "router dest archify skill absent (optional)"
fi

if [[ -f "${DOTS_DIR}/bootstrap.sh" ]] && [[ -x "${DOTS_DIR}/bootstrap.sh" ]]; then
  ok "bootstrap.sh present"
else
  fail "bootstrap.sh missing or not executable"
fi
[[ -f "${CONFIG_DIR}/bootstrap/profiles/base.toml" ]] && ok "bootstrap profile base" || fail "base profile missing"
[[ -f "${CONFIG_DIR}/bootstrap/profiles/home.toml" ]] && ok "bootstrap profile home" || fail "home profile missing"
[[ -f "${CONFIG_DIR}/bootstrap/profiles/work.toml" ]] && ok "bootstrap profile work" || fail "work profile missing"
[[ -f "${CONFIG_DIR}/bootstrap/profiles/server.toml" ]] && ok "bootstrap profile server" || fail "server profile missing"
[[ -f "${CONFIG_DIR}/bootstrap/profiles/all.toml" ]] && ok "bootstrap profile all" || fail "all profile missing"
[[ -f "${CONFIG_DIR}/components.toml" ]] && ok "components registry present" || fail "configs/components.toml missing"

# Runtime policy
if [[ -f "${HOME}/.config/dots/runtime.env" ]]; then
  ok "runtime.env present"
  # shellcheck disable=SC1090
  if bash -n "${HOME}/.config/dots/runtime.env" 2>/dev/null; then
    ok "runtime.env syntax"
  else
    fail "runtime.env syntax error"
  fi
else
  warn "runtime.env missing (run bootstrap to generate)"
fi
if [[ -f "${HOME}/.config/dots/local.sh" ]]; then
  ok "local.sh present"
else
  info "local.sh not created yet (bootstrap seeds it once)"
fi

# Multiplexer expectation
case "${PROFILE_RUNTIME_MULTIPLEXER:-tmux}" in
  herdr)
    if command -v herdr >/dev/null 2>&1; then
      ok "herdr available for runtime.multiplexer=herdr"
    else
      warn "runtime wants herdr but herdr not installed (fallback tmux at runtime)"
    fi
    ;;
  tmux)
    if command -v tmux >/dev/null 2>&1; then
      ok "tmux available"
    else
      fail "tmux missing (required multiplexer)"
    fi
    ;;
esac
if [[ -f "${DOTS_DIR}/configure.sh" ]] && [[ -x "${DOTS_DIR}/configure.sh" ]]; then
  ok "configure.sh present"
else
  fail "configure.sh missing or not executable"
fi
if [[ -f "${CONFIG_DIR}/skills/manifest.toml" ]] && rg -q '\[packs\.ai-skills\]' "${CONFIG_DIR}/skills/manifest.toml"; then
  ok "skills manifest has ai-skills pack"
else
  fail "skills manifest missing packs.ai-skills"
fi

echo -e "\n${BLUE}Summary${NC}"
echo -e "Passed: ${GREEN}${PASSED}${NC}  Warnings: ${YELLOW}${WARNINGS}${NC}  Failed: ${RED}${FAILED}${NC}"
if [[ "${FAILED}" -eq 0 ]]; then
  echo -e "${GREEN}Bootstrap contract satisfied${NC} (profile=${PROFILE_NAME:-${CHECK_PROFILE}}; warnings=${WARNINGS})"
  exit 0
else
  echo -e "${RED}Health check FAILED: ${FAILED} required check(s) failed.${NC}"
  exit 1
fi
