#!/usr/bin/env bash
# scripts/tests/lsp_toolchain_test.sh — registry, providers, CLI, consent, Neovim
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="${ROOT}"
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
contains() {
	local needle="$1"
	shift
	local item
	for item in "$@"; do [[ ${item} == "${needle}" ]] && return 0; done
	return 1
}

# shellcheck source=../../helpers/toml.sh
source "${ROOT}/helpers/toml.sh"
# shellcheck source=../../helpers/components.sh
source "${ROOT}/helpers/components.sh"
# shellcheck source=../../helpers/packages.sh
source "${ROOT}/helpers/packages.sh"
# shellcheck source=../../helpers/bootstrap_prereqs.sh
source "${ROOT}/helpers/bootstrap_prereqs.sh"
# shellcheck source=../../helpers/python_runtime.sh
source "${ROOT}/helpers/python_runtime.sh"
# shellcheck source=../../helpers/lsp.sh
source "${ROOT}/helpers/lsp.sh"

echo "=== registry contract ==="
if [[ $(dots_lsp_validate_registry 2>&1) == OK ]]; then ok "registry validates"; else bad "registry validation"; fi
count="$(dots_lsp_rows | wc -l | tr -d ' ')"
[[ ${count} -eq 12 ]] && ok "12 server entries" || bad "expected 12 servers, got ${count}"

if python3 - "${ROOT}/configs/lsp/servers.toml" <<'PY'; then ok "apt/fallback matrix is deliberate"; else bad "provider matrix"; fi
import sys, tomllib
with open(sys.argv[1], "rb") as fh:
    data = tomllib.load(fh)
servers = {s["id"]: s for s in data["servers"]}
expected = {
    "rust-analyzer", "basedpyright", "gopls", "bash-language-server",
    "yaml-language-server", "vscode-json-language-server", "lua-language-server",
    "markdown-oxide", "taplo", "terraform-ls",
    "dockerfile-language-server", "r-languageserver",
}
assert set(servers) == expected
assert servers["rust-analyzer"]["apt"] == "rust-analyzer"
assert servers["gopls"]["apt"] == "gopls"
assert all(s["apt"] == "" for k, s in servers.items() if k not in {"rust-analyzer", "gopls"})
assert servers["basedpyright"]["fallback"] == "python_venv"
assert servers["r-languageserver"]["fallback"] == "cran"
assert servers["yaml-language-server"]["binary"] == "yaml-language-server"
assert servers["taplo"]["binary"] == "taplo"
assert servers["dockerfile-language-server"]["binary"] == "docker-langserver"
assert servers["vscode-json-language-server"]["binary"] == "vscode-json-language-server"
PY
brew_count="$(rg -c '^brew ' "${ROOT}/brew/Brewfile.lsp")"
[[ ${brew_count} -eq 12 ]] && ok "Brewfile has 12 formulae" || bad "Brewfile formula count=${brew_count}"
if python3 - "${ROOT}/configs/lsp/servers.toml" "${ROOT}/brew/Brewfile.lsp" <<'PY'; then ok "Brewfile matches registry"; else bad "Brewfile drift"; fi
import re, sys, tomllib
with open(sys.argv[1], "rb") as fh:
    data = tomllib.load(fh)
want = {s["brew"] for s in data["servers"] if s.get("brew")}
got = set(re.findall(r'^brew "([^"]+)"', open(sys.argv[2], encoding="utf-8").read(), re.M))
assert want == got, (want - got, got - want)
PY
echo "=== component and consent semantics ==="
members="$(dots_supergroup_members ai | tr '\n' ' ')"
case " ${members} " in *" lsp "*) ok "lsp is in ai" ;; *) bad "lsp missing from ai" ;; esac
all_ids="$(dots_component_ids_for_all | tr '\n' ' ')"
case " ${all_ids} " in *" lsp "*) ok "lsp is in all" ;; *) bad "lsp missing from all" ;; esac

show="$("${ROOT}/bootstrap.sh" --profile work --with lsp --show 2>&1)"
echo "${show}" | rg -q '^  lsp$' && ok "work + lsp selects leaf" || bad "work + lsp"
echo "${show}" | rg -q 'local AI: \(none\)' && echo "${show}" | rg -q 'cloud AI: \(none\)' && ok "lsp grants no AI provider consent" || bad "lsp provider isolation"
ai_show="$("${ROOT}/bootstrap.sh" --profile base --with ai --show 2>&1)"
echo "${ai_show}" | rg -q '^  lsp$' && ok "with ai includes lsp" || bad "ai missing lsp"
without_show="$("${ROOT}/bootstrap.sh" --profile base --with ai --without lsp --show 2>&1)"
if echo "${without_show}" | sed -n '/^components:/,/^requested:/p' | rg -q '^  lsp$'; then bad "without lsp retained lsp"; else ok "with ai --without lsp removes lsp"; fi
base_show="$("${ROOT}/bootstrap.sh" --profile base --show 2>&1)"
if echo "${base_show}" | sed -n '/^components:/,/^explicit provider/p' | rg -q '^  lsp$'; then bad "plain base includes lsp"; else ok "plain base unchanged"; fi

echo "=== desired-state and CLI ==="
TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-lsp-test.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/bin" "${TMP}/home"
while IFS='|' read -r _id _label _domains binary _rest; do
	cat >"${TMP}/bin/${binary}" <<'SH'
#!/usr/bin/env bash
exit 0
SH
	chmod +x "${TMP}/bin/${binary}"
done < <(dots_lsp_rows)
out="$(HOME="${TMP}/home" PATH="${TMP}/bin:${PATH}" dots_lsp_install 2>&1)" || bad "desired-state install failed"
already="$(echo "${out}" | rg -c 'already installed' || true)"
[[ ${already} -eq 12 ]] && ok "all existing servers are skipped" || bad "existing skip count=${already}"

cli="$("${ROOT}/dots" lsp list 2>&1)" || cli=""
echo "${cli}" | rg -q 'rust_analyzer' && echo "${cli}" | rg -q 'r_language_server' && ok "dots lsp list" || bad "dots lsp list"
help="$("${ROOT}/dots" lsp help 2>&1)" || help=""
echo "${help}" | rg -q 'lsp install --yes' && ok "dots lsp command surface" || bad "dots lsp help"
dry="$("${ROOT}/dots" lsp install --dry-run 2>&1)" || dry=""
echo "${dry}" | rg -q 'reconcile language servers' && ok "lsp install delegates to component dry-run" || bad "lsp install delegation"

echo "=== wizard and Neovim ==="
# shellcheck source=../../helpers/ui.sh
source "${ROOT}/helpers/ui.sh"
# shellcheck source=../../helpers/state.sh
source "${ROOT}/helpers/state.sh"
# shellcheck source=../../helpers/wizard.sh
source "${ROOT}/helpers/wizard.sh"
dots_prompt_yesno() {
	case "$1" in
	*"Language servers"*) echo y ;;
	*) echo n ;;
	esac
}
WIZ_WITH="" WIZ_WITHOUT=""
dots_wizard_pick_components base >/dev/null
[[ ${WIZ_WITH} == lsp ]] && ok "wizard selects lsp directly" || bad "wizard direct lsp got '${WIZ_WITH}'"
dots_prompt_yesno() {
	case "$1" in
	"Add AI applications"*) echo y ;;
	*"Exclude lsp"*) echo y ;;
	*) echo n ;;
	esac
}
WIZ_WITH="" WIZ_WITHOUT=""
dots_wizard_pick_components base >/dev/null
[[ ${WIZ_WITH} == ai && ${WIZ_WITHOUT} == lsp ]] && ok "wizard selects ai then excludes lsp" || bad "wizard ai exclusion with='${WIZ_WITH}' without='${WIZ_WITHOUT}'"

if python3 "${ROOT}/scripts/generate_lsp_nvim.py" --check; then ok "generated Neovim table is current"; else bad "Neovim table drift"; fi
if rg -q 'mason|ensure_installed' "${ROOT}/configs/nvim/lua/plugins/lsp.lua"; then bad "Neovim still manages LSP binaries"; else ok "Neovim consumes system binaries"; fi
for server in rust_analyzer basedpyright gopls bashls yamlls jsonls lua_ls markdown_oxide taplo terraformls dockerls r_language_server; do
	rg -q "^  ${server} =" "${ROOT}/configs/nvim/lua/config/lsp_servers.lua" && ok "Neovim config: ${server}" || bad "Neovim missing ${server}"
done

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
