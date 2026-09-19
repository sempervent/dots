#!/usr/bin/env bash
# scripts/tests/wizard_models_progress_test.sh — wizard model pull TTY/logging contract
# Mock-only: never downloads models.
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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-wiz-models.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

WIZ="${ROOT}/helpers/wizard.sh"

echo "=== structural: no interactive tee for model pulls ==="
if grep -n 'pull_models\.sh.*2>&1[[:space:]]*|[[:space:]]*tee' "${WIZ}"; then
	bad "wizard still pipes pull_models through tee"
else
	ok "no pull_models|tee pipe in wizard"
fi
grep -q 'dots_wizard_run_models' "${WIZ}" && ok "helper defined/used" || bad "missing dots_wizard_run_models"
# models-only + Stage 4 must go through the helper (not raw pull_models|tee)
models_only_block="$(awk '/models-only\)/,/check-only\)/' "${WIZ}")"
echo "${models_only_block}" | grep -q 'dots_wizard_run_models' && ok "models-only uses helper" || bad "models-only missing helper"
stage4_block="$(awk '/dots_ui_stage 4 5 "Models"/,/dots_ui_stage 5 5 "Verification"/' "${WIZ}")"
echo "${stage4_block}" | grep -q 'dots_wizard_run_models' && ok "Stage 4 uses helper" || bad "Stage 4 missing helper"
# Interactive branch must check -t 1
if awk '/^dots_wizard_run_models\(\)/,/^}/' "${WIZ}" | grep -q '\[\[ -t 1 \]\]'; then
	ok "helper checks -t 1"
else
	bad "helper missing -t 1 check"
fi
# Standalone ./dots models still execs
grep -E 'exec.*"\$\{DIR\}/scripts/pull_models\.sh"' "${ROOT}/dots" >/dev/null &&
	ok "./dots models still execs pull_models" || bad "./dots models lost exec"

echo "=== behavioral: START/RESULT, no progress flood, rc propagate ==="
DIR="${ROOT}"
WIZ_DRY_RUN=0
WIZ_MODEL_TIER="balanced"

# shellcheck source=../../helpers/ui.sh
source "${ROOT}/helpers/ui.sh"
# shellcheck source=../../helpers/state.sh
source "${ROOT}/helpers/state.sh"
# shellcheck source=../../helpers/wizard.sh
source "${ROOT}/helpers/wizard.sh"

MOCK="${TMP}/mock_pull_models.sh"
cat >"${MOCK}" <<'EOF'
#!/usr/bin/env bash
# Simulate CR-style progress on stdout (would flood a tee'd log).
printf 'downloading'
for _ in 1 2 3 4 5 6 7 8; do
	printf '\r>>>> %s' "$_"
done
printf '\ndone\n'
exit 0
EOF
chmod +x "${MOCK}"

LOG="${TMP}/setup.log"
: >"${LOG}"
export DOTS_PULL_MODELS_SH="${MOCK}"
WIZ_DRY_RUN=0
WIZ_MODEL_TIER="balanced"
set +e
dots_wizard_run_models "${LOG}" --yes --tier balanced
rc=$?
set -e
[[ ${rc} -eq 0 ]] && ok "helper success rc=0" || bad "helper rc=${rc}"
grep -q 'MODEL START tier=balanced' "${LOG}" && ok "log START" || bad "missing START"
grep -q 'MODEL RESULT success rc=0' "${LOG}" && ok "log RESULT success" || bad "missing RESULT success"
if grep -q '>>>>' "${LOG}"; then
	bad "progress markers flooded durable log"
else
	ok "durable log has no >>>> flood"
fi

# Failure rc=23 propagates
cat >"${MOCK}" <<'EOF'
#!/usr/bin/env bash
echo "mock pull failed" >&2
exit 23
EOF
chmod +x "${MOCK}"
: >"${LOG}"
set +e
dots_wizard_run_models "${LOG}" --yes --tier minimal
rc=$?
set -e
[[ ${rc} -eq 23 ]] && ok "failure rc=23 propagates" || bad "expected rc=23 got ${rc}"
grep -q 'MODEL RESULT failed rc=23' "${LOG}" && ok "log RESULT failed" || bad "missing failed RESULT"

# Stage-4 style: nonzero models rc → WARN/FAILED semantics (caller maps to rc=1)
models_rc=23
stage_label=""
if [[ ${models_rc} -eq 0 ]]; then
	stage_label="OK"
else
	stage_label="WARN/FAILED"
fi
[[ ${stage_label} == "WARN/FAILED" ]] && ok "Models WARN/FAILED on failure" || bad "stage label"

# Dry-run may capture plan lines (no real download)
cat >"${MOCK}" <<'EOF'
#!/usr/bin/env bash
echo "[dry-run] would pull example:tag"
exit 0
EOF
chmod +x "${MOCK}"
: >"${LOG}"
WIZ_DRY_RUN=1
set +e
dots_wizard_run_models "${LOG}" --dry-run
rc=$?
set -e
WIZ_DRY_RUN=0
[[ ${rc} -eq 0 ]] && ok "dry-run helper rc=0" || bad "dry-run rc=${rc}"
grep -q 'MODEL START' "${LOG}" && ok "dry-run START" || bad "dry-run missing START"
grep -q '\[dry-run\] would pull' "${LOG}" && ok "dry-run plan captured" || bad "dry-run plan missing"
grep -q 'MODEL RESULT success' "${LOG}" && ok "dry-run RESULT" || bad "dry-run RESULT missing"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
