#!/usr/bin/env bash
# scripts/tests/skills_location_test.sh — Hermes-targeted skill install verification
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-skills.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT
export HOME="${TMP}/home"
mkdir -p "${HOME}"
DIR="${ROOT}"
export DIR
DRY_RUN=0
DOTS_WITH_COMPONENTS=(hermes skills)

# Fake npx/skills that models Hermes-only install (the real-world failure)
mkdir -p "${TMP}/bin"
cat >"${TMP}/bin/npx" <<'EOF'
#!/usr/bin/env bash
# Fake: skills add … -a hermes-agent → only ~/.hermes/skills/<name>
set -euo pipefail
args=("$@")
# Find "skills" then "add"
# Typical: -y skills add SOURCE -g -y -s NAME -a hermes-agent
# or: -y skills add SOURCE -g -y -a hermes-agent
name=""
agent=""
i=0
while [[ $i -lt $# ]]; do
  a="${args[$i]}"
  case "$a" in
  -s|--skill) i=$((i+1)); name="${args[$i]}" ;;
  -a|--agent) i=$((i+1)); agent="${args[$i]}" ;;
  esac
  i=$((i+1))
done
# Infer name from package path when -s omitted (skill-security-review)
if [[ -z ${name} ]]; then
  for a in "${args[@]}"; do
    case "$a" in
    *skill-security-review*) name="skill-security-review" ;;
    *archify*) name="archify" ;;
    esac
  done
fi
[[ -n ${name} ]] || name="unknown-skill"
if [[ ${agent} == *hermes* ]]; then
  dest="${HOME}/.hermes/skills/${name}"
  mkdir -p "${dest}"
  printf '# Skill\n\nsafe content\n' >"${dest}/SKILL.md"
  echo "✓ ${name} (copied) -> ${dest}"
  exit 0
fi
dest="${HOME}/.agents/skills/${name}"
mkdir -p "${dest}"
printf '# Skill\n\nsafe content\n' >"${dest}/SKILL.md"
echo "✓ ${name} -> ${dest}"
exit 0
EOF
chmod +x "${TMP}/bin/npx"
# Also fake node
cat >"${TMP}/bin/node" <<'EOF'
#!/usr/bin/env bash
echo "v20.0.0"
EOF
chmod +x "${TMP}/bin/node"
export PATH="${TMP}/bin:${PATH}"

# Minimal python for static review
dots_python3() { command python3 "$@"; }
export -f dots_python3 2>/dev/null || true

# shellcheck disable=SC1091
source "${ROOT}/helpers/ai_consent.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/agent_skills.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/skills_pack.sh"

has_component() {
	local c="$1" x
	for x in "${DOTS_WITH_COMPONENTS[@]}"; do
		[[ ${x} == "${c}" ]] && return 0
	done
	return 1
}

echo "=== Hermes-only install (regression) ==="
# Clear agents path; install via hermes agent target
rm -rf "${HOME}/.agents" "${HOME}/.hermes"
DOTS_WITH_COMPONENTS=(hermes skills)
install_skill_from_source "skill-security-review" "dkleptsov/skill-security-review" "security" \
	>"${TMP}/out1" 2>&1 || {
	bad "hermes-only install failed"
	cat "${TMP}/out1"
}
if [[ -f ${HOME}/.hermes/skills/skill-security-review/SKILL.md ]]; then
	ok "hermes path has SKILL.md"
else
	bad "missing hermes skill"
fi
if [[ ! -e ${HOME}/.agents/skills/skill-security-review ]]; then
	ok "agents path absent (as upstream)"
else
	bad "agents path unexpectedly present"
fi
grep -q 'provider: Hermes Agent\|path:.*\.hermes/skills' "${TMP}/out1" && ok "reports hermes path" || bad "path report"
grep -qi 'static security review passed' "${TMP}/out1" && ok "review on hermes path" || bad "review: $(tail -5 "${TMP}/out1")"
agent_skill_is_installed skill-security-review && ok "is_installed hermes-only" || bad "is_installed"

echo "=== global only ==="
rm -rf "${HOME}/.agents" "${HOME}/.hermes"
DOTS_WITH_COMPONENTS=(skills) # no hermes
install_skill_from_source "systematic-debugging" "test/repo" "engineering" >"${TMP}/out2" 2>&1 || bad "global install"
[[ -f ${HOME}/.agents/skills/systematic-debugging/SKILL.md ]] && ok "global SKILL.md" || bad "global missing"
[[ ! -e ${HOME}/.hermes/skills/systematic-debugging ]] && ok "no hermes mutation without consent" || bad "hermes mutated"

echo "=== both locations ==="
mkdir -p "${HOME}/.agents/skills/both" "${HOME}/.hermes/skills/both"
echo '# a' >"${HOME}/.agents/skills/both/SKILL.md"
echo '# h' >"${HOME}/.hermes/skills/both/SKILL.md"
found="$(dots_skill_find both)"
[[ ${found} == "${HOME}/.agents/skills/both" ]] && ok "prefers agents when both" || bad "find both=${found}"

echo "=== neither / no SKILL.md / broken symlink ==="
agent_skill_is_installed missing-skill && bad "missing should fail" || ok "neither fails"
mkdir -p "${HOME}/.agents/skills/empty"
agent_skill_is_installed empty && bad "empty dir ok" || ok "dir without SKILL.md fails"
mkdir -p "${HOME}/.agents/skills"
ln -s /nonexistent/path "${HOME}/.agents/skills/broken"
agent_skill_is_installed broken && bad "broken symlink ok" || ok "broken symlink fails"
mkdir -p "${HOME}/.real-skill"
echo '# ok' >"${HOME}/.real-skill/SKILL.md"
ln -s "${HOME}/.real-skill" "${HOME}/.agents/skills/validlink"
agent_skill_is_installed validlink && ok "valid symlink" || bad "valid symlink"

echo "=== install exit nonzero but skill exists ==="
cat >"${TMP}/bin/npx" <<'EOF'
#!/usr/bin/env bash
name="skill-security-review"
dest="${HOME}/.hermes/skills/${name}"
mkdir -p "${dest}"
echo '# Skill' >"${dest}/SKILL.md"
exit 1
EOF
chmod +x "${TMP}/bin/npx"
rm -rf "${HOME}/.agents/skills/skill-security-review" "${HOME}/.hermes/skills/skill-security-review"
DOTS_WITH_COMPONENTS=(hermes skills)
install_skill_from_source "skill-security-review" "dkleptsov/skill-security-review" "security" \
	>"${TMP}/out3" 2>&1 && ok "nonzero CLI + valid skill PASS" || bad "should pass on filesystem"

echo "=== install exit 0 but no skill ==="
cat >"${TMP}/bin/npx" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TMP}/bin/npx"
rm -rf "${HOME}/.hermes/skills/skill-security-review" "${HOME}/.agents/skills/skill-security-review"
if install_skill_from_source "skill-security-review" "dkleptsov/skill-security-review" "security" \
	>"${TMP}/out4" 2>&1; then
	bad "should fail when no skill on disk"
else
	ok "zero CLI + missing skill FAIL"
fi

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
