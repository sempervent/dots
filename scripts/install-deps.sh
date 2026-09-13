#!/usr/bin/env bash
# Install missing dependencies for dotfiles
# Auto-detects package manager and installs utilities

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}📦 Installing dotfiles dependencies...${NC}\n"

# Detect OS and package manager {{{1
if [[ "$(uname -s)" == "Darwin" ]]; then
  OS="macOS"
  if command -v brew >/dev/null 2>&1; then
    PKG_MGR="brew"
    INSTALL_CMD="brew install"
  else
    echo -e "${RED}Error: Homebrew not found. Install from https://brew.sh${NC}"
    exit 1
  fi
elif command -v apt >/dev/null 2>&1; then
  OS="Linux (apt)"
  PKG_MGR="apt"
  INSTALL_CMD="sudo apt install -y"
elif command -v yay >/dev/null 2>&1; then
  OS="Linux (Arch)"
  PKG_MGR="yay"
  INSTALL_CMD="yay -S --noconfirm"
elif command -v pacman >/dev/null 2>&1; then
  OS="Linux (Arch)"
  PKG_MGR="pacman"
  INSTALL_CMD="sudo pacman -S --noconfirm"
else
  echo -e "${RED}Error: Unsupported package manager${NC}"
  exit 1
fi

echo -e "${CYAN}Platform:${NC} ${OS}"
echo -e "${CYAN}Package Manager:${NC} ${PKG_MGR}\n"
# 1}}}

# Package lists by category {{{1
declare -a ESSENTIAL_PACKAGES=()
declare -a MODERN_PACKAGES=()
declare -a DEV_PACKAGES=()
declare -a MEDIA_PACKAGES=()
declare -a FUN_PACKAGES=()

if [[ "$PKG_MGR" == "brew" ]]; then
  ESSENTIAL_PACKAGES=(tmux vim git bash)
  MODERN_PACKAGES=(bat dust fd ripgrep eza zoxide git-delta direnv atuin procs htop)
  DEV_PACKAGES=(jq yq fzf tig lazygit gh shellcheck)
  MEDIA_PACKAGES=(imagemagick ffmpeg)
  FUN_PACKAGES=(figlet fortune cowsay)
  LOLCAT_INSTALL="gem install lolcat"
elif [[ "$PKG_MGR" == "apt" ]]; then
  ESSENTIAL_PACKAGES=(tmux vim git bash)
  MODERN_PACKAGES=(bat fd-find ripgrep eza zoxide direnv htop)
  DEV_PACKAGES=(jq yq fzf tig lazygit gh)
  MEDIA_PACKAGES=(imagemagick ffmpeg)
  FUN_PACKAGES=(figlet fortune-mod cowsay)
  # Note: dust, procs may need cargo install
  CARGO_PACKAGES=(dust procs)
  LOLCAT_INSTALL="gem install lolcat"
elif [[ "$PKG_MGR" == "yay" ]] || [[ "$PKG_MGR" == "pacman" ]]; then
  ESSENTIAL_PACKAGES=(tmux vim git bash)
  MODERN_PACKAGES=(bat dust fd ripgrep eza procs htop)
  DEV_PACKAGES=(jq yq fzf tig lazygit github-cli)
  MEDIA_PACKAGES=(imagemagick ffmpeg)
  FUN_PACKAGES=(figlet fortune-mod cowsay)
  LOLCAT_INSTALL="gem install lolcat"
fi
# 1}}}

# Installation functions {{{1
install_packages() {
  local category="$1"
  shift
  local packages=("$@")
  
  if [ ${#packages[@]} -eq 0 ]; then
    return 0
  fi
  
  echo -e "${BLUE}Installing ${category} packages...${NC}"
  for pkg in "${packages[@]}"; do
    if command -v "$pkg" >/dev/null 2>&1; then
      echo -e "  ${GREEN}✓${NC} ${pkg} already installed"
    else
      echo -e "  ${YELLOW}→${NC} Installing ${pkg}..."
      if $INSTALL_CMD "$pkg"; then
        echo -e "  ${GREEN}✓${NC} ${pkg} installed"
      else
        echo -e "  ${RED}✗${NC} ${pkg} installation failed"
      fi
    fi
  done
  echo ""
}

install_cargo_packages() {
  if [ ${#CARGO_PACKAGES[@]} -eq 0 ]; then
    return 0
  fi
  
  if ! command -v cargo >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠${NC} Cargo not found. Install Rust first:"
    echo -e "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    return 1
  fi
  
  echo -e "${BLUE}Installing Rust packages...${NC}"
  for pkg in "${CARGO_PACKAGES[@]}"; do
    if command -v "$pkg" >/dev/null 2>&1; then
      echo -e "  ${GREEN}✓${NC} ${pkg} already installed"
    else
      echo -e "  ${YELLOW}→${NC} Installing ${pkg}..."
      if cargo install "$pkg"; then
        echo -e "  ${GREEN}✓${NC} ${pkg} installed"
      else
        echo -e "  ${RED}✗${NC} ${pkg} installation failed"
      fi
    fi
  done
  echo ""
}

install_version_managers() {
  echo -e "${BLUE}Checking version managers...${NC}"
  
  # nvm
  if [ ! -s "${HOME}/.nvm/nvm.sh" ]; then
    echo -e "  ${YELLOW}→${NC} Installing nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    echo -e "  ${GREEN}✓${NC} nvm installed"
  else
    echo -e "  ${GREEN}✓${NC} nvm already installed"
  fi
  
  # rustup
  if [ ! -f "${HOME}/.cargo/env" ]; then
    echo -e "  ${YELLOW}→${NC} Installing rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    echo -e "  ${GREEN}✓${NC} rustup installed"
  else
    echo -e "  ${GREEN}✓${NC} rustup already installed"
  fi
  echo ""
}
# 1}}}

# Main installation {{{1
# Essential packages
install_packages "Essential" "${ESSENTIAL_PACKAGES[@]}"

# Modern replacements
read -p "Install modern replacements (bat, dust, htop, etc.)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  install_packages "Modern" "${MODERN_PACKAGES[@]}"
fi

# Development tools
read -p "Install development tools (jq, yq, fzf, etc.)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  install_packages "Development" "${DEV_PACKAGES[@]}"
fi

# Media tools
read -p "Install media tools (imagemagick, ffmpeg)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  install_packages "Media" "${MEDIA_PACKAGES[@]}"
fi

# Fun tools
read -p "Install fun tools (figlet, fortune, cowsay, lolcat)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  install_packages "Fun" "${FUN_PACKAGES[@]}"
  if [[ -n "$LOLCAT_INSTALL" ]]; then
    if ! command -v lolcat >/dev/null 2>&1; then
      echo -e "${BLUE}Installing lolcat...${NC}"
      eval "$LOLCAT_INSTALL"
      echo ""
    fi
  fi
fi

# Cargo packages (if needed)
if [ ${#CARGO_PACKAGES[@]} -gt 0 ]; then
  read -p "Install Rust packages (dust, procs) via cargo? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    install_cargo_packages
  fi
fi

# Version managers
read -p "Install version managers (nvm, rustup)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  install_version_managers
fi

echo -e "${GREEN}✅ Dependency installation complete!${NC}\n"

# Run health check
if [ -f "${DOTS_DIR:-$HOME/dots}/scripts/check.sh" ]; then
  read -p "Run health check now? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "${DOTS_DIR:-$HOME/dots}/scripts/check.sh"
  fi
fi
# 1}}}


