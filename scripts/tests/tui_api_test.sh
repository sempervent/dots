#!/usr/bin/env bash
# scripts/tests/tui_api_test.sh — structured JSON APIs, batch mutate, and `dots tui` non-TTY safety
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="${ROOT}"
export DIR ROOT DOTS_DIR="${ROOT}"

unset DOTS_PROFILE DOTS_ACTIVE_COMPONENTS DOTS_PACKAGE_GROUPS DOTS_MULTIPLEXER DOTS_PROFILE_FILE || true

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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-tui-api.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

export HOME="${TMP}/home"
mkdir -p "${HOME}/.config/dots/profiles"

# Seed active profile = home
cat >"${HOME}/.config/dots/active-profile" <<EOF
DOTS_PROFILE='home'
DOTS_PROFILE_FILE='${ROOT}/configs/bootstrap/profiles/home.toml'
DOTS_PACKAGE_GROUPS='core modern'
EOF

echo "=== 1. Structured JSON endpoints parse cleanly ==="
for cmd in \
	"profile show --json" \
	"profile list --json" \
	"components list --json" \
	"packages groups --json" \
	"profile resolve hyperfine --json" \
	"profile plan --profile base --add dev --add karabiner-elements --json" \
	"upgrade --dry-run --json"; do
	set +e
	# shellcheck disable=SC2086
	out="$("${ROOT}/dots" ${cmd} 2>&1)"
	rc=$?
	set -e
	if [[ ${rc} -eq 0 ]] && printf '%s\n' "${out}" | python3 -c 'import json, sys; json.load(sys.stdin)' 2>/dev/null; then
		ok "valid JSON: dots ${cmd}"
	else
		bad "invalid JSON (rc=${rc}): dots ${cmd}"
		echo "${out}" | head -n 20 >&2 || true
	fi
done

echo "=== 2. Plain human output preserved ==="
plain_show="$("${ROOT}/dots" profile show home 2>&1)"
echo "${plain_show}" | grep -q 'package groups:' && ok "plain profile show preserved" || bad "plain profile show broken"
plain_groups="$("${ROOT}/dots" packages groups 2>&1)"
echo "${plain_groups}" | grep -q 'PACKAGE GROUPS' && ok "plain packages groups preserved" || bad "plain packages groups broken"

echo "=== 3. JSON schema & synthetic registry support ==="
syn_g="${TMP}/groups.toml"
cat >"${syn_g}" <<'EOF'
version = 1
[[groups]]
name = "core"
description = "Core"
required = ["bash"]
optional = []
[[groups]]
name = "quantum-cabbage"
description = "Synthetic quantum cabbage"
required = ["cabbage"]
optional = []
EOF
syn_out="$(DOTS_GROUPS_REGISTRY="${syn_g}" "${ROOT}/dots" packages groups --profile base --json)"
printf '%s\n' "${syn_out}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
names = [g["name"] for g in d["groups"]]
assert "quantum-cabbage" in names, names
' && ok "synthetic group via packages groups --json" || bad "synthetic group missing"

echo "=== 4. Batch profile mutate (atomic single overlay write, builtin immutable) ==="
home_before="$(cksum <"${ROOT}/configs/bootstrap/profiles/home.toml")"
DRY_RUN_OUT="$(DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15 "${ROOT}/dots" profile mutate --profile home --add group:dev --add component:karabiner-elements --remove group:network --dry-run --yes 2>&1)"
echo "${DRY_RUN_OUT}" | grep -q '\[dry-run\] No files modified' && ok "mutate dry-run" || bad "mutate dry-run: ${DRY_RUN_OUT}"
[[ ! -f ${HOME}/.config/dots/profiles/home-local.toml ]] && ok "mutate dry-run wrote zero files" || bad "mutate dry-run created file"

DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15 \
	"${ROOT}/dots" profile mutate --profile home --add component:karabiner-elements --remove group:network --yes >/dev/null 2>&1
home_after="$(cksum <"${ROOT}/configs/bootstrap/profiles/home.toml")"
[[ ${home_before} == "${home_after}" ]] && ok "builtin home.toml immutable" || bad "home.toml modified"
[[ -f ${HOME}/.config/dots/profiles/home-local.toml ]] && ok "home-local.toml created" || bad "home-local missing"

state_json="$(DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15 "${ROOT}/dots" profile show --json)"
printf '%s\n' "${state_json}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["profile"] == "home-local", d["profile"]
assert d["groups"]["modern"]["state"] == "inherited"
assert d["groups"]["network"]["state"] == "excluded"
assert d["components"]["karabiner-elements"]["state"] == "local"
' && ok "profile show --json reflects inherited/excluded/local" || bad "state_json mismatch"

echo "=== 5. Atomic batch abort on invalid selector ==="
ov_before="$(cksum <"${HOME}/.config/dots/profiles/home-local.toml")"
set +e
"${ROOT}/dots" profile mutate --add group:geo --add totally-fake-pkg --yes >/dev/null 2>&1
bad_rc=$?
set -e
ov_after="$(cksum <"${HOME}/.config/dots/profiles/home-local.toml")"
[[ ${bad_rc} -ne 0 && ${ov_before} == "${ov_after}" ]] && ok "invalid batch aborted atomically" || bad "batch wrote partial state"

echo "=== 6b. explicit profile show reports real active state ==="
home_local="${HOME}/.config/dots/profiles/home-local.toml"
# home-local already exists from section 4 and is the active marker target
show_active="$("${ROOT}/dots" profile show home-local --json)"
show_work="$("${ROOT}/dots" profile show work --json)"
show_base="$("${ROOT}/dots" profile show base --json)"
show_none="$("${ROOT}/dots" profile show --json)"
python3 - "${show_active}" "${show_work}" "${show_base}" "${show_none}" <<'PY'
import json, sys
active, work, base, none = (json.loads(x) for x in sys.argv[1:5])
assert active["active"] is True, active["profile"]
assert active["profile"] == "home-local"
assert work["active"] is False, work
assert work["profile"] == "work"
assert base["active"] is False, base
assert none["active"] is True and none["profile"] == "home-local", none["profile"]
PY
ok "explicit profile active flag matches the machine pointer"

echo "=== 6. dots tui --help and non-TTY safety ==="
tui_help="$("${ROOT}/dots" tui --help 2>&1)"
echo "${tui_help}" | grep -q 'dots tui' && ok "dots tui --help" || bad "dots tui --help"
set +e
tui_nontty="$("${ROOT}/dots" tui </dev/null 2>&1)"
tui_rc=$?
set -e
[[ ${tui_rc} -ne 0 ]] && echo "${tui_nontty}" | grep -qi 'TTY' && ok "dots tui refuses non-TTY safely" || bad "dots tui non-TTY: ${tui_nontty}"

echo ""
echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
