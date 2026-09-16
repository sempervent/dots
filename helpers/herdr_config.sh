# helpers/herdr_config.sh — merge managed Herdr config from the dots repo.
#
# Herdr rewrites ~/.config/herdr/config.toml (onboarding, [ui], …). A symlink
# would either pollute the repo or get replaced by a regular file and leave
# stale keys. We merge [theme]/[keys] from configs/herdr/config.toml and
# upsert managed [ui] keys (tab_bar_right*) while preserving everything else.
#
# Requires (from setup.sh): DIR, OLD_DOTS, DRY_RUN, ensure_dir, backup_stamp

sync_herdr_config() {
  local src="${DIR}/configs/herdr/config.toml"
  local dest="${HOME}/.config/herdr/config.toml"
  local name="herdr_config.toml"
  local backup tmp merged

  if [[ ! -f "${src}" ]]; then
    echo "Skip: missing ${src}"
    return 0
  fi

  ensure_dir "$(dirname "${dest}")"
  ensure_dir "${OLD_DOTS}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] merge Herdr [theme]/[keys] + ui.tab_bar_right* from ${src} → ${dest}"
    return 0
  fi

  tmp="$(mktemp)"
  merged="$(mktemp)"

  if [[ -L "${dest}" ]]; then
    if [[ -f "${dest}" ]]; then
      cp "${dest}" "${tmp}"
    else
      : >"${tmp}"
    fi
    backup="${OLD_DOTS}/${name}_symlink_$(backup_stamp)"
    echo "Backup symlink ${dest} → ${backup}"
    mv "${dest}" "${backup}"
  elif [[ -f "${dest}" ]]; then
    cp "${dest}" "${tmp}"
  else
    : >"${tmp}"
  fi

  if ! dots_python3 - "${tmp}" "${src}" "${merged}" <<'PY'
import re
import sys
from pathlib import Path

dest_path, src_path, out_path = sys.argv[1:4]

def section_root(line: str):
    m = re.match(r"^\[\[?([^\]\.\s]+)", line.strip())
    return m.group(1) if m else None

def strip_managed(text: str) -> str:
    out = []
    skipping = False
    for line in text.splitlines(keepends=True):
        if line.lstrip().startswith("["):
            root = section_root(line)
            skipping = root in {"theme", "keys"}
        if not skipping:
            out.append(line)
    body = "".join(out)
    body = re.sub(r"\n{3,}", "\n\n", body)
    return body.rstrip() + ("\n" if body.strip() else "")

def managed_from_repo(text: str) -> str:
    out = []
    keeping = False
    for line in text.splitlines(keepends=True):
        if line.lstrip().startswith("["):
            root = section_root(line)
            keeping = root in {"theme", "keys"}
        if keeping:
            out.append(line)
    return "".join(out).strip() + "\n"

local_body = strip_managed(Path(dest_path).read_text(encoding="utf-8"))
managed = managed_from_repo(Path(src_path).read_text(encoding="utf-8"))
if not managed.strip():
    raise SystemExit("repo Herdr config missing [theme]/[keys]")

parts = []
if local_body.strip():
    parts.append(local_body.rstrip())
parts.append(managed.rstrip())
Path(out_path).write_text("\n\n".join(parts) + "\n", encoding="utf-8")
PY
  then
    echo "Error: failed to merge Herdr config" >&2
    rm -f "${tmp}" "${merged}"
    return 1
  fi

  rm -f "${tmp}"

  # Upsert restrained status area without wiping other [ui] keys
  if command -v yq >/dev/null 2>&1; then
    local tab_json sep
    tab_json="$(yq -p=toml -o=json '.ui.tab_bar_right' "${src}" 2>/dev/null || true)"
    sep="$(yq -p=toml -o=json '.ui.tab_bar_right_separator' "${src}" 2>/dev/null || true)"
    if [[ -n "${tab_json}" ]] && [[ "${tab_json}" != "null" ]]; then
      yq -p=toml -o=toml -i ".ui.tab_bar_right = ${tab_json}" "${merged}" 2>/dev/null || \
        echo "Warn: could not upsert herdr ui.tab_bar_right"
    fi
    if [[ -n "${sep}" ]] && [[ "${sep}" != "null" ]]; then
      yq -p=toml -o=toml -i ".ui.tab_bar_right_separator = ${sep}" "${merged}" 2>/dev/null || true
    fi
  else
    echo "Warn: yq missing — Herdr tab_bar_right not upserted"
  fi

  if [[ -f "${dest}" ]] && cmp -s "${merged}" "${dest}"; then
    echo "OK: ${dest} (Herdr managed sections current)"
    rm -f "${merged}"
    return 0
  fi

  if [[ -f "${dest}" ]]; then
    backup="${OLD_DOTS}/${name}_$(backup_stamp)"
    echo "Backup ${dest} → ${backup}"
    cp "${dest}" "${backup}"
  fi

  mv "${merged}" "${dest}"
  echo "Synced Herdr managed config → ${dest}"
}
