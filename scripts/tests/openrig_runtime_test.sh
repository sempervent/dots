#!/usr/bin/env bash
# scripts/tests/openrig_runtime_test.sh — Node/npm/OpenRig desired-state (mocked; no network)
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

echo "=== openrig runtime policy + helpers ==="
[[ -f ${ROOT}/configs/agents/openrig/runtime.toml ]] && ok "runtime.toml" || bad "runtime.toml"
[[ -f ${ROOT}/helpers/fnm.sh ]] && ok "fnm.sh" || bad "fnm.sh"
[[ -f ${ROOT}/helpers/openrig.sh ]] && ok "openrig.sh" || bad "openrig.sh"
rg -q 'preferred_major = 22' "${ROOT}/configs/agents/openrig/runtime.toml" && ok "preferred Node 22" || bad "preferred major"
rg -q 'run_rig_setup = false' "${ROOT}/configs/agents/openrig/runtime.toml" && ok "no rig setup" || bad "rig setup policy"
rg -q 'allow_sudo_npm = false' "${ROOT}/configs/agents/openrig/runtime.toml" && ok "no sudo npm" || bad "sudo policy"
rg -qi 'never nvm|Do NOT use nvm|never installs or sources nvm' "${ROOT}/helpers/openrig.sh" "${ROOT}/helpers/fnm.sh" && ok "fnm-only policy" || bad "nvm policy text"
rg -q 'check-abi' "${ROOT}/helpers/openrig.sh" && ok "ABI check wired" || bad "ABI"
rg -q 'dots_openrig_check_abi' "${ROOT}/helpers/openrig.sh" && ok "ABI function" || bad "ABI fn"
! grep -Eq 'sudo[[:space:]]+npm[[:space:]]+install' "${ROOT}/helpers/openrig.sh" && ok "no sudo npm install" || bad "sudo npm install present"
! rg -q 'rig setup' "${ROOT}/helpers/openrig.sh" || rg -q "does not run 'rig setup'|not run.*rig setup|Do NOT run \`rig setup\`" "${ROOT}/helpers/openrig.sh"
rg -q "does not run 'rig setup'|Do NOT run \`rig setup\`" "${ROOT}/helpers/openrig.sh" && ok "no blind rig setup" || bad "rig setup guard"
rg -q 'brew "fnm"' "${ROOT}/brew/Brewfile.openrig" && ok "Brewfile fnm" || bad "Brewfile fnm"
rg -q 'brew "tmux"' "${ROOT}/brew/Brewfile.openrig" && ok "Brewfile tmux" || bad "Brewfile tmux"

echo "=== load helpers (dry-run install path) ==="
TMP="$(mktemp -d)"
export HOME="${TMP}"
export DIR="${ROOT}"
export DRY_RUN=1
# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/fnm.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/openrig.sh"

dots_openrig_load_runtime_policy
[[ ${DOTS_OPENRIG_NODE_MAJOR} == "22" ]] && ok "loaded preferred major 22" || bad "major=${DOTS_OPENRIG_NODE_MAJOR}"
[[ ${DOTS_OPENRIG_NPM_PKG} == "@openrig/cli" ]] && ok "package @openrig/cli" || bad "pkg"

out="$(dots_openrig_install 2>&1 || true)"
echo "${out}" | rg -q 'ensure fnm' && ok "dry-run ensures fnm" || bad "dry-run fnm"
echo "${out}" | rg -q 'Node 22' && ok "dry-run Node 22" || bad "dry-run node"
echo "${out}" | rg -q 'npm install -g @openrig/cli|install -g @openrig/cli' && ok "dry-run npm install" || bad "dry-run npm"
echo "${out}" | rg -qi 'ABI|check-abi' && ok "dry-run ABI" || bad "dry-run ABI"
echo "${out}" | rg -q 'not rig setup|skip Herdr' && ok "dry-run skips rig setup" || bad "dry-run setup skip"

echo "=== package state classification (mocked prefixes) ==="
# Fake node/npm/rig layout under TMP
fake_node_root="${TMP}/fnm/node-versions/v22.11.0/installation"
mkdir -p "${fake_node_root}/bin" "${fake_node_root}/lib/node_modules"
cat >"${fake_node_root}/bin/node" <<'EOF'
#!/bin/sh
echo v22.11.0
EOF
cat >"${fake_node_root}/bin/npm" <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo 10.9.0 ;;
  prefix) [[ "$2" == "-g" ]] && echo "$(cd "$(dirname "$0")/.." && pwd)" ;;
  root) [[ "$2" == "-g" ]] && echo "$(cd "$(dirname "$0")/.." && pwd)/lib/node_modules" ;;
  list) echo "└── @openrig/cli@0.7.7" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${fake_node_root}/bin/node" "${fake_node_root}/bin/npm"
export PATH="${fake_node_root}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
unset DRY_RUN

# MISSING when no package and no rig
rm -f "${fake_node_root}/bin/rig"
# override npm list to empty
cat >"${fake_node_root}/bin/npm" <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo 10.9.0 ;;
  prefix) [[ "$2" == "-g" ]] && echo "$(cd "$(dirname "$0")/.." && pwd)" ;;
  root) [[ "$2" == "-g" ]] && echo "$(cd "$(dirname "$0")/.." && pwd)/lib/node_modules" ;;
  list) echo "(empty)" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${fake_node_root}/bin/npm"
state="$(dots_openrig_package_state)"
[[ ${state} == "MISSING" ]] && ok "state MISSING" || bad "state want MISSING got ${state}"

# INSTALLED_COMPATIBLE
cat >"${fake_node_root}/bin/npm" <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo 10.9.0 ;;
  prefix) [[ "$2" == "-g" ]] && echo "$(cd "$(dirname "$0")/.." && pwd)" ;;
  root) [[ "$2" == "-g" ]] && echo "$(cd "$(dirname "$0")/.." && pwd)/lib/node_modules" ;;
  list) echo "└── @openrig/cli@0.7.7" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${fake_node_root}/bin/npm"
cat >"${fake_node_root}/bin/rig" <<'EOF'
#!/bin/sh
echo "0.7.7 (deadbeef)"
EOF
chmod +x "${fake_node_root}/bin/rig"
state="$(dots_openrig_package_state)"
[[ ${state} == "INSTALLED_COMPATIBLE" ]] && ok "state COMPATIBLE" || bad "state want COMPATIBLE got ${state}"

# Stale PATH: rig elsewhere should be WRONG_PREFIX when npm list empty but foreign rig exists
mkdir -p "${TMP}/stale/bin"
cat >"${TMP}/stale/bin/rig" <<'EOF'
#!/bin/sh
echo "0.6.0-stale"
EOF
chmod +x "${TMP}/stale/bin/rig"
rm -f "${fake_node_root}/bin/rig"
cat >"${fake_node_root}/bin/npm" <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo 10.9.0 ;;
  prefix) [[ "$2" == "-g" ]] && echo "$(cd "$(dirname "$0")/.." && pwd)" ;;
  root) [[ "$2" == "-g" ]] && echo "$(cd "$(dirname "$0")/.." && pwd)/lib/node_modules" ;;
  list) echo "(empty)" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${fake_node_root}/bin/npm"
export PATH="${TMP}/stale/bin:${fake_node_root}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
state="$(dots_openrig_package_state)"
[[ ${state} == "INSTALLED_WRONG_PREFIX" ]] && ok "stale PATH → WRONG_PREFIX" || bad "stale want WRONG_PREFIX got ${state}"

# dots_openrig_rig_bin must reject stale PATH
if dots_openrig_rig_bin >/dev/null 2>&1; then
	bad "rig_bin accepted stale PATH"
else
	ok "rig_bin rejects stale PATH"
fi

echo "=== npm belongs to node ==="
export PATH="${fake_node_root}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
if dots_npm_belongs_to_active_node; then
	ok "npm belongs to node"
else
	bad "npm belongs"
fi

# Wrong npm: put foreign npm earlier than node dir
mkdir -p "${TMP}/foreign/bin" "${TMP}/npm-only/bin"
cat >"${TMP}/npm-only/bin/npm" <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo 9.0.0 ;;
  prefix) echo /usr/local ;;
  root) echo /usr/local/lib/node_modules ;;
esac
EOF
chmod +x "${TMP}/npm-only/bin/npm"
export PATH="${TMP}/npm-only/bin:${fake_node_root}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
if dots_npm_belongs_to_active_node; then
	bad "should detect npm/node mismatch"
else
	ok "detects npm/node mismatch"
fi

echo "=== ABI script path construction ==="
export PATH="${fake_node_root}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
mkdir -p "${fake_node_root}/lib/node_modules/@openrig/cli/scripts"
echo 'console.log("abi-ok")' >"${fake_node_root}/lib/node_modules/@openrig/cli/scripts/check-abi.mjs"
# Fix npm root/prefix for this layout
cat >"${fake_node_root}/bin/npm" <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo 10.9.0 ;;
  prefix)
    if [[ "${2:-}" == "-g" ]]; then
      echo "$(cd "$(dirname "$0")/.." && pwd)"
    fi
    ;;
  root)
    if [[ "${2:-}" == "-g" ]]; then
      echo "$(cd "$(dirname "$0")/.." && pwd)/lib/node_modules"
    fi
    ;;
  list) echo "└── @openrig/cli@0.7.7" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${fake_node_root}/bin/npm"
script="$(dots_openrig_abi_script)"
[[ ${script} == *"/@openrig/cli/scripts/check-abi.mjs" ]] && ok "ABI script path" || bad "ABI path=${script}"

# Missing script → check fails
rm -f "${fake_node_root}/lib/node_modules/@openrig/cli/scripts/check-abi.mjs"
if dots_openrig_check_abi 2>/tmp/dots-abi-miss.err; then
	bad "ABI should fail when script absent"
else
	ok "ABI fails when script absent"
fi

echo "=== doctor is read-only (no install verbs on missing fnm mock) ==="
# Doctor should not call npm install — just report. Use empty PATH-ish env with only basics.
export PATH="${fake_node_root}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
# Provide a fake fnm so doctor classifies Node
mkdir -p "${TMP}/fnmbin"
cat >"${TMP}/fnmbin/fnm" <<'EOF'
#!/bin/sh
echo "fnm 1.0.0-test"
EOF
chmod +x "${TMP}/fnmbin/fnm"
export PATH="${TMP}/fnmbin:${fake_node_root}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
# Restore ABI script + rig for a partial OK doctor
mkdir -p "${fake_node_root}/lib/node_modules/@openrig/cli/scripts"
echo 'process.exit(0)' >"${fake_node_root}/lib/node_modules/@openrig/cli/scripts/check-abi.mjs"
cat >"${fake_node_root}/bin/rig" <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo "0.7.7 (test)" ;;
  --help) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${fake_node_root}/bin/rig"
# node -e for ABI: our fake node only prints version — make it exec scripts
cat >"${fake_node_root}/bin/node" <<'EOF'
#!/bin/sh
if [[ "${1:-}" == "-v" || "${1:-}" == "--version" ]]; then
  echo v22.11.0
  exit 0
fi
# ABI script: succeed
exit 0
EOF
chmod +x "${fake_node_root}/bin/node"

doc="$(dots_openrig_doctor 2>&1 || true)"
echo "${doc}" | rg -q 'OpenRig Runtime' && ok "doctor header" || bad "doctor header"
echo "${doc}" | rg -q 'preferred 22' && ok "doctor policy" || bad "doctor policy"
echo "${doc}" | rg -q 'Repair:' && echo "${doc}" | rg -q 'setup --with openrig' && ok "doctor repair hint" || true
# Must not mention performing install in doctor mode
echo "${doc}" | rg -qi 'Installing @openrig' && bad "doctor must not install" || ok "doctor does not install"

rm -rf "${TMP}"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
