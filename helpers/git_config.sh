# shellcheck shell=bash
# helpers/git_config.sh — deploy shared Git config without forcing identity
#
# Requires: DIR, DRY_RUN, ensure_dir

dots_setup_git_config() {
  echo "=== Git config (common + identity templates) ==="
  local gitdir="${HOME}/.config/git"
  ensure_dir "${gitdir}"

  # common is linked via links.toml; ensure present even if links skipped
  if [[ ! -e "${gitdir}/common" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] link ${gitdir}/common"
    else
      ln -sfn "${DIR}/configs/git/common" "${gitdir}/common"
      echo "OK: ${gitdir}/common"
    fi
  fi

  # Seed personal/work identity files once (never overwrite)
  if [[ ! -f "${gitdir}/personal" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] create ${gitdir}/personal from template"
    else
      cp "${DIR}/configs/git/personal.template" "${gitdir}/personal"
      echo "OK: created ${gitdir}/personal — edit name/email"
    fi
  else
    echo "OK: ${gitdir}/personal (preserved)"
  fi

  if [[ ! -f "${gitdir}/work" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] create ${gitdir}/work from template"
    else
      cp "${DIR}/configs/git/work.template" "${gitdir}/work"
      echo "OK: created ${gitdir}/work — edit name/email"
    fi
  else
    echo "OK: ${gitdir}/work (preserved)"
  fi

  # XDG git config — create once with includes; never overwrite
  local xdgcfg="${gitdir}/config"
  if [[ ! -f "${xdgcfg}" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] create ${xdgcfg}"
    else
      cat >"${xdgcfg}" <<'EOF'
# Managed once by DOTS — edit includeIf paths to match your directories.
# Identity lives in personal / work files; common has shared ergonomics.

[include]
	path = ~/.config/git/common

[includeIf "gitdir:~/dev/"]
	path = ~/.config/git/personal

[includeIf "gitdir:~/work/"]
	path = ~/.config/git/work
EOF
      echo "OK: created ${xdgcfg}"
    fi
  else
    echo "OK: ${xdgcfg} (preserved)"
  fi

  # If legacy ~/.gitconfig exists with identity, leave it alone (warn only)
  if [[ -f "${HOME}/.gitconfig" ]]; then
    echo "Note: ~/.gitconfig present — DOTS will not overwrite it."
    echo "      Prefer migrating includes to ~/.config/git/config when ready."
  fi
}
