# helpers/path_hygiene.sh — retire PATH-shadowing shims safely (DOTS)
#
# Hermes git-install historically placed:
#   ~/.local/bin/{node,npm,npx} → ~/.hermes/node/bin/...
#   ~/.local/bin/hermes         → git venv wrapper
#
# DOTS canonical:
#   Node   → fnm (configs/node/default.toml)
#   Hermes → Homebrew hermes-agent (/opt/homebrew/bin/hermes)
#
# Keep ~/.hermes/node/ and ~/.hermes/hermes-agent/ intact (Hermes-private).
# Only retire the ~/.local/bin public shims that pollute non-DOTS shells.
#
# Requires: DRY_RUN, HOME, ensure_dir (optional), OLD_DOTS or fallback

dots_retire_local_shim() {
  local path="$1" reason="$2"
  local stamp dest dir
  [[ -e "${path}" ]] || [[ -L "${path}" ]] || return 0

  dir="${HOME}/.local/bin/.dots-retired"
  stamp="$(date +%Y-%m-%d_%H%M%S 2>/dev/null || echo retired)"
  dest="${dir}/$(basename "${path}").${stamp}"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "[dry-run] retire ${path} → ${dest} (${reason})"
    return 0
  fi

  mkdir -p "${dir}"
  echo "Retiring PATH shim: ${path}"
  echo "  reason: ${reason}"
  echo "  backup: ${dest}"
  mv "${path}" "${dest}"
}

# True when symlink target is under ~/.hermes/node/
_dots_is_hermes_node_shim() {
  local path="$1" target
  [[ -L "${path}" ]] || return 1
  target="$(readlink "${path}" 2>/dev/null || true)"
  case "${target}" in
    "${HOME}/.hermes/node/"*|*/.hermes/node/*) return 0 ;;
  esac
  # resolve one level
  if [[ "${target}" != /* ]]; then
    target="$(dirname "${path}")/${target}"
  fi
  case "$(readlink -f "${path}" 2>/dev/null || true)" in
    "${HOME}/.hermes/node/"*) return 0 ;;
  esac
  return 1
}

_dots_is_hermes_git_wrapper() {
  local path="$1"
  [[ -f "${path}" ]] || return 1
  [[ -x "${path}" ]] || return 1
  # git-install wrapper execs ~/.hermes/hermes-agent/venv/bin/python
  rg -q '\.hermes/hermes-agent/venv/bin/python' "${path}" 2>/dev/null
}

dots_path_hygiene() {
  echo "=== PATH hygiene (Node / Hermes shims) ==="
  local n

  for n in node npm npx; do
    if _dots_is_hermes_node_shim "${HOME}/.local/bin/${n}"; then
      dots_retire_local_shim "${HOME}/.local/bin/${n}" \
        "Hermes-private Node belongs in ~/.hermes/node; interactive Node is fnm"
    elif [[ -L "${HOME}/.local/bin/${n}" ]] || [[ -e "${HOME}/.local/bin/${n}" ]]; then
      echo "Note: ~/.local/bin/${n} present but not a Hermes node shim — left alone"
    fi
  done

  if _dots_is_hermes_git_wrapper "${HOME}/.local/bin/hermes"; then
    if command -v brew >/dev/null 2>&1 && brew list hermes-agent >/dev/null 2>&1; then
      dots_retire_local_shim "${HOME}/.local/bin/hermes" \
        "Canonical Hermes is Homebrew hermes-agent; git wrapper retired from PATH"
    else
      echo "Note: ~/.local/bin/hermes is git-install wrapper; Homebrew hermes-agent not detected — left in place"
    fi
  fi

  if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
    echo "OK: PATH hygiene pass complete (Hermes tree under ~/.hermes/ preserved)"
  fi
}
