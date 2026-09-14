# helpers/notify.sh — deploy notify helper + Hermes completion hooks
#
# Requires: DIR, DRY_RUN, ensure_dir, run_cmd

dots_deploy_notify() {
  echo "=== Notifications ==="
  local src="${DIR}/scripts/notify"
  local dest="${HOME}/.local/bin/notify"
  local hook_src="${DIR}/scripts/hermes-notify-hook"
  local hook_dest="${HOME}/.local/bin/hermes-notify-hook"
  local cfg_src="${DIR}/configs/notify/config.toml"
  local cfg_dest="${HOME}/.config/dots/notify.toml"

  ensure_dir "${HOME}/.local/bin"
  ensure_dir "${HOME}/.config/dots"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] link ${src} → ${dest}"
    echo "[dry-run] link ${hook_src} → ${hook_dest}"
    echo "[dry-run] deploy notify config → ${cfg_dest} (if missing)"
    echo "[dry-run] ensure Hermes on_session_start/end hooks when ~/.hermes/config.yaml exists"
    return 0
  fi

  if [[ -f "${src}" ]]; then
    ln -sfn "${src}" "${dest}"
    chmod +x "${src}"
    echo "OK: ${dest}"
  fi
  if [[ -f "${hook_src}" ]]; then
    ln -sfn "${hook_src}" "${hook_dest}"
    chmod +x "${hook_src}"
    echo "OK: ${hook_dest}"
  fi

  if [[ -f "${cfg_src}" ]] && [[ ! -f "${cfg_dest}" ]]; then
    cp "${cfg_src}" "${cfg_dest}"
    echo "OK: deployed ${cfg_dest}"
  elif [[ -f "${cfg_dest}" ]]; then
    echo "OK: ${cfg_dest} (preserved)"
  fi

  dots_ensure_hermes_notify_hooks
}

dots_ensure_hermes_notify_hooks() {
  local cfg="${HOME}/.hermes/config.yaml"
  local hook="${HOME}/.local/bin/hermes-notify-hook"
  [[ -f "${cfg}" ]] || {
    echo "Note: ~/.hermes/config.yaml absent — Hermes notify hooks deferred"
    return 0
  }
  [[ -x "${hook}" ]] || [[ -L "${hook}" ]] || return 0

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] merge Hermes shell hooks for notify"
    return 0
  fi

  python3 - "${cfg}" "${hook}" <<'PY'
import sys
from pathlib import Path

cfg_path = Path(sys.argv[1])
hook = sys.argv[2]
text = cfg_path.read_text(encoding="utf-8")

# Idempotent: skip when our hook command already referenced
marker = "hermes-notify-hook"
if marker in text:
    print(f"OK: Hermes notify hooks already present in {cfg_path}")
    raise SystemExit(0)

block = f"""
# DOTS: macOS notifications for long Hermes sessions (via terminal-notifier)
# Consent: first use may prompt unless hooks_auto_accept / HERMES_ACCEPT_HOOKS
hooks:
  on_session_start:
    - command: "{hook} start"
      timeout: 5
  on_session_end:
    - command: "{hook} end"
      timeout: 10
"""

# If hooks: already exists, append entries carefully; else append block
if "\nhooks:" in text or text.startswith("hooks:"):
    # Append under existing hooks by adding our events if missing
    lines = text.splitlines(keepends=True)
    out = []
    i = 0
    inserted = False
    while i < len(lines):
        out.append(lines[i])
        if lines[i].startswith("hooks:") and not inserted:
            out.append(f"  on_session_start:\n")
            out.append(f"    - command: \"{hook} start\"\n")
            out.append(f"      timeout: 5\n")
            out.append(f"  on_session_end:\n")
            out.append(f"    - command: \"{hook} end\"\n")
            out.append(f"      timeout: 10\n")
            inserted = True
        i += 1
    if not inserted:
        out.append(block)
    cfg_path.write_text("".join(out), encoding="utf-8")
else:
    cfg_path.write_text(text.rstrip() + "\n" + block + "\n", encoding="utf-8")

print(f"OK: Hermes notify hooks added → {cfg_path}")
print("Note: Hermes may prompt once to accept shell hooks (or set hooks_auto_accept).")
PY
}
