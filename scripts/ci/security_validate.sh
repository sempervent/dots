#!/usr/bin/env bash
# scripts/ci/security_validate.sh — local supply-chain / secrets validation
#
# Read-only wrt user trust: never provisions YubiKeys, age identities, SOPS
# configs, CAs, osqueryd, Secretive, or Cosign signing keys.
#
# Usage:
#   ./scripts/ci/security_validate.sh              # repository security gate
#   ./scripts/ci/security_validate.sh status        # host capabilities
#   ./scripts/ci/security_validate.sh sbom          # Syft → Grype
#   ./scripts/ci/security_validate.sh verify ARG…   # cosign verify passthrough
#   ./scripts/ci/security_validate.sh secrets       # gitleaks only
#   ./scripts/ci/security_validate.sh deep-secrets  # gitleaks --log-opts full
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

MODE="${1:-gate}"
shift || true

ART_DIR="${DOTS_SECURITY_ARTIFACTS:-${ROOT}/artifacts/security}"
mkdir -p "${ART_DIR}" 2>/dev/null || true

usage() {
	cat <<'EOF'
Usage: ./scripts/ci/security_validate.sh [mode] [args]

Modes:
  (default)|gate   Repository security gate (secrets/source/deps/repo/SBOM)
  status           Host capabilities (SOPS/age/YubiKey/osquery/step/cosign)
  secrets          gitleaks on working tree
  deep-secrets     gitleaks including git history
  sbom             Generate CycloneDX SBOM (Syft) and scan with Grype
  verify …         cosign verify … (no key generation; args required)

Requires package group `security` (e.g. ./setup.sh --profile work).
Does not install tools, mutate YubiKeys, generate identities, or sign releases.
EOF
}

missing_tools_hint() {
	echo "" >&2
	echo "Missing security validation tools." >&2
	echo "Select package group 'security', for example:" >&2
	echo "  ./setup.sh --profile work" >&2
	echo "  ./setup.sh --packages core,modern,security" >&2
	echo "" >&2
}

have() { command -v "$1" >/dev/null 2>&1; }

require_cmd() {
	local bin="$1"
	if ! have "${bin}"; then
		echo "${RED}✗${NC} missing required tool: ${bin}" >&2
		missing_tools_hint
		return 1
	fi
}

pass() { echo "${GREEN}PASS${NC} $1"; }
fail() {
	echo "${RED}FAIL${NC} $1"
	return 1
}
skip() { echo "${YELLOW}SKIP${NC} $1"; }
ok_cap() { echo "${GREEN}OK${NC}    $1"; }
info_cap() { echo "      $1"; }

run_step() {
	local name="$1"
	shift
	echo "${BLUE}=== ${name} ===${NC}"
	if "$@"; then
		pass "${name}"
		return 0
	fi
	fail "${name}"
}

# ── Host capability status (informational; does not fail the gate) ──────────

tool_version() {
	local bin="$1"
	shift
	if ! have "${bin}"; then
		echo "missing"
		return
	fi
	# Best-effort version; never dump secrets. Prefer a GitVersion/version line over banners.
	local out
	out="$("${bin}" "$@" 2>&1 || true)"
	if echo "${out}" | grep -Eiq 'GitVersion:|version[: ]'; then
		echo "${out}" | grep -Ei 'GitVersion:|version[: ]' | head -n 1 | tr -d '\r' | sed 's/^[[:space:]]*//'
		return
	fi
	echo "${out}" | grep -Ev '^[[:space:]]*$|^[ /\\|_.]+$' | head -n 1 | tr -d '\r' || echo "present"
}

age_identity_state() {
	# Metadata only — never print key material.
	if [[ -n ${AGE_IDENTITY_FILE:-} && -f ${AGE_IDENTITY_FILE} ]]; then
		echo "configured (AGE_IDENTITY_FILE)"
		return
	fi
	if [[ -f ${HOME}/.config/age/keys.txt ]]; then
		echo "configured (~/.config/age/keys.txt present)"
		return
	fi
	if [[ -f ${HOME}/Library/Application\ Support/age/keys.txt ]]; then
		echo "configured (Application Support age keys present)"
		return
	fi
	echo "not configured"
}

sops_config_state() {
	if [[ -f ${ROOT}/.sops.yaml || -f ${ROOT}/.sops.yml ]]; then
		echo "FOUND (.sops.yaml/.yml in repo)"
	else
		echo "NOT FOUND"
	fi
}

yubikey_connected() {
	have ykman || {
		echo "n/a"
		return
	}
	# Non-mutating list; exit nonzero when no device.
	if ykman list 2>/dev/null | grep -q .; then
		echo "YES"
	else
		echo "NO"
	fi
}

run_status() {
	echo "${BLUE}Security host capabilities${NC}"
	echo "────────────────────────────────────────"
	printf '  %-24s %s\n' "sops" "$(tool_version sops --version)"
	printf '  %-24s %s\n' "age" "$(tool_version age --version)"
	printf '  %-24s %s\n' "age-plugin-yubikey" "$(have age-plugin-yubikey && echo present || echo missing)"
	printf '  %-24s %s\n' "SOPS config (repo)" "$(sops_config_state)"
	printf '  %-24s %s\n' "age identity" "$(age_identity_state)"
	printf '  %-24s %s\n' "ykman" "$(tool_version ykman --version)"
	printf '  %-24s %s\n' "YubiKey connected" "$(yubikey_connected)"
	printf '  %-24s %s\n' "osqueryi" "$(have osqueryi && echo present || echo missing)"
	printf '  %-24s %s\n' "step" "$(tool_version step version)"
	printf '  %-24s %s\n' "cosign" "$(tool_version cosign version)"
	printf '  %-24s %s\n' "gitleaks" "$(tool_version gitleaks version)"
	printf '  %-24s %s\n' "semgrep" "$(have semgrep && echo present || echo missing)"
	printf '  %-24s %s\n' "osv-scanner" "$(have osv-scanner && echo present || echo missing)"
	printf '  %-24s %s\n' "trivy" "$(have trivy && echo present || echo missing)"
	printf '  %-24s %s\n' "syft" "$(have syft && echo present || echo missing)"
	printf '  %-24s %s\n' "grype" "$(have grype && echo present || echo missing)"
	echo ""
	echo "No keys generated. No YubiKey slots modified. No CA bootstrap."
	return 0
}

run_osquery_inventory() {
	if ! have osqueryi; then
		skip "osqueryi (not installed — optional)"
		return 0
	fi
	local q="${ROOT}/configs/security/osquery/inventory.sql"
	[[ -f ${q} ]] || {
		skip "osquery inventory query missing"
		return 0
	}
	# Interactive CLI only — never start osqueryd.
	osqueryi --json <"${q}" >/dev/null
}

# ── Scanners ───────────────────────────────────────────────────────────────

run_gitleaks() {
	require_cmd gitleaks
	local deep=0
	[[ ${1:-} == --deep ]] && deep=1
	local args=(detect --source "${ROOT}" --no-banner --redact -c "${ROOT}/.gitleaks.toml")
	if [[ ${deep} -eq 1 ]]; then
		# Full history — slower; explicit deep mode only.
		gitleaks "${args[@]}"
	else
		# Working tree / unstaged + staged content without full history walk.
		gitleaks "${args[@]}" --no-git
	fi
}

run_semgrep() {
	require_cmd semgrep
	# Local rules only — never --config auto (network + may phone home).
	local cfg="${ROOT}/configs/security/semgrep.yml"
	if [[ ! -f ${cfg} ]]; then
		skip "semgrep (no configs/security/semgrep.yml)"
		return 0
	fi
	# --metrics=off: privacy invariant
	semgrep scan --metrics=off --quiet --error --config "${cfg}" "${ROOT}" \
		--exclude='site' --exclude='.tools' --exclude='artifacts' \
		--exclude='generated' --exclude='**/node_modules' \
		--exclude='scripts/tests/fixtures'
}

run_osv() {
	require_cmd osv-scanner
	# Scans lockfiles/manifests; may need network for OSV DB.
	if [[ ${DOTS_SECURITY_OFFLINE:-0} == 1 ]]; then
		skip "osv-scanner (DOTS_SECURITY_OFFLINE=1)"
		return 0
	fi
	# Exit nonzero when vulnerabilities are found. Exclude synthetic fixtures.
	osv-scanner scan -r "${ROOT}" \
		--verbosity error \
		--x-exclude scripts/tests/fixtures \
		--x-exclude site \
		--x-exclude .tools \
		--x-exclude artifacts
}

run_trivy() {
	require_cmd trivy
	if [[ ${DOTS_SECURITY_OFFLINE:-0} == 1 ]]; then
		# Offline only if DB already cached.
		trivy fs --scanners vuln,misconfig,secret \
			--severity HIGH,CRITICAL \
			--exit-code 1 \
			--offline-scan \
			--skip-dirs site,.tools,artifacts,generated,scripts/tests/fixtures \
			"${ROOT}" || return $?
		return 0
	fi
	trivy fs --scanners vuln,misconfig,secret \
		--severity HIGH,CRITICAL \
		--exit-code 1 \
		--skip-dirs site,.tools,artifacts,generated,scripts/tests/fixtures \
		"${ROOT}"
}

run_sbom() {
	require_cmd syft
	require_cmd grype
	local out="${ART_DIR}/sbom.cdx.json"
	mkdir -p "${ART_DIR}"
	echo "Generating CycloneDX SBOM → ${out}" >&2
	# Exclude generated/vendor and nested tool sandboxes (scanned separately by osv/trivy).
	syft dir:"${ROOT}" \
		-o cyclonedx-json="${out}" \
		--exclude './site/**' \
		--exclude './.tools/**' \
		--exclude './artifacts/**' \
		--exclude './.git/**' \
		--exclude '**/node_modules/**' \
		--exclude './tools/**' \
		--exclude './scripts/tests/fixtures/**'
	echo "Scanning SBOM with Grype (fail on HIGH+)" >&2
	if [[ ${DOTS_SECURITY_OFFLINE:-0} == 1 ]]; then
		grype "sbom:${out}" --fail-on high --only-fixed=false || {
			local rc=$?
			# Distinguish missing DB if possible
			if [[ ${rc} -ne 0 ]]; then
				echo "Grype failed (offline mode). Ensure vulnerability DB is cached." >&2
			fi
			return "${rc}"
		}
		return 0
	fi
	grype "sbom:${out}" --fail-on high
}

run_cosign_verify() {
	require_cmd cosign
	if [[ $# -lt 1 ]]; then
		echo "Usage: ./dots check security verify <cosign-verify-args…>" >&2
		echo "Example: ./dots check security verify --key cosign.pub artifact.tar" >&2
		echo "Phase 2: verification only — signing keys are NOT generated." >&2
		return 1
	fi
	# Never log tokens; pass args through.
	cosign verify "$@"
}

run_gate() {
	local rc=0
	echo "${BLUE}Security Validation${NC}"
	echo "────────────────────────────────────────"
	echo ""
	echo "Secrets"
	run_step "gitleaks" run_gitleaks || rc=1
	echo ""
	echo "Source"
	run_step "semgrep" run_semgrep || rc=1
	echo ""
	echo "Dependencies"
	run_step "osv-scanner" run_osv || rc=1
	echo ""
	echo "Repository"
	run_step "trivy" run_trivy || rc=1
	echo ""
	echo "SBOM"
	run_step "syft+grype" run_sbom || rc=1
	echo ""
	echo "Host capabilities (informational)"
	run_status || true
	run_step "osquery-inventory" run_osquery_inventory || true
	echo ""
	echo "Cosign: installed for verification; release signing NOT ACTIVE in Phase 2."
	return "${rc}"
}

case "${MODE}" in
"" | -h | --help)
	usage
	exit 0
	;;
gate | security)
	run_gate
	exit $?
	;;
status)
	run_status
	exit $?
	;;
secrets)
	run_step "gitleaks" run_gitleaks
	exit $?
	;;
deep-secrets)
	run_step "gitleaks-deep" run_gitleaks --deep
	exit $?
	;;
sbom)
	run_step "syft+grype" run_sbom
	exit $?
	;;
verify)
	run_cosign_verify "$@"
	exit $?
	;;
*)
	echo "Unknown mode: ${MODE}" >&2
	usage >&2
	exit 1
	;;
esac
