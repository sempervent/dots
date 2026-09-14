#!/usr/bin/env bash
# Opt-in OpenCode smoke: temp dir only; read-only inspect; does not mutate DOTS.
#
# Temp dirs are outside the project worktree, so OpenCode asks for
# external_directory — pass --auto for noninteractive smoke.
set -euo pipefail

DOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT="${OPENCODE_AGENT_LAUNCHER:-${HOME}/.local/bin/opencode-agent}"
if [[ ! -x "${AGENT}" ]] && [[ ! -L "${AGENT}" ]]; then
  AGENT="${DOTS_DIR}/scripts/opencode-agent"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-opencode-smoke.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

printf 'hello from dots opencode smoke\n' >"${TMP}/note.txt"

echo "OpenCode smoke in ${TMP}"
"${AGENT}" run \
  --dir "${TMP}" \
  --agent plan \
  --auto \
  --prompt "Read note.txt and reply with only the file contents. Do not modify any files." \
  --timeout "${OPENCODE_SMOKE_TIMEOUT:-600}"
