#!/usr/bin/env bash
# Dependency checker - Shows what utilities are installed/missing

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}📦 Checking dotfiles dependencies...${NC}\n"

# Detect OS
if [[ "$(uname -s)" == "Darwin" ]]; then
  OS="macOS"
  PKG_MGR="brew"
elif command -v apt >/dev/null 2>&1; then
  OS="Linux (apt)"
  PKG_MGR="apt"
elif command -v yay >/dev/null 2>&1; then
  OS="Linux (Arch)"
  PKG_MGR="yay"
else
  OS="Unknown"
  PKG_MGR="unknown"
fi

echo -e "${CYAN}Platform:${NC} ${OS}"
echo -e "${CYAN}Package Manager:${NC} ${PKG_MGR}\n"

# Utility definitions {{{1
declare -A UTILITIES=(
  # Essential
  ["tmux"]="essential"
  ["vim"]="essential"
  ["git"]="essential"
  ["bash"]="essential"
  
  # Modern replacements
  ["bat"]="modern"
  ["dust"]="modern"
  ["fd"]="modern"
  ["ripgrep"]="modern"
  ["eza"]="modern"
  ["procs"]="modern"
  ["htop"]="modern"
  
  # Development
  ["jq"]="dev"
  ["yq"]="dev"
  ["fzf"]="dev"
  ["tig"]="dev"
  ["lazygit"]="dev"
  ["gh"]="dev"
  
  # Media
  ["imagemagick"]="media"
  ["ffmpeg"]="media"
  
  # Fun
  ["figlet"]="fun"
  ["fortune"]="fun"
  ["cowsay"]="fun"
  ["lolcat"]="fun"
)

declare -A INSTALL_COMMANDS=(
  # macOS
  ["bat|brew"]="brew install bat"
  ["dust|brew"]="brew install dust"
  ["fd|brew"]="brew install fd"
  ["ripgrep|brew"]="brew install ripgrep"
  ["eza|brew"]="brew install eza"
  ["procs|brew"]="brew install procs"
  ["htop|brew"]="brew install htop"
  ["jq|brew"]="brew install jq"
  ["yq|brew"]="brew install yq"
  ["fzf|brew"]="brew install fzf"
  ["tig|brew"]="brew install tig"
  ["lazygit|brew"]="brew install lazygit"
  ["gh|brew"]="brew install gh"
  ["imagemagick|brew"]="brew install imagemagick"
  ["ffmpeg|brew"]="brew install ffmpeg"
  ["figlet|brew"]="brew install figlet"
  ["fortune|brew"]="brew install fortune"
  ["cowsay|brew"]="brew install cowsay"
  ["lolcat|brew"]="gem install lolcat"
  
  # Linux apt
  ["bat|apt"]="apt install bat"
  ["dust|apt"]="cargo install du-dust"
  ["fd|apt"]="apt install fd-find"
  ["ripgrep|apt"]="apt install ripgrep"
  ["eza|apt"]="apt install eza"
  ["procs|apt"]="cargo install procs"
  ["htop|apt"]="apt install htop"
  ["jq|apt"]="apt install jq"
  ["yq|apt"]="apt install yq"
  ["fzf|apt"]="apt install fzf"
  ["tig|apt"]="apt install tig"
  ["lazygit|apt"]="apt install lazygit"
  ["gh|apt"]="apt install gh"
  ["imagemagick|apt"]="apt install imagemagick"
  ["ffmpeg|apt"]="apt install ffmpeg"
  ["figlet|apt"]="apt install figlet"
  ["fortune|apt"]="apt install fortune-mod"
  ["cowsay|apt"]="apt install cowsay"
  ["lolcat|apt"]="gem install lolcat"
)

INSTALLED=()
MISSING=()
# 1}}}

# Check utilities {{{1
check_util() {
  local util="$1"
  local category="$2"
  
  if command -v "$util" >/dev/null 2>&1; then
    local version
    version=$($util --version 2>/dev/null | head -n1 | cut -d' ' -f1-3 || echo "installed")
    echo -e "  ${GREEN}✓${NC} ${util} - ${version}"
    INSTALLED+=("$util")
    return 0
  else
    local install_cmd="${INSTALL_COMMANDS["${util}|${PKG_MGR}"]}"
    if [ -z "$install_cmd" ]; then
      install_cmd="${util} (manual install required)"
    fi
    echo -e "  ${RED}✗${NC} ${util} - ${install_cmd}"
    MISSING+=("$util:$install_cmd")
    return 1
  fi
}

# Check by category
echo -e "${BLUE}Essential Tools:${NC}"
for util in tmux vim git bash; do
  check_util "$util" "essential"
done

echo -e "\n${BLUE}Modern Replacements:${NC}"
for util in bat dust fd ripgrep eza procs htop; do
  check_util "$util" "modern"
done

echo -e "\n${BLUE}Development Tools:${NC}"
for util in jq yq fzf tig lazygit gh; do
  check_util "$util" "dev"
done

echo -e "\n${BLUE}Media Tools:${NC}"
for util in imagemagick ffmpeg; do
  check_util "$util" "media"
done

echo -e "\n${BLUE}Fun Tools:${NC}"
for util in figlet fortune cowsay lolcat; do
  check_util "$util" "fun"
done

# Version managers {{{2
echo -e "\n${BLUE}Version Managers:${NC}"

if [ -s "${HOME}/.nvm/nvm.sh" ]; then
  echo -e "  ${GREEN}✓${NC} nvm"
  INSTALLED+=("nvm")
else
  echo -e "  ${RED}✗${NC} nvm - curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash"
  MISSING+=("nvm:curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash")
fi

if [ -f "${HOME}/.cargo/env" ]; then
  echo -e "  ${GREEN}✓${NC} rustup"
  INSTALLED+=("rustup")
else
  echo -e "  ${RED}✗${NC} rustup - curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
  MISSING+=("rustup:curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh")
fi
# 2}}}
# 1}}}

# Summary {{{1
echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Summary:${NC}"
echo -e "  ${GREEN}Installed:${NC} ${#INSTALLED[@]}"
echo -e "  ${RED}Missing:${NC} ${#MISSING[@]}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ ${#MISSING[@]} -gt 0 ]; then
  echo -e "\n${YELLOW}Install missing utilities:${NC}\n"
  for item in "${MISSING[@]}"; do
    IFS=':' read -r util cmd <<< "$item"
    echo -e "${CYAN}# Install ${util}${NC}"
    echo -e "${cmd}\n"
  done
  
  # Generate install script
  INSTALL_SCRIPT="${DOTS_DIR}/.install-missing.sh"
  {
    echo "#!/usr/bin/env bash"
    echo "# Auto-generated install script for missing utilities"
    echo ""
    for item in "${MISSING[@]}"; do
      IFS=':' read -r util cmd <<< "$item"
      echo "# Install $util"
      echo "$cmd"
      echo ""
    done
  } > "$INSTALL_SCRIPT"
  chmod +x "$INSTALL_SCRIPT"
  echo -e "${CYAN}Install script generated:${NC} ${INSTALL_SCRIPT}"
fi
# 1}}}


