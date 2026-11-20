#!/usr/bin/env bash
# scripts/tests/capability_truth_test.sh — package-level installability, OpenTofu, TFLint, and registry audit
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="${ROOT}"
export DIR ROOT DOTS_DIR="${ROOT}"

unset DOTS_PROFILE DOTS_ACTIVE_COMPONENTS DOTS_PACKAGE_GROUPS DOTS_MULTIPLEXER DOTS_PROFILE_FILE || true
unset DOTS_GROUPS_REGISTRY DOTS_COMPONENTS_REGISTRY DOTS_FORCE_OS DOTS_FORCE_PKG_MGR DOTS_FORCE_DARWIN_MAJOR || true
unset DOTS_PKG_MOCK_FORMULAE DOTS_PKG_MOCK_CASKS DOTS_PKG_MOCK_EXTERNAL_BINS DOTS_PKG_MOCK_NATIVE_INSTALLED || true
unset DOTS_PKG_MOCK_HELPER_INSTALLED DOTS_PKG_DISABLE_HOST_WHICH || true

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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-cap-truth.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

export HOME="${TMP}/home"
mkdir -p "${HOME}/.config/dots/profiles"
cat >"${HOME}/.config/dots/active-profile" <<EOF
DOTS_PROFILE='base'
DOTS_PROFILE_FILE='${ROOT}/configs/bootstrap/profiles/base.toml'
DOTS_PACKAGE_GROUPS='core modern'
EOF

echo "=== 1. Darwin Brewfile, OpenTofu, TFLint, helper, external, and counts ==="
darwin_json="$(
	DOTS_FORCE_OS=darwin \
		DOTS_FORCE_PKG_MGR=brew \
		DOTS_PKG_DISABLE_HOST_WHICH=1 \
		DOTS_PKG_MOCK_FORMULAE=$'terraform\nhelm' \
		DOTS_PKG_MOCK_CASKS='' \
		DOTS_PKG_MOCK_EXTERNAL_BINS=$'tflint\nopentofu' \
		DOTS_PKG_MOCK_HELPER_INSTALLED=$'mapshaper' \
		"${ROOT}/dots" packages groups --profile base --json
)"

printf '%s\n' "${darwin_json}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["schema_version"] == 1
assert d["os"] == "darwin"
assert d["pkg_mgr"] == "brew"
by_name = {g["name"]: g for g in d["groups"]}

infra = by_name["infra"]
assert infra["platform_supported"] is True
assert infra["package_count"] == 17, infra["package_count"]
assert infra["supported_package_count"] == 16, infra["supported_package_count"]
assert infra["unsupported_package_count"] == 1, infra["unsupported_package_count"]
assert "tflint" in infra["unsupported_packages"]
# terraform (brew), tflint (external), opentofu (external) => 3 installed (helm also brew => 4)
assert infra["installed_count"] == 4, infra["installed_count"]

ipkgs = {p["name"]: p for p in infra["packages"]}

# OpenTofu: installable via brew, externally present on PATH
tofu = ipkgs["opentofu"]
assert tofu["known"] is True
assert tofu["installable"] is True
assert tofu["platform_supported"] is True
assert tofu["unsupported"] is False
assert tofu["install_method"] == "brew"
assert tofu["install_token"] == "opentofu"
assert tofu["installed"] is True
assert tofu["external"] is True
assert tofu["selected"] is False

# Terraform: brew-owned and installed
tf = ipkgs["terraform"]
assert tf["installable"] is True
assert tf["installed"] is True
assert tf["external"] is False
assert tf["install_token"] == "hashicorp/tap/terraform"

# TFLint: known + owner=infra, uninstallable on Darwin, installed externally
tl = ipkgs["tflint"]
assert tl["known"] is True
assert tl["owner"] == "group:infra"
assert tl["installable"] is False
assert tl["platform_supported"] is False
assert tl["unsupported"] is True
assert tl["install_method"] == "none"
assert tl["install_token"] is None
assert tl["installed"] is True
assert tl["external"] is True
assert tl["unsupported_reason"]

# Brewfile alias: leaf -> leaf-markdown-viewer (no duplicate entry)
modern = by_name["modern"]
mpkgs = {p["name"]: p for p in modern["packages"]}
assert "leaf" in mpkgs
assert "leaf-markdown-viewer" not in mpkgs
assert mpkgs["leaf"]["installable"] is True
assert mpkgs["leaf"]["install_token"] == "leaf-markdown-viewer"

# Helper-managed package: mapshaper in geo
geo = by_name["geo"]
gpkgs = {p["name"]: p for p in geo["packages"]}
ms = gpkgs["mapshaper"]
assert ms["installable"] is True
assert ms["install_method"] == "helper"
assert ms["install_token"] == "mapshaper"
assert ms["installed"] is True
assert ms["external"] is False
' && ok "Darwin packages groups --json truth model" || bad "Darwin packages groups --json failed"

echo "=== 2. Linux native mappings vs empty mappings ==="
apt_json="$(
	DOTS_FORCE_OS=linux \
		DOTS_FORCE_PKG_MGR=apt \
		DOTS_PKG_DISABLE_HOST_WHICH=1 \
		DOTS_PKG_MOCK_NATIVE_INSTALLED=$'bash\nansible' \
		"${ROOT}/dots" packages groups --profile base --json
)"

printf '%s\n' "${apt_json}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["os"] == "linux" and d["pkg_mgr"] == "apt"
by_name = {g["name"]: g for g in d["groups"]}

core = by_name["core"]
cpkgs = {p["name"]: p for p in core["packages"]}
assert cpkgs["fd"]["installable"] is True
assert cpkgs["fd"]["install_token"] == "fd-find"
assert cpkgs["bash"]["installed"] is True and cpkgs["bash"]["external"] is False
assert cpkgs["fnm"]["installable"] is False

infra = by_name["infra"]
ipkgs = {p["name"]: p for p in infra["packages"]}
assert ipkgs["ansible"]["installable"] is True
assert ipkgs["ansible"]["installed"] is True
# OpenTofu is empty in apt.toml (no third-party repo enrollment)
assert ipkgs["opentofu"]["installable"] is False
assert ipkgs["opentofu"]["unsupported"] is True
assert ipkgs["tflint"]["installable"] is False
assert infra["supported_package_count"] < infra["package_count"]
assert infra["platform_supported"] is True  # optional only

geo = by_name["geo"]
gpkgs = {p["name"]: p for p in geo["packages"]}
assert gpkgs["mapshaper"]["installable"] is True
assert gpkgs["mapshaper"]["install_method"] == "helper"
' && ok "Linux apt native + empty + helper mapping truth" || bad "Linux apt truth failed"

dnf_res="$(
	DOTS_FORCE_OS=linux \
		DOTS_FORCE_PKG_MGR=dnf \
		DOTS_PKG_DISABLE_HOST_WHICH=1 \
		"${ROOT}/dots" profile resolve opentofu --json
)"
printf '%s\n' "${dnf_res}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["status"] == "ok"
assert d["owner"] == "group:infra"
assert d["owner_exists"] is True
assert d["installable"] is True
assert d["package"]["install_method"] == "dnf"
assert d["package"]["install_token"] == "opentofu"
assert d["direct_install_allowed"] is True
' && ok "OpenTofu installable on dnf" || bad "OpenTofu dnf resolve failed"

echo "=== 3. profile resolve tflint vs opentofu vs taplo ==="
tflint_res="$(
	DOTS_FORCE_OS=darwin \
		DOTS_FORCE_PKG_MGR=brew \
		DOTS_PKG_DISABLE_HOST_WHICH=1 \
		"${ROOT}/dots" profile resolve tflint --json
)"
printf '%s\n' "${tflint_res}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["status"] == "ok"
assert d["owner"] == "group:infra"
assert d["owner_exists"] is True
assert d["installable"] is False
assert d["platform_supported"] is False
assert d["direct_install_allowed"] is False
assert "group:infra" in d["direct_install_error"]
assert d["group_summary"]["supported_package_count"] == 16
assert d["group_summary"]["package_count"] == 17
assert "tflint" in d["group_summary"]["unsupported_packages"]
' && ok "profile resolve tflint distinguishes owner vs installability" || bad "tflint resolve failed"

taplo_res="$(
	DOTS_FORCE_OS=darwin \
		DOTS_FORCE_PKG_MGR=brew \
		"${ROOT}/dots" profile resolve taplo --json
)"
printf '%s\n' "${taplo_res}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["status"] == "ambiguous"
assert d["owner_exists"] is True
assert set(d["choices"]) >= {"component:lsp", "group:dev"}
' && ok "profile resolve taplo reports ambiguous ownership" || bad "taplo resolve failed"

echo "=== 4. dots install refuses unsatisfiable direct package without mutating ==="
OV_FILE="${HOME}/.config/dots/profiles/base-local.toml"
rm -f "${OV_FILE}"
set +e
tflint_inst_out="$(
	DOTS_FORCE_OS=darwin \
		DOTS_FORCE_PKG_MGR=brew \
		DOTS_PKG_DISABLE_HOST_WHICH=1 \
		"${ROOT}/dots" install tflint --profile base --yes --no-apply 2>&1
)"
tflint_inst_rc=$?
set -e
[[ ${tflint_inst_rc} -ne 0 ]] && ok "dots install tflint exits non-zero" || bad "dots install tflint unexpectedly succeeded"
[[ ! -f ${OV_FILE} ]] && ok "dots install tflint persisted zero overlay changes" || bad "dots install tflint created overlay"
echo "${tflint_inst_out}" | grep -q 'group:infra' && echo "${tflint_inst_out}" | grep -qi 'no supported installer' &&
	ok "dots install tflint explains owner vs unsupported installer" || bad "tflint error output: ${tflint_inst_out}"

# Also verify apt refuses direct opentofu install without mutating
set +e
apt_tofu_out="$(
	DOTS_FORCE_OS=linux \
		DOTS_FORCE_PKG_MGR=apt \
		DOTS_PKG_DISABLE_HOST_WHICH=1 \
		"${ROOT}/dots" install opentofu --profile base --yes --no-apply 2>&1
)"
apt_tofu_rc=$?
set -e
[[ ${apt_tofu_rc} -ne 0 && ! -f ${OV_FILE} ]] && ok "dots install opentofu refused on apt without mutation" || bad "apt opentofu rc=${apt_tofu_rc}"

# Selecting group:infra remains valid even when optional tflint is unsupported
infra_inst_out="$(
	DOTS_FORCE_OS=darwin \
		DOTS_FORCE_PKG_MGR=brew \
		DOTS_PKG_DISABLE_HOST_WHICH=1 \
		"${ROOT}/dots" install infra --profile base --yes --no-apply 2>&1
)"
[[ -f ${OV_FILE} ]] && ok "dots install infra succeeds despite unsupported optional tflint" || bad "dots install infra failed"
echo "${infra_inst_out}" | grep -q '16/17 supported' && echo "${infra_inst_out}" | grep -q 'tflint' &&
	ok "dots install infra reports 16/17 supported and lists unavailable tflint" || bad "infra install out: ${infra_inst_out}"

echo "=== 5. Required unsupported package behavior ==="
syn_g="${TMP}/req-unsup-groups.toml"
cat >"${syn_g}" <<'EOF'
version = 1
[[groups]]
name = "core"
description = "Core"
required = ["bash"]
optional = []
[[groups]]
name = "broken-req"
description = "Group with unsupported required pkg"
required = ["tflint"]
optional = []
EOF

req_json="$(
	DOTS_GROUPS_REGISTRY="${syn_g}" \
		DOTS_FORCE_OS=darwin \
		DOTS_FORCE_PKG_MGR=brew \
		DOTS_PKG_DISABLE_HOST_WHICH=1 \
		"${ROOT}/dots" packages groups --profile base --json
)"
printf '%s\n' "${req_json}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
bg = next(g for g in d["groups"] if g["name"] == "broken-req")
assert bg["platform_supported"] is False
assert bg["required_unsupported"] == ["tflint"]
assert bg["supported_package_count"] == 0
assert bg["package_count"] == 1
assert "tflint" in bg["unsupported_reason"]
' && ok "group with unsupported required package reports platform_supported=false" || bad "required unsupported JSON failed"

rm -f "${OV_FILE}"
set +e
DOTS_GROUPS_REGISTRY="${syn_g}" \
	DOTS_FORCE_OS=darwin \
	DOTS_FORCE_PKG_MGR=brew \
	"${ROOT}/dots" install broken-req --profile base --yes --no-apply >/dev/null 2>&1
req_rc=$?
set -e
[[ ${req_rc} -ne 0 && ! -f ${OV_FILE} ]] && ok "dots install refuses group with unsupported required package" || bad "broken-req install should fail"

echo "=== 6. Registry integrity audit (clean repo + synthetic drift detections) ==="
audit_json="$("${ROOT}/dots" packages audit --json)"
printf '%s\n' "${audit_json}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["schema_version"] == 1
assert d["ok"] is True
assert d["summary"]["errors"] == 0
assert any(f["code"] == "package_no_install_path" and f["package"] == "tflint" and f["level"] == "WARN" for f in d["findings"])
assert any(f["level"] == "INFO" for f in d["findings"])
' && ok "real repo packages audit --json passes (0 errors, tflint WARN, INFO present)" || bad "repo audit failed"

# Synthetic broken workspace copy to exercise all audit ERROR rules offline
BROKEN_DIR="${TMP}/broken-repo"
mkdir -p "${BROKEN_DIR}/configs/packages" "${BROKEN_DIR}/configs/bootstrap/profiles" "${BROKEN_DIR}/brew/groups" "${BROKEN_DIR}/helpers"
cat >"${BROKEN_DIR}/configs/packages/groups.toml" <<'EOF'
version = 1
[[groups]]
name = "alpha"
description = "Alpha"
required = ["req-dead", "dup-pkg"]
optional = []
[[groups]]
name = "beta"
description = "Beta"
required = []
optional = ["dup-pkg"]
EOF
cat >"${BROKEN_DIR}/brew/groups/alpha.Brewfile" <<'EOF'
brew "unlisted-token"
EOF
# beta.Brewfile intentionally missing -> missing_group_brewfile
cat >"${BROKEN_DIR}/configs/components.toml" <<'EOF'
version = 1
[[components]]
id = "ghost"
label = "Ghost"
platforms = ["darwin"]
brewfile = "brew/Brewfile.missing"
EOF
for mgr in apt dnf pacman xbps; do
	cat >"${BROKEN_DIR}/configs/packages/${mgr}.toml" <<'EOF'
[packages]
req-dead = ""
dup-pkg = "dup"
orphan-map-pkg = "orphan"
EOF
done
cat >"${BROKEN_DIR}/configs/bootstrap/profiles/base.toml" <<'EOF'
[profile]
name = "base"
packages = ["alpha"]
EOF
cat >"${BROKEN_DIR}/helpers/mapshaper.sh" <<'EOF'
#!/usr/bin/env bash
npm install -g mapshaper
EOF

set +e
broken_audit="$(DOTS_DIR="${BROKEN_DIR}" "${DOTS_PYTHON:-python3}" "${ROOT}/helpers/package_truth.py" audit --json)"
broken_rc=$?
set -e
[[ ${broken_rc} -ne 0 ]] && ok "audit exits non-zero on registry drift" || bad "broken audit should fail"
printf '%s\n' "${broken_audit}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
codes = {f["code"] for f in d["findings"] if f["level"] == "ERROR"}
expected = {
    "missing_group_brewfile",
    "missing_component_brewfile",
    "package_no_install_path",
    "brewfile_token_unrepresented",
    "platform_map_orphan",
    "duplicate_ownership",
    "required_unsupported_on_profile_platform",
    "helper_package_unrepresented",
}
missing = expected - codes
assert not missing, f"missing audit error codes: {missing} (got {codes})"
' && ok "audit detects all 8 structural drift error classes" || bad "audit missing expected error codes"

echo ""
echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
