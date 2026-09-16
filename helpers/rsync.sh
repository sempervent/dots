# helpers/rsync.sh — ensure rsync on macOS (Homebrew) and Linux (native pkg)
#
# macOS ships openrsync at /usr/bin/rsync (old protocol). Prefer Homebrew
# rsync (Samba) via Brewfile when brew is available.
# On Linux without brew, install the distro `rsync` package.

_dots_rsync_is_homebrew() {
  local bin
  bin="$(command -v rsync 2>/dev/null || true)"
  [[ -n "${bin}" ]] || return 1
  case "${bin}" in
    /opt/homebrew/*|/usr/local/Cellar/*|/usr/local/opt/*|/home/linuxbrew/*)
      return 0
      ;;
  esac
  # Resolve symlinks into Cellar
  if command -v realpath >/dev/null 2>&1; then
    bin="$(realpath "${bin}" 2>/dev/null || printf '%s' "${bin}")"
  elif command -v readlink >/dev/null 2>&1; then
    bin="$(readlink -f "${bin}" 2>/dev/null || printf '%s' "${bin}")"
  fi
  case "${bin}" in
    */Cellar/rsync/*|*/opt/rsync/*) return 0 ;;
  esac
  return 1
}

_dots_rsync_linux_install() {
  local pkg=rsync
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] install ${pkg} via native package manager"
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y "${pkg}"
  elif command -v apt >/dev/null 2>&1; then
    sudo apt update -qq && sudo apt install -y "${pkg}"
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y "${pkg}"
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y "${pkg}"
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm --needed "${pkg}"
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y "${pkg}"
  elif command -v apk >/dev/null 2>&1; then
    sudo apk add "${pkg}"
  else
    echo "Warn: no supported Linux package manager found for rsync" >&2
    return 1
  fi
}

dots_ensure_rsync() {
  echo "=== rsync ==="

  if command -v brew >/dev/null 2>&1; then
    if brew list --formula rsync >/dev/null 2>&1; then
      echo "OK: Homebrew rsync ($(command -v rsync))"
      rsync --version 2>/dev/null | head -1 || true
      return 0
    fi
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] brew install rsync"
      return 0
    fi
    echo "Installing rsync via Homebrew…"
    if brew install rsync; then
      echo "OK: Homebrew rsync ($(command -v rsync))"
      rsync --version 2>/dev/null | head -1 || true
      return 0
    fi
    echo "Warn: brew install rsync failed" >&2
  fi

  if command -v rsync >/dev/null 2>&1; then
    echo "OK: rsync present ($(command -v rsync))"
    rsync --version 2>/dev/null | head -1 || true
    if [[ "$(uname -s)" == "Darwin" ]] && ! _dots_rsync_is_homebrew; then
      echo "Note: using system openrsync; prefer Homebrew rsync (brew install rsync)"
    fi
    return 0
  fi

  # Linux without brew (or brew failed) and no rsync binary
  if [[ "$(uname -s)" == "Linux" ]]; then
    echo "Installing rsync via system package manager…"
    if _dots_rsync_linux_install; then
      if command -v rsync >/dev/null 2>&1; then
        echo "OK: rsync ($(command -v rsync))"
        rsync --version 2>/dev/null | head -1 || true
        return 0
      fi
    fi
    echo "Error: rsync install failed" >&2
    return 1
  fi

  echo "Warn: rsync not found and no installer available for this platform" >&2
  return 1
}
