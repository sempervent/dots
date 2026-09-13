#!/usr/bin/env bash
# Shared compatibility shims — prefer shell/ going forward.
# Kept so older docs/scripts that source shared/* still work.
DOTS_DIR="${DOTS_DIR:-${HOME}/dots}"
# shellcheck disable=SC1091
. "${DOTS_DIR}/shell/aliases.sh"
