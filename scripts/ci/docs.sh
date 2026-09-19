#!/usr/bin/env bash
# scripts/ci/docs.sh — generate --check + strict MkDocs build
# Used by .github/workflows/docs.yml and local docs validation.
# NOT invoked from scripts/ci/test.sh (unit suite stays free of MkDocs installs).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

REQ="${ROOT}/docs/requirements.txt"
MKDOCS=""

if command -v mkdocs >/dev/null 2>&1; then
	MKDOCS="$(command -v mkdocs)"
else
	VENV="${ROOT}/.tools/docs-venv"
	if [[ ! -x ${VENV}/bin/mkdocs ]]; then
		python3 -m venv "${VENV}"
		"${VENV}/bin/pip" install --upgrade pip
		"${VENV}/bin/pip" install -r "${REQ}"
	fi
	MKDOCS="${VENV}/bin/mkdocs"
fi

echo "=== generate --check ==="
python3 "${ROOT}/scripts/docs/generate_reference.py" --check

echo "=== mkdocs build --strict ==="
"${MKDOCS}" build --strict

echo "OK: docs CI passed"
