#!/usr/bin/env bash
# Update script for dotfiles
# Pulls latest changes and re-applies setup

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DOTS_DIR="${DOTS_DIR:-${HOME}/dots}"
OLD_DIR="$(pwd)"

echo -e "${BLUE}🔄 Updating dotfiles...${NC}\n"

# Check if we're in a git repo
if [ ! -d "${DOTS_DIR}/.git" ]; then
  echo -e "${RED}Error: ${DOTS_DIR} is not a git repository${NC}"
  exit 1
fi

cd "$DOTS_DIR"

# Backup current state
echo -e "${BLUE}📦 Creating backup...${NC}"
BACKUP_DIR="${HOME}/.old_dots/update_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup current symlinks
for file in "$HOME"/.{bashrc,zshrc,xonshrc,vimrc,exrc,tmux.conf,screenrc}; do
  if [ -L "$file" ]; then
    cp -L "$file" "$BACKUP_DIR/$(basename $file)" 2>/dev/null || true
  fi
done

# Pull latest changes
echo -e "${BLUE}⬇️  Pulling latest changes...${NC}"
if git pull; then
  echo -e "${GREEN}✓${NC} Latest changes pulled"
else
  echo -e "${RED}✗${NC} Failed to pull changes"
  exit 1
fi

# Show what changed
echo -e "\n${BLUE}📋 Recent changes:${NC}"
git log --oneline -10 || true

# Re-run setup
echo -e "\n${BLUE}🔧 Re-running setup...${NC}"
if [ -f "${DOTS_DIR}/setup.sh" ]; then
  bash "${DOTS_DIR}/setup.sh"
else
  echo -e "${RED}✗${NC} setup.sh not found"
  exit 1
fi

# Run health check
if [ -f "${DOTS_DIR}/scripts/check.sh" ]; then
  echo -e "\n${BLUE}🔍 Running health check...${NC}"
  bash "${DOTS_DIR}/scripts/check.sh" || true
fi

echo -e "\n${GREEN}✅ Update complete!${NC}"
echo -e "Backup saved to: ${BACKUP_DIR}"

cd "$OLD_DIR"


