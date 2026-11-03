#!/usr/bin/env bash
# scripts/docs/generate.sh — regenerate docs/reference/generated + maintainer copies
# Also refreshes man pages and the Bash CLI synopsis from configs/help/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
# shellcheck source=../../helpers/python_runtime.sh
source "${ROOT}/helpers/python_runtime.sh"
PY="$(dots_find_python311)" || {
	echo "Error: Python >=3.11 required (stdlib tomllib)." >&2
	exit 1
}
"${PY}" "${ROOT}/scripts/docs/generate_usage.py"
"${PY}" "${ROOT}/scripts/docs/generate_manpages.py"
exec "${PY}" "${ROOT}/scripts/docs/generate_reference.py" "$@"
