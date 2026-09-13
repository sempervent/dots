#!/usr/bin/env bash
# setup.sh — idempotent installer for sempervent/dots
#
# Usage:
#   ./setup.sh
#   ./setup.sh --with herdr,hermes,ollama
#   ./setup.sh --with=herdr
#   ./setup.sh --dry-run
#   ./setup.sh --help
#
# Default setup does NOT install AI tooling (herdr / hermes / ollama).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SYM_DIR="${DIR}/syms"
OLD_DOTS="${HOME}/.old_dots"
VUNDLE_DIR="${HOME}/.vim/bundle/Vundle.vim"
TMUX_PLUGIN_DIR="${HOME}/.tmux/plugins/tpm"
ZSH="${ZSH:-${HOME}/.oh-my-zsh}"
ZSH_CUSTOM="${ZSH_CUSTOM:-${ZSH}/custom}"
DRY_RUN=0
DOTS_WITH_COMPONENTS=()

SUPPORTED_WITH=(herdr hermes ollama)

usage() {
  cat <<'EOF'
Usage: ./setup.sh [options]

Install / refresh dotfiles (idempotent). Safe to re-run.

Options:
  --with <list>     Comma-separated optional components to install via Brewfile
                    fragments. Supported: herdr, hermes, ollama
  --with=<list>     Same as --with <list>
  --dry-run         Preview actions without modifying the machine
  -h, --help        Show this help

Examples:
  ./setup.sh
  ./setup.sh --with herdr
  ./setup.sh --with herdr,hermes
  ./setup.sh --with herdr,hermes,ollama
  ./setup.sh --with=ollama
  ./setup.sh --dry-run --with herdr

Default ./setup.sh does NOT install AI tools or download models.

Environment (runtime shells, not installer):
  DOTS_MULTIPLEXER=tmux|herdr|none   (default: tmux)
  DOTS_AUTO_TMUX=0                   disable auto tmux (compat)
  DOTS_PROMPT_STATS=1                enable prompt dir stats
  DOTS_GREETING=0                    silence fortune greeting
EOF
}

parse_with_list() {
  local raw="$1" item
  IFS=',' read -r -a _parts <<<"${raw}"
  for item in "${_parts[@]}"; do
    item="$(echo "${item}" | tr -d '[:space:]')"
    [[ -z "${item}" ]] && continue
    local ok=0 s
    for s in "${SUPPORTED_WITH[@]}"; do
      if [[ "${item}" == "${s}" ]]; then
        ok=1
        break
      fi
    done
    if [[ "${ok}" -ne 1 ]]; then
      echo "Error: unknown --with component '${item}'" >&2
      echo "Supported: ${SUPPORTED_WITH[*]}" >&2
      exit 1
    fi
    DOTS_WITH_COMPONENTS+=("${item}")
  done
}

# Deduplicate while preserving order
uniq_components() {
  local seen="|" c out=()
  for c in "${DOTS_WITH_COMPONENTS[@]}"; do
    case "${seen}" in
      *"|${c}|"*) ;;
      *)
        out+=("${c}")
        seen="${seen}${c}|"
        ;;
    esac
  done
  DOTS_WITH_COMPONENTS=("${out[@]}")
}

has_component() {
  local want="$1" c
  for c in "${DOTS_WITH_COMPONENTS[@]+"${DOTS_WITH_COMPONENTS[@]}"}"; do
    [[ "${c}" == "${want}" ]] && return 0
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --with=*)
      parse_with_list "${1#--with=}"
      shift
      ;;
    --with)
      [[ $# -ge 2 ]] || { echo "Error: --with requires an argument" >&2; exit 1; }
      parse_with_list "$2"
      shift 2
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

uniq_components

backup_stamp() { date +%Y-%m-%d_%H%M%S; }
ensure_dir() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] mkdir -p $1"
  else
    mkdir -p "$1"
  fi
}

run_cmd() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

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

  if [[ -L "${dest}" ]] && [[ "$(readlink "${dest}")" == "${source}" ]]; then
    echo "OK: ${dest}"
    return 0
  fi

  if [[ -e "${dest}" ]] || [[ -L "${dest}" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] backup ${dest} → ${backup}"
    else
      echo "Backup ${dest} → ${backup}"
      mv "${dest}" "${backup}"
    fi
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] link ${source} → ${dest}"
  else
    echo "Linked: ${source} → ${dest}"
    ln -s "${source}" "${dest}"
  fi
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
  run_cmd git clone --depth 1 "${url}" "${dest}"
}

echo "=== dots setup ==="
[[ "${DRY_RUN}" -eq 1 ]] && echo "(dry-run mode — no mutations)"
if [[ ${#DOTS_WITH_COMPONENTS[@]} -gt 0 ]]; then
  echo "Optional components: ${DOTS_WITH_COMPONENTS[*]}"
else
  echo "Optional components: (none — AI tooling not installed by default)"
fi

echo "=== Symlinks ==="
for f in bashrc zshrc zprofile vimrc tmux.conf sqliterc psqlrc; do
  move_sym "${f}" "${HOME}/.${f}"
done

# App configs under XDG (file-level, not whole directory)
if [[ -f "${DIR}/configs/bat.conf" ]]; then
  move_sym "bat_config" "${HOME}/.config/bat/config" "${DIR}/configs/bat.conf"
fi
if [[ -f "${DIR}/configs/btop/btop.conf" ]]; then
  move_sym "btop.conf" "${HOME}/.config/btop/btop.conf" "${DIR}/configs/btop/btop.conf"
fi
if [[ -f "${DIR}/configs/btop/themes/catppuccin_mocha.theme" ]]; then
  ensure_dir "${HOME}/.config/btop/themes"
  move_sym "btop_catppuccin_mocha.theme" \
    "${HOME}/.config/btop/themes/catppuccin_mocha.theme" \
    "${DIR}/configs/btop/themes/catppuccin_mocha.theme"
fi
if [[ -f "${DIR}/configs/herdr/config.toml" ]]; then
  # Prefer symlink; Herdr reads ~/.config/herdr/config.toml
  move_sym "herdr_config.toml" "${HOME}/.config/herdr/config.toml" "${DIR}/configs/herdr/config.toml"
fi

# Ranger — file-level deploy only
echo "=== Ranger ==="
RANGER_DST="${HOME}/.config/ranger"
ensure_dir "${RANGER_DST}"
ensure_dir "${RANGER_DST}/colorschemes"
for rf in rc.conf rifle.conf scope.sh commands.py; do
  if [[ -f "${DIR}/ranger/${rf}" ]]; then
    move_sym "ranger_${rf}" "${RANGER_DST}/${rf}" "${DIR}/ranger/${rf}"
  fi
done
if [[ -f "${DIR}/ranger/colorschemes/catppuccin.py" ]]; then
  move_sym "ranger_catppuccin.py" "${RANGER_DST}/colorschemes/catppuccin.py" \
    "${DIR}/ranger/colorschemes/catppuccin.py"
fi
if [[ "${DRY_RUN}" -eq 0 ]] && [[ -f "${RANGER_DST}/scope.sh" ]]; then
  chmod +x "${RANGER_DST}/scope.sh" || true
fi

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
  run_cmd git clone https://github.com/VundleVim/Vundle.vim.git "${VUNDLE_DIR}"
  if [[ "${DRY_RUN}" -eq 0 ]] && command -v vim >/dev/null 2>&1; then
    vim +PluginInstall +qall || true
  fi
else
  echo "OK: Vundle"
fi

echo "=== tmux TPM ==="
clone_if_missing "https://github.com/tmux-plugins/tpm" "${TMUX_PLUGIN_DIR}" "tpm"
if [[ "${DRY_RUN}" -eq 0 ]] && [[ -x "${TMUX_PLUGIN_DIR}/bin/install_plugins" ]]; then
  "${TMUX_PLUGIN_DIR}/bin/install_plugins" || echo "Warn: TPM plugin install reported errors"
elif [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "[dry-run] TPM install_plugins"
fi

echo "=== Homebrew (Brewfile) ==="
if command -v brew >/dev/null 2>&1; then
  brew_failed=0
  apply_brewfile() {
    local file="$1"
    if [[ ! -f "${file}" ]]; then
      echo "Warn: missing ${file}"
      return 0
    fi
    echo "brew bundle --file=${file}"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] would apply:"
      brew bundle list --file="${file}" 2>/dev/null || cat "${file}"
      return 0
    fi
    if ! brew bundle --file="${file}"; then
      brew_failed=1
      echo "Warn: brew bundle failed for ${file}"
    fi
  }

  apply_brewfile "${DIR}/brew/Brewfile"

  if has_component herdr; then
    apply_brewfile "${DIR}/brew/Brewfile.herdr"
  fi
  if has_component hermes; then
    apply_brewfile "${DIR}/brew/Brewfile.hermes"
    if [[ "$(uname -s)" == "Darwin" ]]; then
      echo "Installing hermes-desktop cask (macOS)..."
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "[dry-run] brew install --cask hermes-desktop"
      else
        brew install --cask hermes-desktop || {
          brew_failed=1
          echo "Warn: hermes-desktop cask install failed"
        }
      fi
    else
      echo "Note: hermes-desktop cask skipped (macOS only)"
    fi
  fi
  if has_component ollama; then
    apply_brewfile "${DIR}/brew/Brewfile.ollama"
  fi

  if [[ "${brew_failed}" -ne 0 ]]; then
    echo "Homebrew finished with warnings — review output before relying on new tools."
  fi
else
  echo "Note: brew not found; skipped package install"
fi

# Hermes PATH ambiguity warning (never delete old install)
if has_component hermes || command -v hermes >/dev/null 2>&1; then
  echo "=== Hermes PATH check ==="
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    type -a hermes 2>/dev/null || true
    _hermes_win="$(command -v hermes 2>/dev/null || true)"
    if [[ "${_hermes_win}" == "${HOME}/.local/bin/hermes" ]]; then
      echo "Warn: ~/.local/bin/hermes currently wins PATH (likely git install)."
      echo "      After verifying Homebrew hermes-agent, remove/rename the old shim manually."
      echo "      Prefer Homebrew PATH (brew shellenv) ahead of ~/.local/bin if desired."
    fi
    unset _hermes_win
  else
    echo "[dry-run] would run: type -a hermes"
  fi
fi

# Herdr integrations (only when herdr present / selected)
if has_component herdr || command -v herdr >/dev/null 2>&1; then
  echo "=== Herdr integrations ==="
  ensure_herdr_integration() {
    local name="$1" need_cli="$2"
    if ! command -v herdr >/dev/null 2>&1; then
      return 0
    fi
    if [[ -n "${need_cli}" ]] && ! command -v "${need_cli}" >/dev/null 2>&1; then
      echo "Skip integration ${name}: ${need_cli} not installed"
      return 0
    fi
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] herdr integration install ${name} (if needed)"
      return 0
    fi
    # install is idempotent enough; status may already say current
    herdr integration install "${name}" 2>&1 || echo "Warn: herdr integration ${name} failed"
  }
  # Only install integrations for agents that exist
  ensure_herdr_integration hermes hermes
  ensure_herdr_integration codex codex
  # OpenCode CLI binary name varies; try common names
  if command -v opencode >/dev/null 2>&1 || command -v open-code >/dev/null 2>&1; then
    ensure_herdr_integration opencode opencode
  else
    # Still try if integration status previously existed — only when herdr selected
    if has_component herdr; then
      echo "Note: OpenCode CLI not found; skip opencode integration unless already present"
      if [[ "${DRY_RUN}" -eq 0 ]]; then
        herdr integration status 2>/dev/null | rg -i '^opencode:' || true
      fi
    fi
  fi
fi

# bat theme cache (Catppuccin) if theme files present
if command -v bat >/dev/null 2>&1 && [[ -d "${DIR}/configs/bat/themes" ]]; then
  echo "=== bat theme cache ==="
  ensure_dir "${HOME}/.config/bat/themes"
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    # Link theme files if needed
    for t in "${DIR}/configs/bat/themes"/*.tmTheme; do
      [[ -f "${t}" ]] || continue
      bn="$(basename "${t}")"
      dest="${HOME}/.config/bat/themes/${bn}"
      if [[ ! -e "${dest}" ]]; then
        ln -s "${t}" "${dest}"
      fi
    done
    bat cache --build >/dev/null 2>&1 || echo "Warn: bat cache --build failed"
  else
    echo "[dry-run] bat cache --build"
  fi
fi

ensure_dir "${SECRETS_DIR:-${DIR}/.secrets}"
if [[ -f "${DIR}/helpers/git_alias_setup.sh" ]] && [[ "${DRY_RUN}" -eq 0 ]]; then
  # shellcheck disable=SC1091
  source "${DIR}/helpers/git_alias_setup.sh" || true
fi

# Conservative Atuin local config if atuin exists and config missing
if command -v atuin >/dev/null 2>&1; then
  ensure_dir "${HOME}/.config/atuin"
  if [[ ! -f "${HOME}/.config/atuin/config.toml" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] create local-only Atuin config"
    else
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
fi

cat <<EOF

Finished installing dots$([ "${DRY_RUN}" -eq 1 ] && echo ' (dry-run)').

Core: ~/.bashrc ~/.zshrc ~/.zprofile ~/.vimrc ~/.tmux.conf
Ranger: ~/.config/ranger/{rc.conf,rifle.conf,scope.sh,colorschemes/catppuccin.py}
Herdr config: ~/.config/herdr/config.toml (when present in repo)

Optional --with: ${DOTS_WITH_COMPONENTS[*]:-none}

Multiplexer (shell runtime):
  DOTS_MULTIPLEXER=tmux|herdr|none   (default tmux)
  DOTS_AUTO_TMUX=0                   still disables auto-tmux

Prefixes: tmux=Ctrl-Space  herdr=Ctrl-A (sidebar remains Ctrl-A b)

See README.md for details.
EOF
