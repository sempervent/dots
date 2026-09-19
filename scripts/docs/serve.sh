#!/usr/bin/env bash
# scripts/docs/serve.sh — local MkDocs preview
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

VENV="${ROOT}/.tools/docs-venv"
REQ="${ROOT}/docs/requirements.txt"

if [[ ! -x ${VENV}/bin/mkdocs ]]; then
	python3 -m venv "${VENV}"
	"${VENV}/bin/pip" install --upgrade pip
	"${VENV}/bin/pip" install -r "${REQ}"
fi

# Ensure generated pages exist before serve
python3 "${ROOT}/scripts/docs/generate_reference.py"

exec "${VENV}/bin/mkdocs" serve "$@"
