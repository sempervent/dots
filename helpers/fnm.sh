# helpers/fnm.sh — install and configure fnm-managed default Node (DOTS)
#
# Requires (from setup.sh): DIR, DRY_RUN, run_cmd, ensure_dir
# Policy file: configs/node/default.toml

dots_node_default_version() {
  local policy="${DIR}/configs/node/default.toml"
  if [[ ! -f "${policy}" ]]; then
    printf '%s\n' "24"
    return 0
  fi
  if declare -F dots_toml_query >/dev/null 2>&1; then
    dots_toml_query "${policy}" <<'PY'
print(str(data.get("version") or "24").strip() or "24")
PY
    return 0
  fi
  printf '%s\n' "24"
}

dots_setup_fnm_node() {
  echo "=== fnm / Node ==="
  local ver
  ver="$(dots_node_default_version)"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] ensure fnm installed; install Node ${ver} if absent; fnm default ${ver}"
    return 0
  fi

  if ! command -v fnm >/dev/null 2>&1; then
    echo "Warn: fnm not on PATH yet (Homebrew install may have just finished)."
    # Try common Homebrew locations
    if [[ -x /opt/homebrew/bin/fnm ]]; then
      eval "$(/opt/homebrew/bin/fnm env --shell bash)"
    elif [[ -x /usr/local/bin/fnm ]]; then
      eval "$(/usr/local/bin/fnm env --shell bash)"
    else
      echo "Warn: fnm missing; skip Node default install"
      return 0
    fi
  else
    eval "$(fnm env --shell bash)"
  fi

  # Do not auto-upgrade majors: only install if this version/alias is absent.
  if fnm list 2>/dev/null | rg -q "v?${ver}(\\.|$)|${ver} "; then
    echo "OK: fnm already has Node ${ver}"
  else
    echo "Installing Node ${ver} via fnm..."
    fnm install "${ver}" || {
      echo "Warn: fnm install ${ver} failed" >&2
      return 0
    }
  fi

  # Set as default only when default is unset or already this line
  local current_default
  current_default="$(fnm list 2>/dev/null | rg -o 'default[^)]*|lts-latest' || true)"
  fnm default "${ver}" >/dev/null 2>&1 || fnm default "$(fnm list | rg -o "v${ver}[^\s]*" | head -1 | tr -d '[:space:]')" || true
  eval "$(fnm env --shell bash)"
  echo "OK: fnm $(fnm --version 2>/dev/null) current=$(fnm current 2>/dev/null) node=$(node --version 2>/dev/null) npm=$(npm --version 2>/dev/null)"

  if [[ -L "${HOME}/.local/bin/node" ]] && readlink "${HOME}/.local/bin/node" 2>/dev/null | rg -q '\.hermes/node'; then
    echo "Note: ~/.local/bin/node still points at Hermes private Node."
    echo "      PATH hygiene should retire it on the next setup run."
  fi
}
