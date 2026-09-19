#!/usr/bin/env bash
# scripts/docs/generate.sh — regenerate docs/reference/generated + maintainer copies
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
exec python3 "${ROOT}/scripts/docs/generate_reference.py" "$@"
