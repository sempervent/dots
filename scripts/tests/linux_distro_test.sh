#!/usr/bin/env bash
# scripts/tests/linux_distro_test.sh — /etc/os-release parsing + pkg family hints
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() {
	echo "OK: $1"
	pass=$((pass + 1))
}
bad() {
	echo "FAIL: $1" >&2
	fail=$((fail + 1))
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-linux-distro.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

# shellcheck disable=SC1091
source "${ROOT}/helpers/hardware.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/packages.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/linux_distro.sh"

write_os() {
	cat >"${TMP}/os-release"
	export DOTS_OS_RELEASE_FILE="${TMP}/os-release"
}

echo "=== ubuntu → debian / apt ==="
write_os <<'EOF'
PRETTY_NAME="Ubuntu 24.04.1 LTS"
NAME="Ubuntu"
ID=ubuntu
ID_LIKE=debian
VERSION_ID="24.04"
EOF
[[ $(dots_linux_distro_id) == ubuntu ]] && ok "ubuntu id" || bad "ubuntu id=$(dots_linux_distro_id)"
[[ $(dots_linux_distro_family) == debian ]] && ok "ubuntu family debian" || bad "ubuntu family"
[[ $(dots_linux_expected_pkg_mgr) == apt ]] && ok "ubuntu expects apt" || bad "ubuntu pkg"
dots_linux_is_raspbian && bad "ubuntu not raspbian" || ok "ubuntu not raspbian"

echo "=== debian → debian / apt ==="
write_os <<'EOF'
PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
NAME="Debian GNU/Linux"
ID=debian
VERSION_ID="13"
EOF
[[ $(dots_linux_distro_id) == debian ]] && ok "debian id" || bad "debian id"
[[ $(dots_linux_distro_family) == debian ]] && ok "debian family" || bad "debian family"
[[ $(dots_linux_expected_pkg_mgr) == apt ]] && ok "debian expects apt" || bad "debian pkg"

echo "=== raspbian → debian / apt ==="
write_os <<'EOF'
PRETTY_NAME="Raspbian GNU/Linux 12 (bookworm)"
NAME="Raspbian GNU/Linux"
ID=raspbian
ID_LIKE=debian
VERSION_ID="12"
EOF
[[ $(dots_linux_distro_id) == raspbian ]] && ok "raspbian id" || bad "raspbian id=$(dots_linux_distro_id)"
[[ $(dots_linux_distro_family) == debian ]] && ok "raspbian family debian" || bad "raspbian family"
[[ $(dots_linux_expected_pkg_mgr) == apt ]] && ok "raspbian expects apt" || bad "raspbian pkg"
dots_linux_is_raspbian && ok "raspbian detected" || bad "raspbian detect"

echo "=== raspberry pi os (ID=debian + pretty) ==="
write_os <<'EOF'
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
NAME="Debian GNU/Linux"
ID=debian
VERSION_CODENAME=bookworm
EOF
# Without rpi markers, plain debian is fine
dots_linux_is_raspbian && bad "plain debian not raspbian" || ok "plain debian not raspbian"

echo "=== arch → arch / pacman ==="
write_os <<'EOF'
NAME="Arch Linux"
PRETTY_NAME="Arch Linux"
ID=arch
BUILD_ID=rolling
EOF
[[ $(dots_linux_distro_id) == arch ]] && ok "arch id" || bad "arch id"
[[ $(dots_linux_distro_family) == arch ]] && ok "arch family" || bad "arch family"
[[ $(dots_linux_expected_pkg_mgr) == pacman ]] && ok "arch expects pacman" || bad "arch pkg"

echo "=== manjaro → arch / pacman ==="
write_os <<'EOF'
NAME="Manjaro Linux"
PRETTY_NAME="Manjaro Linux"
ID=manjaro
ID_LIKE=arch
EOF
[[ $(dots_linux_distro_id) == manjaro ]] && ok "manjaro id" || bad "manjaro id"
[[ $(dots_linux_distro_family) == arch ]] && ok "manjaro family arch" || bad "manjaro family"
[[ $(dots_linux_expected_pkg_mgr) == pacman ]] && ok "manjaro expects pacman" || bad "manjaro pkg"

echo "=== fedora → fedora / dnf ==="
write_os <<'EOF'
NAME="Fedora Linux"
PRETTY_NAME="Fedora Linux 41"
ID=fedora
VERSION_ID=41
EOF
[[ $(dots_linux_distro_id) == fedora ]] && ok "fedora id" || bad "fedora id"
[[ $(dots_linux_distro_family) == fedora ]] && ok "fedora family" || bad "fedora family"
[[ $(dots_linux_expected_pkg_mgr) == dnf ]] && ok "fedora expects dnf" || bad "fedora pkg"

echo "=== void → void / xbps ==="
write_os <<'EOF'
NAME="void"
PRETTY_NAME="Void Linux"
ID=void
EOF
[[ $(dots_linux_distro_id) == void ]] && ok "void id" || bad "void id"
[[ $(dots_linux_distro_family) == void ]] && ok "void family" || bad "void family"
[[ $(dots_linux_expected_pkg_mgr) == xbps ]] && ok "void expects xbps" || bad "void pkg"

echo "=== unknown distro family ==="
write_os <<'EOF'
NAME="MysteryOS"
ID=mysteryos
EOF
[[ $(dots_linux_distro_family) == unknown ]] && ok "unknown family" || bad "mystery family=$(dots_linux_distro_family)"
[[ $(dots_linux_expected_pkg_mgr) == unknown ]] && ok "unknown expects unknown pkg" || bad "mystery pkg"

echo "=== architecture normalization ==="
export DOTS_FORCE_ARCH=aarch64
[[ $(dots_linux_arch) == arm64 ]] && ok "aarch64→arm64" || bad "arch aarch64"
export DOTS_FORCE_ARCH=arm64
[[ $(dots_linux_arch) == arm64 ]] && ok "arm64" || bad "arch arm64"
export DOTS_FORCE_ARCH=amd64
[[ $(dots_linux_arch) == x86_64 ]] && ok "amd64→x86_64" || bad "arch amd64"
export DOTS_FORCE_ARCH=x86_64
[[ $(dots_linux_arch) == x86_64 ]] && ok "x86_64" || bad "arch x86_64"
unset DOTS_FORCE_ARCH

echo "=== platform report emits Platform: ==="
write_os <<'EOF'
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 24.04"
EOF
export DOTS_FORCE_OS=linux DOTS_FORCE_ARCH=x86_64
# Without apt on this host, pkg mgr may be unknown — report still prints
rep="$(dots_linux_platform_report)"
echo "${rep}" | grep -q '^Platform:' && ok "report header" || bad "report header"
echo "${rep}" | grep -qi 'ubuntu\|debian' && ok "report mentions distro" || bad "report distro"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
