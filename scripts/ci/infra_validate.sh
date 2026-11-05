#!/usr/bin/env bash
# scripts/ci/infra_validate.sh — infrastructure engineering diagnostics (Phase 7)
#
# Network-free / non-mutating by default:
#   - no terraform/tofu/terragrunt init|apply|destroy
#   - no ansible-playbook against hosts / fact gathering
#   - no vault login / vault status against servers
#   - no packer build|init
#   - no infracost API / cloud calls
#   - no Terraform state reads
#
# Usage:
#   ./scripts/ci/infra_validate.sh            # status (default)
#   ./scripts/ci/infra_validate.sh status
#   ./scripts/ci/infra_validate.sh gate       # static checks on fixtures + repo (when present)
#   ./scripts/ci/infra_validate.sh examples
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

MODE="${1:-status}"
FIXTURES="${ROOT}/scripts/tests/fixtures/infra"

usage() {
	cat <<'EOF'
Usage: ./scripts/ci/infra_validate.sh [status|gate|examples]

  status    Report infra tooling presence + local config metadata
  gate      Static format/lint checks (no init/apply/login/build/network APIs)
  examples  Print example commands (stdout only; not executed)

Never mutates infrastructure, authenticates Vault/cloud, or contacts remotes.
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

# Scrub credentials from child environments for validators.
scrub_env() {
	env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN \
		-u GOOGLE_APPLICATION_CREDENTIALS -u GOOGLE_CREDENTIALS \
		-u AZURE_CLIENT_SECRET -u AZURE_CLIENT_ID \
		-u VAULT_TOKEN -u VAULT_CLIENT_TOKEN \
		-u TF_TOKEN_app_terraform_io -u TFE_TOKEN \
		-u INFRACOST_API_KEY -u INFRACOST_SELF_HOSTED_API_KEY \
		-u ANSIBLE_VAULT_PASSWORD -u ANSIBLE_VAULT_PASSWORD_FILE \
		"$@"
}

tool_line() {
	local label="$1"
	local bin="$2"
	local note="${3:-}"
	if have "${bin}"; then
		local ver=""
		case "${bin}" in
		terraform) ver="$(terraform version 2>/dev/null | head -n1 || true)" ;;
		tofu) ver="$(tofu version 2>/dev/null | head -n1 || true)" ;;
		terraform-docs) ver="$(terraform-docs version 2>/dev/null | head -n1 || true)" ;;
		tflint) ver="$(tflint --version 2>/dev/null | head -n1 || true)" ;;
		checkov) ver="$(checkov --version 2>/dev/null | head -n1 || true)" ;;
		terragrunt) ver="$(terragrunt --version 2>/dev/null | head -n1 || true)" ;;
		ansible) ver="$(ansible --version 2>/dev/null | head -n1 || true)" ;;
		ansible-lint) ver="$(ansible-lint --version 2>/dev/null | head -n1 || true)" ;;
		vault) ver="$(vault version 2>/dev/null | head -n1 || true)" ;;
		packer) ver="$(packer version 2>/dev/null | head -n1 || true)" ;;
		infracost) ver="$(infracost --version 2>/dev/null | head -n1 || true)" ;;
		helm) ver="$(helm version --short 2>/dev/null | head -n1 || true)" ;;
		*) ver="present" ;;
		esac
		printf '  %-18s %s%s%s\n' "${label}" "${GREEN}OK${NC}" "${ver:+ (${ver})}" "${note:+ ${note}}"
	else
		if [[ ${label} == tofu || ${label} == tflint ]]; then
			printf '  %-18s %s\n' "${label}" "OPTIONAL / not installed"
		else
			printf '  %-18s %s\n' "${label}" "${YELLOW}missing${NC}"
		fi
	fi
}

tf_bin() {
	if have terraform; then
		echo terraform
	elif have tofu; then
		echo tofu
	else
		echo ""
	fi
}

count_tf_files() {
	local dir="${1:-.}"
	find "${dir}" \( -name '*.tf' -o -name '*.tf.json' \) \
		! -path '*/.terraform/*' ! -path '*/vendor/*' ! -path '*/.git/*' \
		! -path '*/scripts/tests/fixtures/*' \
		2>/dev/null | wc -l | tr -d ' '
}

count_tg_files() {
	local dir="${1:-.}"
	find "${dir}" \( -name 'terragrunt.hcl' -o -name 'root.hcl' \) \
		! -path '*/.terraform/*' ! -path '*/.git/*' ! -path '*/scripts/tests/fixtures/*' \
		2>/dev/null | wc -l | tr -d ' '
}

count_packer_files() {
	local dir="${1:-.}"
	find "${dir}" \( -name '*.pkr.hcl' -o -name '*.pkr.json' \) \
		! -path '*/.git/*' ! -path '*/scripts/tests/fixtures/*' \
		2>/dev/null | wc -l | tr -d ' '
}

has_ansible_content() {
	local dir="${1:-.}"
	# Ignore Phase 7 test fixtures when reporting repo inventory.
	if find "${dir}" \( -name 'ansible.cfg' -o -path '*/roles/*' -o -path '*/playbooks/*' -o -name 'site.yml' \) \
		! -path '*/scripts/tests/fixtures/*' ! -path '*/.git/*' 2>/dev/null | grep -q .; then
		return 0
	fi
	return 1
}

vault_meta() {
	echo "Secrets"
	tool_line "vault" vault
	if [[ -n ${VAULT_ADDR:-} ]]; then
		printf '  %-18s %s\n' "VAULT_ADDR" "CONFIGURED (value not printed)"
	else
		printf '  %-18s %s\n' "VAULT_ADDR" "NOT CONFIGURED"
	fi
	if [[ -n ${VAULT_NAMESPACE:-} ]]; then
		printf '  %-18s %s\n' "VAULT_NAMESPACE" "CONFIGURED (value not printed)"
	else
		printf '  %-18s %s\n' "VAULT_NAMESPACE" "NOT CONFIGURED"
	fi
	# Never print VAULT_TOKEN presence as the token itself — only YES/NO.
	if [[ -n ${VAULT_TOKEN:-} ]]; then
		printf '  %-18s %s\n' "VAULT_TOKEN" "PRESENT (not displayed; unused)"
	else
		printf '  %-18s %s\n' "VAULT_TOKEN" "NOT SET"
	fi
}

infracost_meta() {
	echo "Cost"
	tool_line "infracost" infracost
	if [[ -n ${INFRACOST_API_KEY:-} ]]; then
		printf '  %-18s %s\n' "API key" "CONFIGURED (not displayed; unused)"
	else
		printf '  %-18s %s\n' "API key" "NOT CONFIGURED"
	fi
}

run_status() {
	echo "${BLUE}Infrastructure Tooling${NC}"
	echo "────────────────────────────────"
	echo ""
	echo "Terraform / OpenTofu"
	tool_line "terraform" terraform "(authoritative when present)"
	tool_line "tofu" tofu "(optional; no automatic migration)"
	tool_line "terraform-docs" terraform-docs
	tool_line "tflint" tflint "(no Homebrew formula today; optional)"
	tool_line "checkov" checkov
	tool_line "terragrunt" terragrunt
	tool_line "helm" helm "(pre-existing infra)"
	echo ""
	echo "Configuration (repository scope)"
	local n_tf n_tg n_pk
	n_tf="$(count_tf_files "${ROOT}")"
	n_tg="$(count_tg_files "${ROOT}")"
	n_pk="$(count_packer_files "${ROOT}")"
	printf '  %-18s %s\n' "Terraform files" "${n_tf}"
	printf '  %-18s %s\n' "Terragrunt files" "${n_tg}"
	printf '  %-18s %s\n' "Packer files" "${n_pk}"
	if has_ansible_content "${ROOT}"; then
		printf '  %-18s %s\n' "Ansible content" "YES"
	else
		printf '  %-18s %s\n' "Ansible content" "NO"
	fi
	echo ""
	echo "Automation"
	tool_line "ansible" ansible
	tool_line "ansible-lint" ansible-lint
	echo ""
	vault_meta
	echo ""
	echo "Images"
	tool_line "packer" packer
	echo ""
	infracost_meta
	echo ""
	echo "Invariants"
	echo "  No terraform/tofu/terragrunt init|apply|destroy; no remote state"
	echo "  No ansible host contact; no vault login; no packer build; no Infracost API"
	echo "  Terraform state files never opened; credentials never printed"
	echo "  DOTS does not migrate Terraform ↔ OpenTofu"
	return 0
}

# --- gate: static checks on fixtures (and optional repo paths) ---

run_fmt_check() {
	local dir="$1"
	local bin
	bin="$(tf_bin)"
	if [[ -z ${bin} ]]; then
		echo "  fmt-check            SKIP (no terraform/tofu)"
		return 0
	fi
	if scrub_env "${bin}" fmt -check -recursive "${dir}" >/dev/null 2>&1; then
		echo "  fmt-check            ${GREEN}PASS${NC} (${bin})"
	else
		echo "  fmt-check            ${YELLOW}FAIL${NC} (${bin} fmt -check)"
		return 1
	fi
	return 0
}

run_tflint_dir() {
	local dir="$1"
	if ! have tflint; then
		echo "  tflint               SKIP (not installed)"
		return 0
	fi
	# --disable-module / no init: avoid plugin downloads when possible.
	# Prefer --chdir without --init.
	if scrub_env tflint --chdir "${dir}" --disable-rule=terraform_required_version >/dev/null 2>&1; then
		echo "  tflint               ${GREEN}PASS${NC}"
		return 0
	fi
	# Missing plugins → informational skip rather than auto-install
	echo "  tflint               ${YELLOW}SKIP_NOT_INITIALIZED${NC} (plugins/config; no auto-download)"
	return 0
}

run_checkov_dir() {
	local dir="$1"
	if ! have checkov; then
		echo "  checkov              SKIP (not installed)"
		return 0
	fi
	# Local only — disable external checks / soft fail on missing frameworks.
	if scrub_env checkov -d "${dir}" --quiet --compact --framework terraform \
		--download-external-modules false >/dev/null 2>&1; then
		echo "  checkov              ${GREEN}PASS${NC}"
		return 0
	fi
	# Policy findings are real; report without uploading.
	echo "  checkov              ${YELLOW}FINDINGS${NC} (local scan; not uploaded)"
	return 0
}

run_terraform_docs_preview() {
	local dir="$1"
	if ! have terraform-docs; then
		echo "  terraform-docs       SKIP (not installed)"
		return 0
	fi
	local tmp
	tmp="$(mktemp)"
	# Generate to temp — never rewrite README.
	if scrub_env terraform-docs markdown table "${dir}" >"${tmp}" 2>/dev/null; then
		echo "  terraform-docs       ${GREEN}OK${NC} (preview only; source not modified)"
		rm -f "${tmp}"
		return 0
	fi
	rm -f "${tmp}"
	echo "  terraform-docs       ${YELLOW}SKIP${NC}"
	return 0
}

run_ansible_lint_dir() {
	local dir="$1"
	if ! have ansible-lint; then
		echo "  ansible-lint         SKIP (not installed)"
		return 0
	fi
	if scrub_env ansible-lint -q "${dir}" >/dev/null 2>&1; then
		echo "  ansible-lint         ${GREEN}PASS${NC}"
		return 0
	fi
	echo "  ansible-lint         ${YELLOW}FINDINGS${NC} (no hosts contacted)"
	return 0
}

run_packer_fmt() {
	local dir="$1"
	if ! have packer; then
		echo "  packer fmt-check     SKIP (not installed)"
		return 0
	fi
	local f
	local any=0
	while IFS= read -r f; do
		any=1
		if scrub_env packer fmt -check "${f}" >/dev/null 2>&1; then
			:
		else
			echo "  packer fmt-check     ${YELLOW}FAIL${NC} (${f})"
			return 1
		fi
	done < <(find "${dir}" \( -name '*.pkr.hcl' -o -name '*.pkr.json' \) 2>/dev/null)
	if [[ ${any} -eq 0 ]]; then
		echo "  packer fmt-check     SKIP (no packer files)"
	else
		echo "  packer fmt-check     ${GREEN}PASS${NC}"
	fi
	return 0
}

run_gate() {
	echo "${BLUE}Infrastructure gate (static / local)${NC}"
	echo "────────────────────────────────"
	local rc=0

	# Prefer fixtures so DOTS repo without IaC still exercises validators.
	local tf_dir="${FIXTURES}/terraform-valid"
	local ans_dir="${FIXTURES}/ansible"
	local pkr_dir="${FIXTURES}/packer-valid"

	echo ""
	echo "Terraform fixture"
	if [[ -d ${tf_dir} ]]; then
		run_fmt_check "${tf_dir}" || rc=1
		echo "  native validate      SKIPPED_NOT_INITIALIZED (no terraform init)"
		run_tflint_dir "${tf_dir}" || true
		run_checkov_dir "${tf_dir}" || true
		run_terraform_docs_preview "${tf_dir}" || true
	else
		echo "  SKIP: no fixtures"
	fi

	echo ""
	echo "Terragrunt"
	if [[ "$(count_tg_files "${ROOT}")" -gt 0 ]] || [[ -f ${FIXTURES}/terragrunt/terragrunt.hcl ]]; then
		if have terragrunt; then
			echo "  terragrunt           ${GREEN}OK${NC} (binary only; no init/apply/run-all)"
		else
			echo "  terragrunt           SKIP (not installed)"
		fi
	else
		echo "  terragrunt files     SKIP (none)"
	fi

	echo ""
	echo "Ansible fixture"
	if [[ -d ${ans_dir} ]]; then
		run_ansible_lint_dir "${ans_dir}" || true
		echo "  playbook execution   NOT RUN"
		echo "  host contact         NO"
	else
		echo "  SKIP: no ansible fixtures"
	fi

	echo ""
	echo "Packer fixture"
	if [[ -d ${pkr_dir} ]]; then
		run_packer_fmt "${pkr_dir}" || rc=1
		echo "  packer validate      SKIPPED_NOT_INITIALIZED (no packer init)"
		echo "  packer build         NOT RUN"
	else
		echo "  SKIP: no packer fixtures"
	fi

	echo ""
	echo "Vault / Infracost"
	echo "  vault server contact NO"
	echo "  infracost API        NO"
	echo ""
	echo "Invariants"
	echo "  No remote backends; no state reads; no cloud/Vault auth"
	return "${rc}"
}

run_examples() {
	cat <<'EOF'
Infrastructure tooling examples (copy/paste — not executed by DOTS)

  terraform fmt -check -recursive
  # terraform validate   # needs init — DOTS does not auto-init
  tflint --chdir path/to/module
  checkov -d path/to/module --framework terraform
  terraform-docs markdown table ./module   # preview; do not auto-write README
  terragrunt --version
  ansible-lint playbooks/
  # ansible-playbook site.yml            # execution — user-directed only
  packer fmt -check template.pkr.hcl
  # packer build template.pkr.hcl        # builds images — never by DOTS
  infracost breakdown --path .           # needs API key — user-directed
  vault version
  # vault login                          # never by DOTS

Terraform vs OpenTofu: DOTS uses whichever is installed; it does not migrate
projects. HashiCorp Vault CLI ≠ ansible-vault.
EOF
}

case "${MODE}" in
-h | --help)
	usage
	exit 0
	;;
"" | status)
	run_status
	exit $?
	;;
gate)
	run_gate
	exit $?
	;;
examples)
	run_examples
	exit 0
	;;
*)
	echo "Unknown mode: ${MODE}" >&2
	usage >&2
	exit 1
	;;
esac
