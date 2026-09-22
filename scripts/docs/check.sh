#!/usr/bin/env bash
# scripts/docs/check.sh — drift check + strict MkDocs build
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
# shellcheck source=../../helpers/python_runtime.sh
source "${ROOT}/helpers/python_runtime.sh"
PY="$(dots_find_python311)" || {
	echo "Error: Python >=3.11 required (stdlib tomllib)." >&2
	exit 1
}

VENV="${ROOT}/.tools/docs-venv"
REQ="${ROOT}/docs/requirements.txt"

if [[ ! -x ${VENV}/bin/mkdocs ]]; then
	echo "Creating docs venv at ${VENV}"
	"${PY}" -m venv "${VENV}"
	# Prefer hashed lock when present
	"${VENV}/bin/pip" install --upgrade pip
	"${VENV}/bin/pip" install -r "${REQ}"
fi

echo "=== generate --check ==="
"${PY}" "${ROOT}/scripts/docs/generate_reference.py" --check

echo "=== mkdocs build --strict ==="
"${VENV}/bin/mkdocs" build --strict

echo "OK: docs check passed"
