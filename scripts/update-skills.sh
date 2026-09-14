#!/usr/bin/env bash
# update-skills.sh — opt-in update for curated Engineering Pack skills
# Does NOT run automatically during ./setup.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
DRY_RUN="${DRY_RUN:-0}"

# shellcheck source=helpers/agent_skills.sh
source "${DIR}/helpers/agent_skills.sh"
# shellcheck source=helpers/skills_pack.sh
source "${DIR}/helpers/skills_pack.sh"

ensure_dir() { mkdir -p "$1"; }

echo "=== DOTS skills update (curated pack only) ==="
dots_update_skills_pack
echo "Done. Re-run ./scripts/check.sh to verify discovery."
