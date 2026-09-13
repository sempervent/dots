#!/usr/bin/env bash
# Health check for sempervent/dots — green when optional AI tools are absent.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASSED=0; FAILED=0; WARNINGS=0

DOTS_DIR="${DOTS_DIR:-${HOME}/dots}"
SYM_DIR="${DOTS_DIR}/syms"
CONFIG_DIR="${DOTS_DIR}/configs"

ok() { echo -e "${GREEN}✓${NC} $1"; PASSED=$((PASSED + 1)); }
warn() { echo -e "${YELLOW}⚠${NC} $1"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo -e "${RED}✗${NC} $1"; FAILED=$((FAILED + 1)); }

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

echo -e "${BLUE}dotfiles health check${NC}\n"

echo -e "${BLUE}Core layout${NC}"
[[ -f "${DOTS_DIR}/brew/Brewfile" ]] && ok "Brewfile present" || fail "Brewfile missing"
[[ ! -e "${DOTS_DIR}/brew/packages.txt" ]] && ok "packages.txt absent" || fail "packages.txt still present (should be removed)"
[[ -d "${DOTS_DIR}/shell" ]] && ok "shell/ present" || fail "shell/ missing"
[[ -d "${DOTS_DIR}/zsh" ]] && ok "zsh/ present" || fail "zsh/ missing"

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

echo -e "\n${BLUE}tmux (optional)${NC}"
if command -v tmux >/dev/null 2>&1; then
  ok "tmux $(tmux -V)"
  sock="/tmp/dots-tmux-check-$$"
  if tmux -L "dotscheck$$" -f "${SYM_DIR}/tmux.conf" start-server \; list-commands >/dev/null 2>&1; then
    ok "tmux config loads"
    tmux -L "dotscheck$$" kill-server >/dev/null 2>&1 || true
  else
    # Alternative: start then kill
    tmux -L "dotscheck$$" -f "${SYM_DIR}/tmux.conf" new-session -d -s check 'true' 2>/dev/null && {
      ok "tmux config loads (temp session)"
      tmux -L "dotscheck$$" kill-server >/dev/null 2>&1 || true
    } || warn "tmux config validation inconclusive (plugins may be pending)"
  fi
  unset sock
else
  warn "tmux not installed"
fi

echo -e "\n${BLUE}Herdr (optional)${NC}"
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
else
  warn "herdr not installed (use: ./setup.sh --with herdr)"
fi

echo -e "\n${BLUE}Agent skills (optional)${NC}"
# shellcheck source=../helpers/agent_skills.sh
if [[ -f "${DOTS_DIR}/helpers/agent_skills.sh" ]]; then
  # shellcheck disable=SC1091
  source "${DOTS_DIR}/helpers/agent_skills.sh"
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
      warn "Hermes archify link missing (run: ./setup.sh --with archify)"
    fi
  else
    warn "archify skill not installed (use: ./setup.sh --with archify)"
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
    fail "MCP Python deps not resolvable (uv sync --directory tools/drawthings_mcp)"
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
    warn "Hermes installed but MCP 'drawthings' not registered (run: ./setup.sh --with drawthings)"
  fi
else
  warn "Hermes not installed — Draw Things bridge can exist without MCP registration"
fi

if [[ -f "${HOME}/.config/dots/drawthings-mcp.client.json" ]]; then
  ok "reusable MCP client snippet (~/.config/dots/drawthings-mcp.client.json)"
fi

echo -e "\n${BLUE}Hermes (optional)${NC}"
if command -v hermes >/dev/null 2>&1; then
  ok "hermes resolved: $(command -v hermes)"
  hermes --version 2>/dev/null | head -2 || true
  count="$(type -a hermes 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${count}" -gt 1 ]]; then
    warn "multiple hermes binaries on PATH (type -a hermes); prefer Homebrew after migration"
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

echo -e "\n${BLUE}Summary${NC}"
echo -e "Passed: ${GREEN}${PASSED}${NC}  Warnings: ${YELLOW}${WARNINGS}${NC}  Failed: ${RED}${FAILED}${NC}"
[[ "${FAILED}" -eq 0 ]]
