#!/usr/bin/env bash
# scripts/tests/component_supergroups_test.sh — declarative supergroup expansion
set -euo pipefail

DOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="${DOTS_DIR}"
# shellcheck source=../../helpers/toml.sh
source "${DOTS_DIR}/helpers/toml.sh"
# shellcheck source=../../helpers/components.sh
source "${DOTS_DIR}/helpers/components.sh"
# shellcheck source=../../helpers/profiles.sh
source "${DOTS_DIR}/helpers/profiles.sh"

pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

contains() {
	local needle="$1"
	shift
	local x
	for x in "$@"; do
		[[ ${x} == "${needle}" ]] && return 0
	done
	return 1
}

read_expand() {
	local dest="$1"
	shift
	eval "${dest}=()"
	local line
	while IFS= read -r line; do
		[[ -n ${line} ]] && eval "${dest}+=(\"\${line}\")"
	done < <(dots_expand_with_selectors "$@" 2>/dev/null)
}

echo "=== component registry validation ==="
if out="$(dots_validate_component_registry 2>&1)" && [[ ${out} == OK ]]; then
	ok "registry validates"
else
	bad "registry validation failed: ${out}"
fi

echo "=== ai supergroup members ==="
members="$(dots_supergroup_members ai | tr '\n' ' ')"
members="${members% }"
want="hermes ollama llamacpp drawthings opencode codex cursor fluidvoice lsp"
if [[ ${members} == "${want}" ]]; then
	ok "ai members declared"
else
	bad "ai members want='${want}' got='${members}'"
fi

echo "=== Darwin 15+ : --with ai includes fluidvoice ==="
export DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15
got=()
read_expand got ai
if contains fluidvoice "${got[@]+"${got[@]}"}"; then ok "darwin15 ai includes fluidvoice"; else bad "darwin15 missing fluidvoice"; fi
for m in hermes ollama llamacpp drawthings opencode codex cursor lsp; do
	if contains "${m}" "${got[@]+"${got[@]}"}"; then ok "darwin15 ai has ${m}"; else bad "darwin15 missing ${m}"; fi
done

echo "=== Linux : --with ai excludes fluidvoice/cursor/codex ==="
export DOTS_FORCE_OS=linux
unset DOTS_FORCE_DARWIN_MAJOR || true
got=()
read_expand got ai
if contains fluidvoice "${got[@]+"${got[@]}"}"; then bad "linux ai should omit fluidvoice"; else ok "linux ai omits fluidvoice"; fi
if contains cursor "${got[@]+"${got[@]}"}"; then bad "linux ai should omit cursor"; else ok "linux ai omits cursor"; fi
if contains codex "${got[@]+"${got[@]}"}"; then bad "linux ai should omit codex"; else ok "linux ai omits codex"; fi
if contains hermes "${got[@]+"${got[@]}"}" && contains ollama "${got[@]+"${got[@]}"}" && contains opencode "${got[@]+"${got[@]}"}" && contains llamacpp "${got[@]+"${got[@]}"}" && contains lsp "${got[@]+"${got[@]}"}"; then
	ok "linux ai keeps hermes/ollama/opencode/llamacpp/lsp"
else
	bad "linux ai missing portable members: ${got[*]-}"
fi
if contains drawthings "${got[@]+"${got[@]}"}"; then ok "linux ai keeps drawthings"; else bad "linux ai missing drawthings"; fi

echo "=== explicit Linux fluidvoice fails ==="
if dots_require_explicit_component_supported fluidvoice 2>/dev/null; then
	bad "explicit fluidvoice on linux should fail"
else
	ok "explicit fluidvoice on linux errors"
fi

echo "=== macOS <15 : explicit fluidvoice fails; ai omits ==="
export DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=14
if dots_require_explicit_component_supported fluidvoice 2>/dev/null; then
	bad "fluidvoice on macOS 14 should fail"
else
	ok "fluidvoice on macOS 14 errors"
fi
got=()
read_expand got ai
if contains fluidvoice "${got[@]+"${got[@]}"}"; then bad "ai on macOS 14 should omit fluidvoice"; else ok "ai on macOS 14 omits fluidvoice"; fi
if contains cursor "${got[@]+"${got[@]}"}"; then ok "ai on macOS 14 keeps cursor"; else bad "ai on macOS 14 missing cursor"; fi

echo "=== dedupe ai,ollama ==="
export DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15
got=()
read_expand got ai ollama
ollama_n=0
for x in "${got[@]+"${got[@]}"}"; do
	[[ ${x} == ollama ]] && ollama_n=$((ollama_n + 1))
done
if [[ ${ollama_n} -eq 1 ]]; then ok "ai,ollama dedupes"; else bad "ollama count=${ollama_n}"; fi

echo "=== unknown selector ==="
if dots_expand_with_selectors aii 2>/dev/null; then
	bad "unknown aii should fail"
else
	ok "unknown aii rejected"
fi

echo "=== without expansion ==="
gone=()
while IFS= read -r line; do
	[[ -n ${line} ]] && gone+=("${line}")
done < <(dots_expand_without_selectors ai 2>/dev/null)
if contains cursor "${gone[@]+"${gone[@]}"}" && contains fluidvoice "${gone[@]+"${gone[@]}"}"; then
	ok "without ai expands all members"
else
	bad "without ai incomplete: ${gone[*]-}"
fi

echo "=== profile: base + ai / without cursor ==="
export DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15
PROFILE_NAME="" PROFILE_WITH=() PROFILE_WITHOUT=() PROFILE_WITH_RAW=() PROFILE_WITHOUT_RAW=()
PROFILE_PACKAGES=() PROFILE_RUNTIME_MULTIPLEXER="" PROFILE_EXTENDS="" PROFILE_CHAIN=() PROFILE_OPEN_APPS=()
PROFILE_DESC="" PROFILE_RUNTIME_GREETING="" PROFILE_RUNTIME_PROMPT_STATS="" PROFILE_RUNTIME_AUTO_TMUX=""
CLI_WITH=(ai) CLI_WITHOUT=(cursor) CLI_WITH_RAW=() CLI_WITHOUT_RAW=() EFFECTIVE_WITH=()
dots_load_profile_file "$(dots_resolve_profile_path base)" >/dev/null
dots_compute_effective_with
if contains hermes "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then ok "base+ai has hermes"; else bad "base+ai missing hermes"; fi
if contains cursor "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then bad "base+ai --without cursor"; else ok "base+ai without cursor"; fi
if contains fluidvoice "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then ok "base+ai has fluidvoice"; else bad "base+ai missing fluidvoice"; fi

echo "=== profile: home --without ai ==="
CLI_WITH=() CLI_WITHOUT=(ai) EFFECTIVE_WITH=()
PROFILE_WITH=() PROFILE_WITHOUT=()
dots_load_profile_file "$(dots_resolve_profile_path home)" >/dev/null
dots_compute_effective_with
_ai_leak=0
for m in hermes ollama llamacpp drawthings opencode codex cursor fluidvoice lsp; do
	if contains "${m}" "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
		bad "home --without ai still has ${m}"
		_ai_leak=1
	fi
done
[[ ${_ai_leak} -eq 0 ]] && ok "home --without ai removes AI apps"
if contains herdr "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then ok "home --without ai keeps herdr"; else bad "home --without ai lost herdr"; fi
if contains skills "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then ok "home --without ai keeps skills"; else bad "home --without ai lost skills"; fi
if contains images "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then ok "home --without ai keeps images"; else bad "home --without ai lost images"; fi

echo "=== home Darwin equivalence (ai − fluidvoice + extras) ==="
CLI_WITH=() CLI_WITHOUT=() EFFECTIVE_WITH=()
PROFILE_WITH=() PROFILE_WITHOUT=()
dots_load_profile_file "$(dots_resolve_profile_path home)" >/dev/null
dots_compute_effective_with
home_got="$(printf '%s\n' "${EFFECTIVE_WITH[@]}" | sort | tr '\n' ' ')"
home_want="$(printf '%s\n' hermes herdr ollama llamacpp skills ai-skills drawthings opencode codex cursor images tex lsp | sort | tr '\n' ' ')"
if [[ ${home_got} == "${home_want}" ]]; then
	ok "home Darwin set matches prior leaf intent"
else
	bad "home Darwin want='${home_want}' got='${home_got}'"
fi

echo "=== work remains AI-free; work+ai adds ==="
CLI_WITH=() CLI_WITHOUT=() EFFECTIVE_WITH=()
dots_load_profile_file "$(dots_resolve_profile_path work)" >/dev/null
dots_compute_effective_with
if [[ ${#EFFECTIVE_WITH[@]} -eq 0 ]]; then ok "work → []"; else bad "work got ${EFFECTIVE_WITH[*]-}"; fi
CLI_WITH=(ai) CLI_WITHOUT=() EFFECTIVE_WITH=()
dots_load_profile_file "$(dots_resolve_profile_path work)" >/dev/null
dots_compute_effective_with
if contains hermes "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then ok "work+ai adds hermes"; else bad "work+ai missing hermes"; fi

echo "=== server + ai keeps herdr, omits fluidvoice ==="
export DOTS_FORCE_OS=linux
unset DOTS_FORCE_DARWIN_MAJOR || true
CLI_WITH=(ai) CLI_WITHOUT=() EFFECTIVE_WITH=()
dots_load_profile_file "$(dots_resolve_profile_path server)" >/dev/null
dots_compute_effective_with
if contains herdr "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then ok "server+ai keeps herdr"; else bad "server+ai lost herdr"; fi
if contains fluidvoice "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then bad "server+ai should omit fluidvoice"; else ok "server+ai omits fluidvoice"; fi

unset DOTS_FORCE_OS DOTS_FORCE_DARWIN_MAJOR || true

echo ""
echo "supergroup tests: ${pass} passed, ${fail} failed"
[[ ${fail} -eq 0 ]]
