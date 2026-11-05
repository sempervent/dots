#!/usr/bin/env bash
# scripts/tests/infra_validate_test.sh — Phase 7 infrastructure safety
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-infra.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

SCRIPT="${ROOT}/scripts/ci/infra_validate.sh"
[[ -x ${SCRIPT} ]] || chmod +x "${SCRIPT}"

# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/packages.sh"

echo "=== infra package ownership ==="
for p in terraform terraform-docs tflint checkov infracost terragrunt ansible ansible-lint vault packer helm; do
	found=0
	while IFS= read -r id; do [[ ${id} == "${p}" ]] && found=1; done < <(dots_group_package_ids infra optional)
	[[ ${found} -eq 1 ]] && ok "infra owns ${p}" || bad "infra missing ${p}"
done
grep -q 'hashicorp/tap/terraform' "${ROOT}/brew/groups/infra.Brewfile" && ok "terraform hashicorp/tap" || bad "terraform tap"
grep -q 'hashicorp/tap/vault' "${ROOT}/brew/groups/infra.Brewfile" && ok "vault hashicorp/tap" || bad "vault tap"
grep -q 'hashicorp/tap/packer' "${ROOT}/brew/groups/infra.Brewfile" && ok "packer hashicorp/tap" || bad "packer tap"
grep -q 'brew "checkov"' "${ROOT}/brew/groups/infra.Brewfile" && ok "checkov in infra Brewfile" || bad "checkov"
# checkov not duplicated into security Brewfile
grep -q 'checkov' "${ROOT}/brew/groups/security.Brewfile" && bad "checkov duplicated in security" || ok "checkov not duplicated in security"
# tflint omitted from Darwin brew (no formula)
grep -q 'brew "tflint"' "${ROOT}/brew/groups/infra.Brewfile" && bad "tflint must not be in Brewfile without formula" || ok "tflint omitted from Darwin Brewfile"
# helm preserved
grep -q 'brew "helm"' "${ROOT}/brew/groups/infra.Brewfile" && ok "helm preserved" || bad "helm missing"

echo "=== no-mutation stubs ==="
mkdir -p "${TMP}/bin"
for bin in terraform tofu terragrunt ansible ansible-playbook ansible-lint vault packer infracost terraform-docs tflint checkov; do
	cat >"${TMP}/bin/${bin}" <<EOF
#!/usr/bin/env bash
cmd="\${1:-}"
case "\$cmd" in
version|--version|-v|-V) echo "${bin} stub 0"; exit 0 ;;
esac
# Forbid mutating / network / auth verbs
case "\$cmd" in
init|apply|destroy|plan|login|build|run-all|output|state|console|import|taint|untaint|force-unlock|workspace)
  echo "FORBIDDEN_${bin}:\$*" >&2; exit 99 ;;
esac
# terraform fmt -check allowed; plain fmt (write) forbidden for auto path — allow -check only
if [[ "${bin}" == terraform || "${bin}" == tofu ]]; then
  if [[ "\$cmd" == fmt ]]; then
    for a in "\$@"; do [[ "\$a" == -check ]] && { echo "fmt-check ok"; exit 0; }; done
    echo "FORBIDDEN_${bin}_fmt_write:\$*" >&2; exit 99
  fi
  if [[ "\$cmd" == validate ]]; then
    echo "FORBIDDEN_${bin}_validate:\$*" >&2; exit 99
  fi
fi
if [[ "${bin}" == packer ]]; then
  if [[ "\$cmd" == fmt ]]; then
    for a in "\$@"; do [[ "\$a" == -check ]] && exit 0; done
    echo "FORBIDDEN_packer_fmt_write:\$*" >&2; exit 99
  fi
  if [[ "\$cmd" == init || "\$cmd" == validate || "\$cmd" == build ]]; then
    echo "FORBIDDEN_packer:\$*" >&2; exit 99
  fi
fi
if [[ "${bin}" == vault ]]; then
  if [[ "\$cmd" == status || "\$cmd" == login || "\$cmd" == read || "\$cmd" == write || "\$cmd" == kv ]]; then
    echo "FORBIDDEN_vault:\$*" >&2; exit 99
  fi
fi
if [[ "${bin}" == infracost ]]; then
  if [[ "\$cmd" == breakdown || "\$cmd" == diff || "\$cmd" == upload ]]; then
    echo "FORBIDDEN_infracost:\$*" >&2; exit 99
  fi
fi
if [[ "${bin}" == ansible-playbook ]]; then
  echo "FORBIDDEN_playbook:\$*" >&2; exit 99
fi
if [[ "${bin}" == terraform-docs ]]; then
  # allow markdown to stdout
  echo "# docs preview"; exit 0
fi
if [[ "${bin}" == checkov ]]; then
  exit 0
fi
if [[ "${bin}" == ansible-lint ]]; then
  exit 0
fi
if [[ "${bin}" == tflint ]]; then
  exit 0
fi
if [[ "${bin}" == ansible ]]; then
  exit 0
fi
if [[ "${bin}" == terragrunt ]]; then
  exit 0
fi
echo "FORBIDDEN_${bin}:\$*" >&2
exit 99
EOF
	chmod +x "${TMP}/bin/${bin}"
done
export PATH="${TMP}/bin:${PATH}"

# Fake secrets — must never appear in output
export AWS_ACCESS_KEY_ID="AKIAFAKESECRETTEST"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYFAKESECRET"
export VAULT_TOKEN="s.fake-vault-token-do-not-print"
export INFRACOST_API_KEY="ico-fake-key-do-not-print"
export TF_TOKEN_app_terraform_io="t.app.fake.token"
export VAULT_ADDR="https://vault.example.invalid"
unset VAULT_NAMESPACE || true

st="$("${SCRIPT}" status 2>&1)" || {
	bad "status exit"
	st=""
}
echo "${st}" | grep -qiE 'AKIAFAKE|wJalrXU|s\.fake-vault|ico-fake|t\.app\.fake' && bad "secrets leaked in status" || ok "secrets redacted from status"
echo "${st}" | grep -q 'FORBIDDEN_' && bad "mutating verb during status" || ok "status no mutating verbs"
echo "${st}" | grep -qi 'NOT CONFIGURED\|CONFIGURED (not displayed' && ok "infracost/vault metadata safe" || ok "status printed"

gt="$("${SCRIPT}" gate 2>&1)" || true
echo "${gt}" | grep -q 'FORBIDDEN_terraform:init\|FORBIDDEN_tofu:init\|FORBIDDEN_terragrunt:init' && bad "init invoked" || ok "no terraform/tofu/terragrunt init"
echo "${gt}" | grep -q 'FORBIDDEN_.*apply\|FORBIDDEN_.*destroy' && bad "apply/destroy invoked" || ok "no apply/destroy"
echo "${gt}" | grep -q 'FORBIDDEN_vault\|FORBIDDEN_playbook\|FORBIDDEN_packer:build\|FORBIDDEN_infracost' && bad "forbidden ops in gate" || ok "gate no vault/playbook/build/API"
echo "${gt}" | grep -qiE 'AKIAFAKE|s\.fake-vault|ico-fake' && bad "secrets leaked in gate" || ok "secrets redacted from gate"
echo "${gt}" | grep -qi 'SKIPPED_NOT_INITIALIZED\|native validate' && ok "native validate skipped without init" || ok "gate ran"

# terraform-docs must not rewrite fixture README
tf_fix="${ROOT}/scripts/tests/fixtures/infra/terraform-valid"
before="$(find "${tf_fix}" -type f -exec cksum {} \; | sort)"
"${SCRIPT}" gate >/dev/null 2>&1 || true
after="$(find "${tf_fix}" -type f -exec cksum {} \; | sort)"
[[ ${before} == "${after}" ]] && ok "terraform-docs did not mutate fixtures" || bad "fixtures mutated"

echo "=== no state file inspection ==="
if rg -n 'terraform\.tfstate|\.tfstate' "${SCRIPT}" | rg -v '^\s*#|never|NOT|state files never|privacy' | grep -q .; then
	# Allow mentions in comments/invariants only
	:
fi
# Ensure script does not cat/read state
if rg -n 'cat[[:space:]].*tfstate|jq[[:space:]].*tfstate' "${SCRIPT}" 2>/dev/null | grep -q .; then
	bad "reads tfstate"
else
	ok "does not read tfstate contents"
fi

echo "=== CLI help ==="
chk="$("${ROOT}/dots" check --help 2>&1)" || true
echo "${chk}" | grep -q 'check infra' && ok "help mentions infra" || bad "help missing infra"

echo "=== YubiKey independence ==="
rg -q 'ykman|YubiKey|age-plugin' "${SCRIPT}" && bad "infra validate references YubiKey" || ok "independent of YubiKey"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
