#!/usr/bin/env bash
# scripts/tests/network_hardware_validate_test.sh — Phase 6 (non-mutating)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-net-hw.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

NET="${ROOT}/scripts/ci/network_validate.sh"
HW="${ROOT}/scripts/ci/hardware_validate.sh"
[[ -x ${NET} ]] || chmod +x "${NET}"
[[ -x ${HW} ]] || chmod +x "${HW}"

# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/packages.sh"

echo "=== network package ownership ==="
for p in mtr nmap iperf3 gping bandwhich mosh rclone tailscale; do
	found=0
	while IFS= read -r id; do [[ ${id} == "${p}" ]] && found=1; done < <(dots_group_package_ids network optional)
	[[ ${found} -eq 1 ]] && ok "network owns ${p}" || bad "network missing ${p}"
done
grep -q 'brew "mtr"' "${ROOT}/brew/groups/network.Brewfile" && ok "mtr Brewfile" || bad "mtr Brewfile"
grep -q 'brew "nmap"' "${ROOT}/brew/groups/network.Brewfile" && ok "nmap Brewfile" || bad "nmap Brewfile"
grep -q 'brew "iperf3"' "${ROOT}/brew/groups/network.Brewfile" && ok "iperf3 Brewfile" || bad "iperf3 Brewfile"
# termshark not on Darwin brew (disabled)
grep -q 'brew "termshark"' "${ROOT}/brew/groups/network.Brewfile" && bad "termshark must not be in Darwin Brewfile (disabled)" || ok "termshark omitted from Darwin Brewfile"
# rclone not in backup
rclone_backup=0
while IFS= read -r id; do [[ ${id} == rclone ]] && rclone_backup=1; done < <(dots_group_package_ids backup optional)
[[ ${rclone_backup} -eq 0 ]] && ok "rclone not duplicated into backup" || bad "rclone duplicated"

echo "=== hardware package ownership ==="
for p in smartmontools fio picocom usbutils pciutils; do
	found=0
	while IFS= read -r id; do [[ ${id} == "${p}" ]] && found=1; done < <(dots_group_package_ids hardware optional)
	[[ ${found} -eq 1 ]] && ok "hardware owns ${p}" || bad "hardware missing ${p}"
done
grep -q 'brew "smartmontools"' "${ROOT}/brew/groups/hardware.Brewfile" && ok "smartmontools Brewfile" || bad "smartmontools"
grep -q '"hardware"' "${ROOT}/configs/bootstrap/profiles/all.toml" && ok "all includes hardware" || bad "all missing hardware"

echo "=== no-scan / no-capture stubs ==="
mkdir -p "${TMP}/bin"
# Stubs that fail on probe/capture verbs
for bin in mtr nmap gping iperf3 bandwhich termshark tshark mosh; do
	cat >"${TMP}/bin/${bin}" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
--version|-v|version|--help|-h) echo "${bin} stub 0"; exit 0 ;;
esac
# Any other args treated as active probe/capture
echo "FORBIDDEN_${bin}:\$*" >&2
exit 99
EOF
	chmod +x "${TMP}/bin/${bin}"
done
cat >"${TMP}/bin/rclone" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in version) echo "rclone stub 0"; exit 0 ;; listremotes) exit 0 ;;
*) echo "FORBIDDEN_rclone:$*" >&2; exit 99 ;; esac
EOF
chmod +x "${TMP}/bin/rclone"
cat >"${TMP}/bin/tailscale" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
version) echo "1.0.0-stub"; exit 0 ;;
status)
  # allow read-only status; forbid up/login/set
  shift
  echo '{"BackendState":"NeedsLogin"}'
  exit 0
  ;;
up|login|set|switch|down)
  echo "FORBIDDEN_tailscale:$1" >&2
  exit 99
  ;;
*) echo "FORBIDDEN_tailscale:$*" >&2; exit 99 ;;
esac
EOF
chmod +x "${TMP}/bin/tailscale"

export PATH="${TMP}/bin:${PATH}"
nout="$("${NET}" status 2>&1)" || {
	bad "network status exit"
	nout=""
}
echo "${nout}" | grep -q 'FORBIDDEN_mtr\|FORBIDDEN_nmap\|FORBIDDEN_gping\|FORBIDDEN_iperf3' && bad "network probes invoked" || ok "no mtr/nmap/gping/iperf probes"
echo "${nout}" | grep -q 'FORBIDDEN_bandwhich\|FORBIDDEN_termshark\|FORBIDDEN_tshark' && bad "packet capture invoked" || ok "no packet capture"
echo "${nout}" | grep -q 'FORBIDDEN_mosh' && bad "mosh connection invoked" || ok "no mosh connection"
echo "${nout}" | grep -q 'FORBIDDEN_tailscale' && bad "tailscale up/login/set invoked" || ok "no tailscale up/login/set"
echo "${nout}" | grep -qi 'NeedsLogin\|logged in' && ok "tailscale status reported" || ok "tailscale block present"
echo "${nout}" | grep -qi 'No host/subnet scans\|No tailscale up' && ok "network invariants stated" || bad "network invariants"

echo "=== hardware stubs ==="
cat >"${TMP}/bin/smartctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in --version|-V|version) echo "smartctl stub 0"; exit 0 ;;
-t|--test|*)
  for a in "$@"; do
    case "$a" in -t|--test|/dev/*) echo "FORBIDDEN_smartctl:$*" >&2; exit 99 ;; esac
  done
  echo "smartctl stub"; exit 0
  ;;
esac
EOF
cat >"${TMP}/bin/fio" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in --version|-v) echo "fio stub 0"; exit 0 ;;
*) echo "FORBIDDEN_fio:$*" >&2; exit 99 ;;
esac
EOF
cat >"${TMP}/bin/picocom" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in --help|-h) echo "picocom stub help"; exit 0 ;;
*)
  for a in "$@"; do
    case "$a" in /dev/*) echo "FORBIDDEN_serial:$a" >&2; exit 99 ;; esac
  done
  echo "FORBIDDEN_picocom:$*" >&2; exit 99
  ;;
esac
EOF
cat >"${TMP}/bin/lsusb" <<'EOF'
#!/usr/bin/env bash
echo "FORBIDDEN_lsusb_scan" >&2; exit 99
EOF
cat >"${TMP}/bin/lspci" <<'EOF'
#!/usr/bin/env bash
echo "FORBIDDEN_lspci_scan" >&2; exit 99
EOF
chmod +x "${TMP}/bin/smartctl" "${TMP}/bin/fio" "${TMP}/bin/picocom" "${TMP}/bin/lsusb" "${TMP}/bin/lspci"

hout="$("${HW}" status 2>&1)" || {
	bad "hardware status exit"
	hout=""
}
echo "${hout}" | grep -q 'FORBIDDEN_smartctl' && bad "SMART test invoked" || ok "no SMART self-test"
echo "${hout}" | grep -q 'FORBIDDEN_fio' && bad "fio workload invoked" || ok "no fio workload"
echo "${hout}" | grep -q 'FORBIDDEN_serial\|FORBIDDEN_picocom' && bad "serial opened" || ok "no serial device open"
# lsusb/lspci: status only checks have(); must not execute them for inventory
echo "${hout}" | grep -q 'FORBIDDEN_lsusb\|FORBIDDEN_lspci' && bad "bus enumeration executed" || ok "no bus enumeration during check"

echo "=== no privilege escalation in validate scripts ==="
# Allow the word in examples/docs heredocs; forbid actual invocations outside examples.
if rg -n '(^|[[:space:]])(sudo|doas|pkexec)[[:space:]]+[a-zA-Z]' "${NET}" "${HW}" 2>/dev/null |
	rg -v 'examples|EOF|Privileged|often needs|user-directed|No sudo|sudo/doas|# ' | grep -q .; then
	bad "sudo/doas/pkexec invocation in validate scripts"
else
	ok "no sudo invocation in validate scripts"
fi
# Ensure status path does not call sudo
if rg -n '^\s*(sudo|doas|pkexec)\s' "${NET}" "${HW}" 2>/dev/null | grep -q .; then
	bad "sudo as command in validate scripts"
else
	ok "sudo not used as a command"
fi

echo "=== no ssh→mosh alias ==="
if rg -n 'alias[[:space:]]+ssh=.*mosh' "${ROOT}" --glob '!vendor/**' --glob '!**/*.md' 2>/dev/null | grep -q .; then
	bad "ssh aliased to mosh"
else
	ok "ssh not aliased to mosh"
fi

echo "=== CLI help ==="
chk="$("${ROOT}/dots" check --help 2>&1)" || true
echo "${chk}" | grep -q 'check network' && ok "help mentions network" || bad "help missing network"
echo "${chk}" | grep -q 'check hardware' && ok "help mentions hardware" || bad "help missing hardware"

echo "=== YubiKey independence ==="
rg -q 'ykman|YubiKey|age-plugin' "${NET}" "${HW}" && bad "network/hardware validate reference YubiKey" || ok "independent of YubiKey"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
