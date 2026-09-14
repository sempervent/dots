#!/usr/bin/env bash
# notify-smoke.sh — opt-in macOS notification smoke test (NOT part of check.sh)
set -euo pipefail

if ! command -v notify >/dev/null 2>&1 && ! command -v terminal-notifier >/dev/null 2>&1; then
  echo "Error: notify/terminal-notifier missing" >&2
  exit 1
fi

if command -v notify >/dev/null 2>&1; then
  notify --title "DOTS notify smoke" --message "terminal-notifier wrapper OK" --group "dots-notify-smoke"
else
  terminal-notifier -title "DOTS notify smoke" -message "terminal-notifier OK" -group "dots-notify-smoke"
fi
echo "OK: notification sent (check Notification Center)"
