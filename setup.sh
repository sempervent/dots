#!/usr/bin/env bash
# setup.sh — idempotent installer for sempervent/dots
# Safe to re-run. Backs up with second-resolution timestamps.
# Does not reclone Oh My Zsh / TPM / Vundle / third-party plugins if present.
# Does not change the login shell. Does not uninstall Homebrew packages.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SYM_DIR="${DIR}/syms"
OLD_DOTS="${HOME}/.old_dots"
VUNDLE_DIR="${HOME}/.vim/bundle/Vundle.vim"
TMUX_PLUGIN_DIR="${HOME}/.tmux/plugins/tpm"
ZSH="${ZSH:-${HOME}/.oh-my-zsh}"
ZSH_CUSTOM="${ZSH_CUSTOM:-${ZSH}/custom}"

backup_stamp() { date +%Y-%m-%d_%H%M%S; }
ensure_dir() { mkdir -p "$1"; }

move_sym() {
  local name="$1"
  local dest="$2"
  local source="${3:-${SYM_DIR}/${name}}"
  local backup

  if [[ ! -e "${source}" ]]; then
    echo "Skip: missing source ${source}"
    return 0
  fi

  ensure_dir "$(dirname "${dest}")"
  ensure_dir "${OLD_DOTS}"
  backup="${OLD_DOTS}/${name}_$(backup_stamp)"

  if [[ -L "${dest}" ]]; then
    if [[ "$(readlink "${dest}")" == "${source}" ]]; then
      echo "OK: ${dest}"
      return 0
    fi
  fi

  if [[ -e "${dest}" ]] || [[ -L "${dest}" ]]; then
    echo "Backup ${dest} → ${backup}"
    mv "${dest}" "${backup}"
  fi

  ln -s "${source}" "${dest}"
  echo "Linked: ${source} → ${dest}"
}

clone_if_missing() {
  local url="$1" dest="$2" label="${3:-$(basename "$2")}"
  if [[ -d "${dest}/.git" ]] || [[ -e "${dest}/oh-my-zsh.sh" ]] || [[ -e "${dest}/tpm" ]]; then
    echo "OK: ${label}"
    return 0
  fi
  if [[ -d "${dest}" ]] && [[ -n "$(ls -A "${dest}" 2>/dev/null || true)" ]]; then
    echo "OK: ${label} (present)"
    return 0
  fi
  echo "Cloning ${label}..."
  git clone --depth 1 "${url}" "${dest}"
}

echo "=== Symlinks ==="
# Core shell modernization targets + previously supported tracked configs
for f in bashrc zshrc zprofile vimrc tmux.conf sqliterc psqlrc; do
  move_sym "${f}" "${HOME}/.${f}"
done

echo "=== Oh My Zsh ==="
if [[ ! -f "${ZSH}/oh-my-zsh.sh" ]]; then
  clone_if_missing "https://github.com/ohmyzsh/ohmyzsh.git" "${ZSH}" "oh-my-zsh"
else
  echo "OK: oh-my-zsh"
fi
ensure_dir "${ZSH_CUSTOM}/plugins"

install_zsh_plugin() {
  local repo="$1" name="$2"
  clone_if_missing "https://github.com/${repo}.git" "${ZSH_CUSTOM}/plugins/${name}" "${name}"
}
install_zsh_plugin "zsh-users/zsh-autosuggestions" "zsh-autosuggestions"
install_zsh_plugin "zsh-users/zsh-syntax-highlighting" "zsh-syntax-highlighting"
install_zsh_plugin "zsh-users/zsh-history-substring-search" "zsh-history-substring-search"

echo "=== Vundle ==="
if [[ ! -d "${VUNDLE_DIR}" ]]; then
  git clone https://github.com/VundleVim/Vundle.vim.git "${VUNDLE_DIR}"
  command -v vim >/dev/null 2>&1 && vim +PluginInstall +qall || true
else
  echo "OK: Vundle"
fi

echo "=== tmux TPM ==="
clone_if_missing "https://github.com/tmux-plugins/tpm" "${TMUX_PLUGIN_DIR}" "tpm"
if [[ -x "${TMUX_PLUGIN_DIR}/bin/install_plugins" ]]; then
  "${TMUX_PLUGIN_DIR}/bin/install_plugins" || echo "Warn: TPM plugin install reported errors"
fi

echo "=== Homebrew ==="
if command -v brew >/dev/null 2>&1; then
  brew_failed=0
  if [[ -f "${DIR}/brew/Brewfile" ]]; then
    echo "Running brew bundle (Brewfile)..."
    if ! brew bundle --file="${DIR}/brew/Brewfile"; then
      brew_failed=1
      echo "Warn: brew bundle reported failures (see above)."
      echo "Note: stale keg metadata (e.g. libtiff/webp) is a manual Homebrew repair —"
      echo "      setup.sh will not uninstall or reinstall unrelated packages."
    fi
  elif [[ -f "${DIR}/brew/packages.txt" ]]; then
    while read -r pkg; do
      pkg="${pkg%%#*}"
      pkg="$(echo "${pkg}" | tr -d '[:space:]')"
      [[ -z "${pkg}" ]] && continue
      if brew list --formula "${pkg}" >/dev/null 2>&1; then
        echo "OK: ${pkg}"
      else
        echo "Installing ${pkg}..."
        if ! brew install "${pkg}"; then
          brew_failed=1
          echo "Warn: failed to install ${pkg}"
        fi
      fi
    done <"${DIR}/brew/packages.txt"
  fi
  if [[ "${brew_failed}" -ne 0 ]]; then
    echo "Homebrew finished with warnings — review output before relying on new tools."
  fi
else
  echo "Note: brew not found; skipped package install"
fi

# Secrets dir + optional git aliases
ensure_dir "${SECRETS_DIR:-${DIR}/.secrets}"
if [[ -f "${DIR}/helpers/git_alias_setup.sh" ]]; then
  # shellcheck disable=SC1091
  source "${DIR}/helpers/git_alias_setup.sh" || true
fi

# Conservative Atuin local config if atuin exists and config missing
if command -v atuin >/dev/null 2>&1; then
  ensure_dir "${HOME}/.config/atuin"
  if [[ ! -f "${HOME}/.config/atuin/config.toml" ]]; then
    cat >"${HOME}/.config/atuin/config.toml" <<'EOF'
## dots setup — local-first (no cloud sync required)
auto_sync = false
update_check = false
style = "compact"
search_mode = "fuzzy"
filter_mode = "global"
inline_height = 20
EOF
    echo "Created local-only Atuin config"
  fi
fi

cat <<EOF

Finished installing dots.

Linked when present: ~/.bashrc ~/.zshrc ~/.zprofile ~/.vimrc ~/.tmux.conf
Oh My Zsh: ${ZSH}
Plugins:   ${ZSH_CUSTOM}/plugins/{zsh-autosuggestions,zsh-syntax-highlighting,zsh-history-substring-search}

Toggles:
  DOTS_AUTO_TMUX=0      disable auto tmux
  DOTS_PROMPT_STATS=1   enable dir file count/size in prompt
  DOTS_GREETING=0       silence fortune greeting

Switch default shell (manual):
  chsh -s "\$(command -v zsh)"   # or bash

See README.md for architecture and troubleshooting.
EOF
