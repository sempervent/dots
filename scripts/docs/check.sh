#!/usr/bin/env bash
# scripts/docs/check.sh — drift check + strict MkDocs build
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

VENV="${ROOT}/.tools/docs-venv"
REQ="${ROOT}/docs/requirements.txt"

if [[ ! -x ${VENV}/bin/mkdocs ]]; then
	echo "Creating docs venv at ${VENV}"
	python3 -m venv "${VENV}"
	# Prefer hashed lock when present
	"${VENV}/bin/pip" install --upgrade pip
	"${VENV}/bin/pip" install -r "${REQ}"
fi

echo "=== generate --check ==="
python3 "${ROOT}/scripts/docs/generate_reference.py" --check

echo "=== mkdocs build --strict ==="
"${VENV}/bin/mkdocs" build --strict

echo "OK: docs check passed"
