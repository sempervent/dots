#!/usr/bin/env bash
# Update dotfiles: git pull + setup.sh (Homebrew-managed tools update via brew).
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
DOTS_DIR="${DOTS_DIR:-${HOME}/dots}"
OLD_DIR="$(pwd)"

echo -e "${BLUE}Updating dotfiles...${NC}"
[[ -d "${DOTS_DIR}/.git" ]] || { echo -e "${RED}Not a git repo: ${DOTS_DIR}${NC}"; exit 1; }
cd "${DOTS_DIR}"

git pull

echo -e "${BLUE}Re-running setup (no AI components unless you pass --with)...${NC}"
bash "${DOTS_DIR}/setup.sh"

# Homebrew-owned updates (do not pull Ollama models; do not run hermes git updater)
if command -v brew >/dev/null 2>&1; then
  echo -e "${BLUE}Optional: brew upgrade for Brewfile packages${NC}"
  echo "  brew bundle --file=${DOTS_DIR}/brew/Brewfile"
  echo "  (optional: brew bundle --file=brew/Brewfile.herdr|.hermes|.ollama|.archify|.drawthings|.opencode|.codex|.cursor|.fluidvoice|.images|.tex|.mactools after --with)"
fi

if [[ -f "${DOTS_DIR}/scripts/check.sh" ]]; then
  bash "${DOTS_DIR}/scripts/check.sh" || true
fi

echo -e "${GREEN}Update complete${NC}"
cd "${OLD_DIR}"
