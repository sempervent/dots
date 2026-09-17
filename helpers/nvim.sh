# helpers/nvim.sh — deploy Neovim Lua config from configs/nvim
#
# Requires: DIR, DRY_RUN, ensure_dir
# Pre-change content is captured by helpers/backup.sh collision snapshot.

dots_deploy_nvim() {
  echo "=== Neovim ==="
  local src="${DIR}/configs/nvim"
  local dest="${HOME}/.config/nvim"

  if [[ ! -f "${src}/init.lua" ]]; then
    echo "Skip: missing ${src}/init.lua"
    return 0
  fi

  ensure_dir "${HOME}/.config"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] deploy Neovim config ${src} → ${dest}"
    return 0
  fi

  if [[ -e "${dest}" ]] && [[ ! -L "${dest}" ]]; then
    if [[ -f "${dest}/init.lua" ]] && cmp -s "${src}/init.lua" "${dest}/init.lua" 2>/dev/null; then
      :
    else
      echo "Replace ${dest}"
      rm -rf "${dest}"
    fi
  elif [[ -L "${dest}" ]]; then
    echo "Replace symlink ${dest}"
    rm -f "${dest}"
  fi

  mkdir -p "${dest}/lua/config" "${dest}/lua/plugins"
  cp "${src}/init.lua" "${dest}/init.lua"
  cp -R "${src}/lua/config/." "${dest}/lua/config/"
  cp -R "${src}/lua/plugins/." "${dest}/lua/plugins/"

  if [[ -f "${dest}/init.vim" ]]; then
    rm -f "${dest}/init.vim"
    echo "Removed legacy init.vim (Neovim is managed editor)"
  fi

  echo "OK: Neovim config deployed → ${dest}"

  if command -v nvim >/dev/null 2>&1; then
    nvim --headless "+Lazy! sync" "+qa" >/dev/null 2>&1 || \
      echo "Note: Lazy sync deferred (run nvim once to install plugins)"
  fi
}
