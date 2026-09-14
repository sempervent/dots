# helpers/nvim.sh — deploy Neovim Lua config from configs/nvim
#
# Requires: DIR, DRY_RUN, OLD_DOTS, ensure_dir, backup_stamp

dots_deploy_nvim() {
  echo "=== Neovim ==="
  local src="${DIR}/configs/nvim"
  local dest="${HOME}/.config/nvim"

  if [[ ! -f "${src}/init.lua" ]]; then
    echo "Skip: missing ${src}/init.lua"
    return 0
  fi

  ensure_dir "${HOME}/.config"
  ensure_dir "${OLD_DOTS}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] deploy Neovim config ${src} → ${dest}"
    echo "[dry-run] backup legacy init.vim if present"
    return 0
  fi

  # Backup existing nvim config if it is not already our tree
  if [[ -e "${dest}" ]] && [[ ! -L "${dest}" ]]; then
    if [[ -f "${dest}/init.lua" ]] && cmp -s "${src}/init.lua" "${dest}/init.lua" 2>/dev/null; then
      # Likely already synced — still refresh tree via rsync-like copy of managed files
      :
    else
      local backup="${OLD_DOTS}/nvim_$(backup_stamp)"
      echo "Backup ${dest} → ${backup}"
      mv "${dest}" "${backup}"
    fi
  elif [[ -L "${dest}" ]]; then
    local backup="${OLD_DOTS}/nvim_symlink_$(backup_stamp)"
    echo "Backup symlink ${dest} → ${backup}"
    mv "${dest}" "${backup}"
  fi

  mkdir -p "${dest}/lua/config" "${dest}/lua/plugins"
  # Copy managed files (authoritative DOTS config)
  cp "${src}/init.lua" "${dest}/init.lua"
  cp -R "${src}/lua/config/." "${dest}/lua/config/"
  cp -R "${src}/lua/plugins/." "${dest}/lua/plugins/"

  # Remove legacy init.vim in live config so Neovim prefers init.lua
  if [[ -f "${dest}/init.vim" ]]; then
    mv "${dest}/init.vim" "${OLD_DOTS}/nvim_init.vim_$(backup_stamp)"
    echo "Moved legacy init.vim aside (Neovim is managed editor)"
  fi

  echo "OK: Neovim config deployed → ${dest}"

  # Headless plugin sync (best-effort; network may be needed first time)
  if command -v nvim >/dev/null 2>&1; then
    nvim --headless "+Lazy! sync" "+qa" >/dev/null 2>&1 || \
      echo "Note: Lazy sync deferred (run nvim once to install plugins)"
  fi
}
