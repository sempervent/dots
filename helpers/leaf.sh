# helpers/leaf.sh — leaf markdown viewer (RivoLink) + shell completions
#
# Binary name: leaf  (Homebrew formula: leaf-markdown-viewer)
# Conflicts with deprecated Homebrew `leaf` (vrongmeal reloader) and leaf-proxy.
#
# Completions: dump into XDG share and load from dots shell configs.
# Do NOT run bare `leaf --auto-complete` — it appends to ~/.zshrc / ~/.bashrc.

DOTS_LEAF_COMPLETIONS_DIR="${DOTS_LEAF_COMPLETIONS_DIR:-${HOME}/.local/share/leaf/completions}"
DOTS_LEAF_INSTALL_URL="${DOTS_LEAF_INSTALL_URL:-https://raw.githubusercontent.com/RivoLink/leaf/main/scripts/install.sh}"

_dots_leaf_is_markdown_viewer() {
  local bin="$1"
  [[ -x "${bin}" ]] || return 1
  # RivoLink leaf speaks -V / --auto-complete; vrongmeal reloader does not.
  "${bin}" -V >/dev/null 2>&1 || return 1
  "${bin}" --help 2>&1 | grep -q -- '--auto-complete' || return 1
}

_dots_leaf_resolve_bin() {
  local cand
  for cand in \
    "$(command -v leaf 2>/dev/null || true)" \
    "${HOME}/.local/bin/leaf" \
    "/opt/homebrew/bin/leaf" \
    "/usr/local/bin/leaf"
  do
    [[ -n "${cand}" ]] || continue
    if _dots_leaf_is_markdown_viewer "${cand}"; then
      printf '%s\n' "${cand}"
      return 0
    fi
  done
  return 1
}

_dots_leaf_retire_conflicting_brew_leaf() {
  # Homebrew formula `leaf` (file reloader) shadows leaf-markdown-viewer.
  if ! command -v brew >/dev/null 2>&1; then
    return 0
  fi
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "[dry-run] would check/uninstall conflicting brew leaf (reloader)"
    return 0
  fi
  if brew list --formula leaf >/dev/null 2>&1; then
    echo "Note: uninstalling deprecated Homebrew leaf (reloader) — conflicts with leaf-markdown-viewer"
    brew uninstall --formula leaf || echo "Warn: could not uninstall brew leaf" >&2
  fi
}

_dots_leaf_install_brew() {
  command -v brew >/dev/null 2>&1 || return 1
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "[dry-run] brew install leaf-markdown-viewer"
    return 0
  fi
  if brew list --formula leaf-markdown-viewer >/dev/null 2>&1; then
    echo "OK: leaf-markdown-viewer already installed (brew)"
    return 0
  fi
  brew install leaf-markdown-viewer
}

_dots_leaf_install_curl() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] curl install leaf → ${HOME}/.local/bin"
    return 0
  fi
  ensure_dir "${HOME}/.local/bin"
  # Official installer; installs into first arg (default ~/.local/bin)
  curl -fsSL "${DOTS_LEAF_INSTALL_URL}" | sh -s -- "${HOME}/.local/bin"
}

dots_install_leaf() {
  echo "=== leaf (markdown viewer) ==="
  if _dots_leaf_resolve_bin >/dev/null 2>&1; then
    echo "OK: leaf markdown viewer present ($(_dots_leaf_resolve_bin))"
    return 0
  fi

  _dots_leaf_retire_conflicting_brew_leaf

  if command -v brew >/dev/null 2>&1; then
    if _dots_leaf_install_brew; then
      if _dots_leaf_resolve_bin >/dev/null 2>&1 || [[ "${DRY_RUN}" -eq 1 ]]; then
        return 0
      fi
      echo "Warn: brew leaf-markdown-viewer did not yield leaf binary — trying curl installer"
    fi
  fi

  _dots_leaf_install_curl || {
    echo "Error: failed to install leaf markdown viewer" >&2
    return 1
  }
}

dots_install_leaf_completions() {
  local leaf_bin
  leaf_bin="$(_dots_leaf_resolve_bin 2>/dev/null || true)"
  if [[ -z "${leaf_bin}" ]]; then
    echo "Note: leaf not found — skip completions"
    return 0
  fi

  echo "=== leaf shell completions ==="
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] dump leaf completions → ${DOTS_LEAF_COMPLETIONS_DIR}"
    return 0
  fi

  ensure_dir "${DOTS_LEAF_COMPLETIONS_DIR}"
  ensure_dir "${HOME}/.config/fish/completions"

  # Dump only — never bare --auto-complete (mutates shell rc files).
  "${leaf_bin}" --auto-complete zsh:dump >"${DOTS_LEAF_COMPLETIONS_DIR}/_leaf"
  "${leaf_bin}" --auto-complete bash:dump >"${DOTS_LEAF_COMPLETIONS_DIR}/leaf.bash"
  "${leaf_bin}" --auto-complete fish:dump >"${HOME}/.config/fish/completions/leaf.fish"

  # Optional extras when the binary supports them
  if "${leaf_bin}" --auto-complete nushell:dump >/dev/null 2>&1; then
    "${leaf_bin}" --auto-complete nushell:dump >"${DOTS_LEAF_COMPLETIONS_DIR}/leaf.nu" || true
  fi
  if "${leaf_bin}" --auto-complete powershell:dump >/dev/null 2>&1; then
    "${leaf_bin}" --auto-complete powershell:dump >"${DOTS_LEAF_COMPLETIONS_DIR}/leaf.ps1" || true
  fi

  # Strip any leftover auto-complete hooks leaf may have written earlier
  _dots_leaf_scrub_rc_hooks

  echo "OK: leaf completions → ${DOTS_LEAF_COMPLETIONS_DIR} (+ fish)"
}

_dots_leaf_scrub_rc_hooks() {
  local rc line
  line='source .*/\.local/share/leaf/completions/_leaf'
  for rc in "${HOME}/.zshrc" "${HOME}/.bashrc" "${HOME}/.zprofile"; do
    [[ -f "${rc}" ]] || continue
    # Only edit if it is not our managed symlink content needing a surgical delete
    if rg -q 'local/share/leaf/completions' "${rc}" 2>/dev/null \
      || grep -q 'local/share/leaf/completions' "${rc}" 2>/dev/null; then
      # Portable in-place delete of leaf-injected source lines
      if command -v gsed >/dev/null 2>&1; then
        gsed -i '\|local/share/leaf/completions|d' "${rc}" || true
      elif sed --version >/dev/null 2>&1; then
        sed -i '\|local/share/leaf/completions|d' "${rc}" || true
      else
        # BSD sed
        sed -i '' '\|local/share/leaf/completions|d' "${rc}" || true
      fi
    fi
  done
}

dots_setup_leaf() {
  dots_install_leaf || return 1
  dots_install_leaf_completions || return 1
  if command -v leaf >/dev/null 2>&1; then
    leaf -V 2>/dev/null || true
  fi
}
