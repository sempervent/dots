#!/usr/bin/env bash
# Health check script for dotfiles setup
# Checks that all symlinks, configs, and utilities are properly configured

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
WARNINGS=0

# Dots directory
DOTS_DIR="${DOTS_DIR:-${HOME}/dots}"
SYM_DIR="${DOTS_DIR}/syms"
CONFIG_DIR="${DOTS_DIR}/configs"

echo -e "${BLUE}🔍 Running dotfiles health check...${NC}\n"

# Check symlinks {{{1
check_symlink() {
  local target="$1"
  local source="$2"
  local name="$3"
  
  if [ ! -e "$target" ]; then
    echo -e "${RED}✗${NC} ${name}: ${target} does not exist"
    ((CHECKS_FAILED++))
    return 1
  elif [ ! -L "$target" ]; then
    echo -e "${YELLOW}⚠${NC} ${name}: ${target} exists but is not a symlink"
    ((WARNINGS++))
    return 2
  elif [ "$(readlink -f "$target")" != "$(readlink -f "$source")" ]; then
    echo -e "${RED}✗${NC} ${name}: ${target} points to wrong location"
    ((CHECKS_FAILED++))
    return 1
  else
    echo -e "${GREEN}✓${NC} ${name}"
    ((CHECKS_PASSED++))
    return 0
  fi
}

echo -e "${BLUE}Checking symlinks...${NC}"

# Standard symlinks in $HOME
check_symlink "$HOME/.bashrc" "${SYM_DIR}/bashrc" "Bash config"
check_symlink "$HOME/.zshrc" "${SYM_DIR}/zshrc" "Zsh config"
check_symlink "$HOME/.xonshrc" "${SYM_DIR}/xonshrc" "Xonsh config"
check_symlink "$HOME/.vimrc" "${SYM_DIR}/vimrc" "Vim config"
check_symlink "$HOME/.exrc" "${SYM_DIR}/exrc" "Vi config"
check_symlink "$HOME/.tmux.conf" "${SYM_DIR}/tmux.conf" "Tmux config"
check_symlink "$HOME/.screenrc" "${SYM_DIR}/screenrc" "Screen config"
check_symlink "$HOME/.sqliterc" "${SYM_DIR}/sqliterc" "SQLite config"
check_symlink "$HOME/.psqlrc" "${SYM_DIR}/psqlrc" "PostgreSQL config"

# Special location symlinks
check_symlink "$HOME/.config/fish/config.fish" "${SYM_DIR}/config.fish" "Fish config"
check_symlink "$HOME/.config/nvim/init.vim" "${SYM_DIR}/init.vim" "Neovim config"

# Config symlinks
check_symlink "$HOME/.config/bat/config" "${CONFIG_DIR}/bat.conf" "Bat config"
check_symlink "$HOME/.config/htop/htoprc" "${CONFIG_DIR}/htoprc" "htop config"
check_symlink "$HOME/.config/ImageMagick/magick.xml" "${CONFIG_DIR}/magick.xml" "ImageMagick config"

echo ""
# 1}}}

# Check shared files {{{1
echo -e "${BLUE}Checking shared files...${NC}"

if [ -f "${DOTS_DIR}/shared/aliases.sh" ]; then
  echo -e "${GREEN}✓${NC} Shared aliases exist"
  ((CHECKS_PASSED++))
else
  echo -e "${RED}✗${NC} Shared aliases missing"
  ((CHECKS_FAILED++))
fi

if [ -f "${DOTS_DIR}/shared/functions.sh" ]; then
  echo -e "${GREEN}✓${NC} Shared functions exist"
  ((CHECKS_PASSED++))
else
  echo -e "${RED}✗${NC} Shared functions missing"
  ((CHECKS_FAILED++))
fi

echo ""
# 1}}}

# Check utilities {{{1
echo -e "${BLUE}Checking utilities...${NC}"

check_utility() {
  local cmd="$1"
  local name="$2"
  
  if command -v "$cmd" >/dev/null 2>&1; then
    local version
    version=$($cmd --version 2>/dev/null | head -n1 || echo "installed")
    echo -e "${GREEN}✓${NC} ${name}: ${version}"
    ((CHECKS_PASSED++))
    return 0
  else
    echo -e "${YELLOW}⚠${NC} ${name}: not installed"
    ((WARNINGS++))
    return 1
  fi
}

# Essential utilities
check_utility "tmux" "Tmux"
check_utility "vim" "Vim"
check_utility "git" "Git"

# Modern utilities (optional but recommended)
check_utility "bat" "bat"
check_utility "dust" "dust"
check_utility "htop" "htop"
check_utility "jq" "jq"
check_utility "yq" "yq"
check_utility "fzf" "fzf"

# Version managers
if [ -s "${HOME}/.nvm/nvm.sh" ]; then
  echo -e "${GREEN}✓${NC} nvm: installed"
  ((CHECKS_PASSED++))
else
  echo -e "${YELLOW}⚠${NC} nvm: not installed"
  ((WARNINGS++))
fi

if [ -f "${HOME}/.cargo/env" ]; then
  echo -e "${GREEN}✓${NC} rustup: installed"
  ((CHECKS_PASSED++))
else
  echo -e "${YELLOW}⚠${NC} rustup: not installed"
  ((WARNINGS++))
fi

echo ""
# 1}}}

# Check plugins {{{1
echo -e "${BLUE}Checking plugins...${NC}"

# Vim plugins
if [ -d "${HOME}/.vim/bundle/Vundle.vim" ]; then
  echo -e "${GREEN}✓${NC} Vim Vundle installed"
  ((CHECKS_PASSED++))
else
  echo -e "${YELLOW}⚠${NC} Vim Vundle not installed"
  ((WARNINGS++))
fi

# Tmux plugins
if [ -d "${HOME}/.tmux/plugins/tpm" ]; then
  echo -e "${GREEN}✓${NC} Tmux TPM installed"
  ((CHECKS_PASSED++))
else
  echo -e "${YELLOW}⚠${NC} Tmux TPM not installed"
  ((WARNINGS++))
fi

# Check if tmux plugins are installed
if [ -d "${HOME}/.tmux/plugins/tpm" ] && [ -d "${HOME}/.tmux/plugins/tmux-catppuccin" ]; then
  echo -e "${GREEN}✓${NC} Tmux plugins installed"
  ((CHECKS_PASSED++))
else
  echo -e "${YELLOW}⚠${NC} Tmux plugins may need installation (run 'Prefix + I' in tmux)"
  ((WARNINGS++))
fi

echo ""
# 1}}}

# Check config syntax {{{1
echo -e "${BLUE}Checking config syntax...${NC}"

# Check bash config
if bash -n "${SYM_DIR}/bashrc" 2>/dev/null; then
  echo -e "${GREEN}✓${NC} Bash config syntax valid"
  ((CHECKS_PASSED++))
else
  echo -e "${RED}✗${NC} Bash config has syntax errors"
  ((CHECKS_FAILED++))
fi

# Check zsh config
if command -v zsh >/dev/null 2>&1 && zsh -n "${SYM_DIR}/zshrc" 2>/dev/null; then
  echo -e "${GREEN}✓${NC} Zsh config syntax valid"
  ((CHECKS_PASSED++))
else
  echo -e "${YELLOW}⚠${NC} Zsh not available or config has issues"
  ((WARNINGS++))
fi

# Check tmux config
if command -v tmux >/dev/null 2>&1 && tmux -f "${SYM_DIR}/tmux.conf" list-commands >/dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} Tmux config syntax valid"
  ((CHECKS_PASSED++))
else
  echo -e "${YELLOW}⚠${NC} Tmux config check skipped (tmux not available or session required)"
  ((WARNINGS++))
fi

echo ""
# 1}}}

# Summary {{{1
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Summary:${NC}"
echo -e "  ${GREEN}Passed:${NC} ${CHECKS_PASSED}"
echo -e "  ${RED}Failed:${NC} ${CHECKS_FAILED}"
echo -e "  ${YELLOW}Warnings:${NC} ${WARNINGS}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

if [ $CHECKS_FAILED -eq 0 ]; then
  if [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed!${NC}"
    exit 0
  else
    echo -e "${YELLOW}⚠️  Checks passed with warnings${NC}"
    exit 0
  fi
else
  echo -e "${RED}❌ Some checks failed${NC}"
  exit 1
fi
# 1}}}


