#!/usr/bin/env bash
# Explicit native-manager convergence and profile-scope isolation.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

pass() { echo "OK: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

DIR="${ROOT}"
DRY_RUN=0
export DIR DRY_RUN DOTS_PKG_MOCK_NATIVE_INSTALL=1 DOTS_PKG_DISABLE_HOST_WHICH=1
# shellcheck source=../../helpers/python_runtime.sh
source "${ROOT}/helpers/python_runtime.sh"
# shellcheck source=../../helpers/packages.sh
source "${ROOT}/helpers/packages.sh"

for mgr in apt dnf pacman xbps; do
	log="$(mktemp)"
	export DOTS_FORCE_OS=linux DOTS_FORCE_PKG_MGR="${mgr}" DOTS_NATIVE_INSTALL_LOG="${log}"
	PROFILE_PKG_INCLUDE=(hyperfine)
	PROFILE_PKG_EXCLUDE=()
	DOTS_RESOLVED_GROUPS=()
	DOTS_WITH_COMPONENTS=()
	dots_provision_explicit_packages >/tmp/dots-explicit-"${mgr}".out
	grep -q "hyperfine" "${log}" || fail "${mgr} batch did not include mapped hyperfine token: $(cat "${log}")"
	case "${mgr}" in
	apt) grep -q 'apt-get install -y hyperfine' "${log}" || fail "apt command: $(cat "${log}")" ;;
	dnf) grep -q 'dnf install -y hyperfine' "${log}" || fail "dnf command: $(cat "${log}")" ;;
	pacman) grep -q 'pacman -Sy --noconfirm --needed hyperfine' "${log}" || fail "pacman command: $(cat "${log}")" ;;
	xbps) grep -q 'xbps-install -Sy hyperfine' "${log}" || fail "xbps command: $(cat "${log}")" ;;
	esac
	pass "explicit hyperfine installs via ${mgr}"
	rm -f "${log}"
done

# Requested profile must not inherit the active profile's explicit leaves.
HOME_A="$(mktemp -d)"
export HOME="${HOME_A}" DOTS_FORCE_OS=darwin DOTS_FORCE_PKG_MGR=brew DOTS_UI_NONINTERACTIVE=1
mkdir -p "${HOME_A}/.config/dots/profiles"
active="${HOME_A}/.config/dots/profiles/active-leaf.toml"
req="${HOME_A}/.config/dots/profiles/requested-leaf.toml"
cat >"${active}" <<'EOF'
[profile]
name = "active-leaf"
extends = "base"

[packages]
include = ["raycast"]
EOF
cat >"${req}" <<'EOF'
[profile]
name = "requested-leaf"
extends = "base"

[packages]
include = ["hyperfine"]
EOF
mkdir -p "${HOME_A}/.config/dots"
cat >"${HOME_A}/.config/dots/active-profile" <<EOF
DOTS_PROFILE='active-leaf'
DOTS_PROFILE_FILE='${active}'
DOTS_PACKAGE_GROUPS='core modern'
EOF

plan_out="$("${ROOT}/dots" packages plan --profile "${req}" 2>/dev/null)"
printf '%s\n' "${plan_out}" | grep -q 'hyperfine' || fail "requested plan missing hyperfine: ${plan_out}"
if printf '%s\n' "${plan_out}" | grep -q 'raycast'; then
	fail "requested plan leaked active explicit package raycast"
fi
pass "packages plan --profile uses requested explicit leaves only"

up="$("${ROOT}/dots" upgrade --profile "${req}" --dry-run --json 2>/dev/null || true)"
if printf '%s\n' "${up}" | grep -q 'raycast'; then
	fail "upgrade --profile leaked raycast: ${up}"
fi
pass "upgrade --profile does not use active explicit package"

bad_home="$(mktemp -d)"
export HOME="${bad_home}"
mkdir -p "${bad_home}/.config/dots/profiles"
bad="${bad_home}/.config/dots/profiles/bad-leaf.toml"
cat >"${bad}" <<'EOF'
[profile]
name = "bad-leaf"
extends = "base"

[packages]
include = ["racyast"]
EOF
if "${ROOT}/dots" profile show --profile "${bad}" >/tmp/dots-bad-leaf.out 2>&1; then
	fail "unknown packages.include was accepted"
fi
grep -q 'racyast' /tmp/dots-bad-leaf.out || fail "unknown package error missing"
pass "unknown packages.include rejected"

cat >"${bad}" <<'EOF'
[profile]
name = "bad-leaf"
extends = "base"

[packages]
include = ["@openrig/cli"]
EOF
if "${ROOT}/dots" profile show --profile "${bad}" >/tmp/dots-bad-leaf.out 2>&1; then
	fail "lifecycle packages.include was accepted"
fi
pass "lifecycle explicit package rejected"

rm -rf "${HOME_A}" "${bad_home}"
echo "explicit native and scope tests passed"
