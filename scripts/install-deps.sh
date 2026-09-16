#!/usr/bin/env bash
# scripts/install-deps.sh — compatibility wrapper
#
# Canonical provisioning is:
#   ./bootstrap.sh --profile <name>
#   ./setup.sh --packages core,modern,…
#
# This script remains for older muscle memory and forwards to bootstrap base.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Note: install-deps.sh is a compatibility wrapper."
echo "      Prefer: ${DIR}/bootstrap.sh --profile base|home|work|server"
echo ""
exec "${DIR}/bootstrap.sh" --profile base "$@"
