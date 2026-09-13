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
if command -v herdr >/dev/null 2>&1; then
  ok "herdr $(herdr --version 2>/dev/null | head -1)"
  [[ -f "${HOME}/.config/herdr/config.toml" ]] && ok "herdr config present" || warn "herdr config missing (run setup.sh)"
  if [[ -f "${HOME}/.config/herdr/config.toml" ]]; then
    rg -q 'prefix = "ctrl\+a"' "${HOME}/.config/herdr/config.toml" && ok "herdr prefix ctrl+a" || warn "herdr prefix not ctrl+a"
    rg -q 'toggle_sidebar = "prefix\+b"' "${HOME}/.config/herdr/config.toml" && ok "herdr sidebar on prefix+b" || warn "sidebar binding unexpected"
  fi
  herdr integration status 2>/dev/null | head -20 || true
else
  warn "herdr not installed (use: ./setup.sh --with herdr)"
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
