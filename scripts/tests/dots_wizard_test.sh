#!/usr/bin/env bash
# scripts/tests/dots_wizard_test.sh — scripted ./dots setup wizard (dry-run, temp HOME)
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

# Run wizard dry-run with answer lines. Prints: home|out|rc|mutated
_wiz_parse() {
	local name="$1"
	shift
	local home out rc mut=0 answers="" a
	home="$(mktemp -d "${TMPDIR:-/tmp}/dots-wiz-${name}.XXXXXX")"
	out="${home}/out.txt"
	for a in "$@"; do
		answers+="${a}"$'\n'
	done
	set +e
	HOME="${home}" DOTS_UI_ANSWERS="${answers}" \
		"${ROOT}/dots" setup --dry-run >"${out}" 2>&1
	rc=$?
	set -e
	if [[ -d ${home}/.config/dots/profiles ]] && [[ -n $(ls -A "${home}/.config/dots/profiles" 2>/dev/null || true) ]]; then
		mut=1
	fi
	[[ -f ${home}/.config/dots/models.toml ]] && mut=1
	[[ -d ${home}/.local/state/dots ]] && mut=1
	printf '%s|%s|%s|%s\n' "${home}" "${out}" "${rc}" "${mut}"
}

echo "=== wizard: work as-is, skip models ==="
IFS='|' read -r whome wout wrc wmut < <(_wiz_parse work 2 y)
if [[ ${wrc} -eq 0 ]]; then
	ok "work dry-run exit 0"
else
	bad "work dry-run rc=${wrc}"
	tail -40 "${wout}" || true
fi
grep -q 'work' "${wout}" && ok "work plan mentions work" || bad "work plan profile"
grep -qiE 'skip|not now|No local model|Models:' "${wout}" && ok "work models section" || bad "work models"
[[ ${wmut} -eq 0 ]] && ok "work dry-run no HOME mutation" || bad "work mutated HOME"
rm -rf "${whome}"

echo "=== wizard: home as-is, models not now ==="
# 1=home, y=as-is, 3=models not now (home has AI stack → models prompt)
IFS='|' read -r hhome hout hrc hmut < <(_wiz_parse home 1 y 3)
[[ ${hrc} -eq 0 ]] && ok "home dry-run exit 0" || {
	bad "home rc=${hrc}"
	tail -40 "${hout}" || true
}
grep -q 'home' "${hout}" && ok "home plan" || bad "home plan"
grep -qiE 'skip|not now' "${hout}" && ok "home models skipped" || bad "home models skip"
[[ ${hmut} -eq 0 ]] && ok "home dry-run clean HOME" || bad "home mutated"
rm -rf "${hhome}"

echo "=== wizard: server customize bertha + ollama/llamacpp + balanced ==="
# 3=server, n=customize, hostname n, name=bertha,
# ai n, skills n, aiskills n, images n, tex n, ollama y, llamacpp y,
# mux 1 (tmux), infra y, models 2 (choose), tier 3 (balanced), cleanup n
IFS='|' read -r shome sout src smut < <(_wiz_parse server \
	3 n n bertha \
	n n n n n n \
	y y \
	1 \
	y \
	2 3 n)
[[ ${src} -eq 0 ]] && ok "server custom dry-run exit 0" || {
	bad "server rc=${src}"
	tail -60 "${sout}" || true
}
grep -q 'bertha' "${sout}" && ok "server plan names bertha" || bad "bertha name"
grep -q 'ollama' "${sout}" && ok "server with ollama" || bad "server ollama"
grep -q 'llamacpp' "${sout}" && ok "server with llamacpp" || bad "server llamacpp"
grep -qi 'balanced\|tier' "${sout}" && ok "server model tier" || bad "server tier"
[[ ${smut} -eq 0 ]] && ok "server dry-run clean HOME" || bad "server mutated"
rm -rf "${shome}"

echo "=== wizard: AI supergroup + exclusion ==="
os="$(uname -s)"
if [[ ${os} == Darwin ]]; then
	# home customize: hostname n, name, keep defaults n,
	# ai y, exclude cursor y, codex n, fluidvoice n, drawthings n,
	# herdr n, skills n, aiskills n, images n, tex n,
	# mux 2 (herdr default → sparse clear), models not now
	IFS='|' read -r chome cout crc cmut < <(_wiz_parse aicustom \
		1 n n home-custom \
		n \
		y y n n n n \
		n n n n n \
		2 \
		3)
else
	# Linux skips unavailable excludes; drawthings still offered
	IFS='|' read -r chome cout crc cmut < <(_wiz_parse aicustom \
		1 n n home-custom \
		n \
		y n n \
		n n n n n \
		1 \
		3)
fi
[[ ${crc} -eq 0 ]] && ok "ai custom dry-run exit 0" || {
	bad "ai custom rc=${crc}"
	tail -60 "${cout}" || true
}
grep -Eq 'with:.*ai|"ai"|with: ai' "${cout}" && ok "ai with in plan" || {
	grep -q 'ai' "${cout}" && ok "ai mentioned" || bad "ai with"
}
[[ ${cmut} -eq 0 ]] && ok "ai custom dry-run clean" || bad "ai mutated"
rm -rf "${chome}"

echo "=== wizard: abort before apply ==="
ahome="$(mktemp -d "${TMPDIR:-/tmp}/dots-abort.XXXXXX")"
set +e
HOME="${ahome}" DOTS_UI_ANSWERS=$'2\ny\n3\n' \
	"${ROOT}/dots" setup >"${ahome}/out.txt" 2>&1
set -e
grep -q 'No changes made' "${ahome}/out.txt" && ok "abort message" || {
	bad "abort message"
	tail -30 "${ahome}/out.txt" || true
}
[[ ! -f ${ahome}/.config/dots/models.toml ]] && ok "abort no models.toml" || bad "abort wrote models"
if [[ ! -d ${ahome}/.config/dots/profiles ]] || [[ -z $(ls -A "${ahome}/.config/dots/profiles" 2>/dev/null || true) ]]; then
	ok "abort no profile write"
else
	bad "abort wrote profile"
fi
rm -rf "${ahome}"

echo "=== wizard: existing profile → verify only ==="
ehome="$(mktemp -d "${TMPDIR:-/tmp}/dots-exist.XXXXXX")"
mkdir -p "${ehome}/.config/dots"
cat >"${ehome}/.config/dots/active-profile" <<EOF
DOTS_PROFILE='server'
DOTS_PROFILE_FILE='${ROOT}/configs/bootstrap/profiles/server.toml'
EOF
set +e
HOME="${ehome}" DOTS_UI_ANSWERS=$'4\n' \
	"${ROOT}/dots" setup --dry-run >"${ehome}/out.txt" 2>&1
set -e
grep -qiE 'Existing|Verify|check|Health|server|DOTS' "${ehome}/out.txt" && ok "existing-machine menu" || {
	bad "existing menu"
	tail -40 "${ehome}/out.txt" || true
}
rm -rf "${ehome}"

echo "=== profile TOML writer ==="
DIR="${ROOT}"
# shellcheck disable=SC1091
source "${ROOT}/helpers/state.sh"
td="$(mktemp -d)"
dots_write_profile_toml_bash "${td}/x.toml" "x" "server" "test" "tmux" "ai,ollama" "cursor" "infra"
grep -q 'extends = "server"' "${td}/x.toml" && ok "toml extends" || bad "toml extends"
grep -q '"ai"' "${td}/x.toml" && ok "toml with ai" || bad "toml with"
grep -q '"cursor"' "${td}/x.toml" && ok "toml without cursor" || bad "toml without"
grep -q 'multiplexer = "tmux"' "${td}/x.toml" && ok "toml mux" || bad "toml mux"
grep -q '"infra"' "${td}/x.toml" && ok "toml pkg" || bad "toml pkg"
rm -rf "${td}"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
