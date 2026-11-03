#!/usr/bin/env python3
"""Generate Zsh/Bash completion scripts for the `dots` CLI.

Sources: configs/help/commands.toml + component/package/LSP/topic registries.
Outputs (GENERATED — DO NOT EDIT):
  generated/completions/_dots
  generated/completions/dots.bash

Usage:
  python3 scripts/docs/generate_completions.py
  python3 scripts/docs/generate_completions.py --check
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Allow `python scripts/docs/generate_completions.py` without installing a package.
sys.path.insert(0, str(Path(__file__).resolve().parent))

import metadata as meta  # noqa: E402

ROOT = meta.ROOT
OUT_DIR = ROOT / "generated" / "completions"
ZSH_OUT = OUT_DIR / "_dots"
BASH_OUT = OUT_DIR / "dots.bash"

HEADER_ZSH = """\
#compdef dots
# GENERATED — DO NOT EDIT
# Source: configs/help/commands.toml + registries via scripts/docs/generate_completions.py
# Runtime: cheap filesystem reads only (profiles / snapshots). No network.

"""

HEADER_BASH = """\
# GENERATED — DO NOT EDIT
# Source: configs/help/commands.toml + registries via scripts/docs/generate_completions.py
# Bash completion for `dots` / `./dots`. No Textual/Python at Tab time.

"""


def _zsh_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "'\\''").replace(":", "\\:")


def _bash_escape(s: str) -> str:
    return s.replace("'", "'\\''")


def build_zsh() -> str:
    cmds = meta.commands()
    topics = meta.topics()
    comps = meta.components()
    sgs = meta.supergroups()
    groups = meta.package_groups()
    servers = meta.lsp_servers()
    profiles = meta.builtin_profiles()
    providers = meta.model_providers()
    tiers = meta.model_tiers()

    cmd_pairs = []
    for c in cmds:
        name = str(c.get("name") or "")
        if not name:
            continue
        desc = _zsh_escape(meta.short_desc(str(c.get("description") or ""), 56))
        cmd_pairs.append(f"    '{name}:{desc}'")

    topic_pairs = []
    for t in topics:
        tid = str(t.get("id") or "")
        title = _zsh_escape(str(t.get("title") or tid))
        topic_pairs.append(f"    '{tid}:{title}'")

    sel_pairs = []
    for row in sgs:
        sid = str(row.get("id") or "")
        lab = _zsh_escape(str(row.get("label") or row.get("description") or sid))
        if sid:
            sel_pairs.append(f"    '{sid}:{lab}'")
    for row in comps:
        cid = str(row.get("id") or "")
        lab = _zsh_escape(str(row.get("label") or row.get("description") or cid))
        if cid:
            sel_pairs.append(f"    '{cid}:{lab}'")

    group_pairs = []
    for g in groups:
        name = str(g.get("name") or "")
        desc = _zsh_escape(meta.short_desc(str(g.get("description") or ""), 48))
        if name:
            group_pairs.append(f"    '{name}:{desc}'")

    lsp_ids = [str(s.get("id") or "") for s in servers if s.get("id")]
    lsp_subs = ["status", "install", "check", "list"]
    model_subs = ["discover", "pull", "plan", "--list"]
    shell_subs = ["status", "keys", "startup"]
    completion_subs = ["status", "paths"]
    pkg_subs = ["groups", "group", "plan", "status", "explain", "outdated", "upgrade", "adopt", "help"]
    component_subs = ["list", "active", "show", "help"]
    ai_subs = ["status", "doctor", "up", "down", "help"]
    agent_subs = [
        "status",
        "doctor",
        "sandbox",
        "models",
        "scout",
        "route",
        "eval",
        "run",
        "worktrees",
        "diff",
        "apply",
        "discard",
        "mcp",
        "costs",
        "gateway",
    ]

    lines = [
        HEADER_ZSH.rstrip(),
        "",
        "_dots() {",
        "  local curcontext=\"$curcontext\" state state_descr line",
        "  typeset -A opt_args",
        "  local -a commands topics selectors groups profiles providers tiers",
        "  local -a lsp_subs model_subs shell_subs completion_subs pkg_subs",
        "  local -a component_subs ai_subs agent_subs lsp_ids",
        "",
        "  commands=(",
        *cmd_pairs,
        "  )",
        "  topics=(",
        *topic_pairs,
        "  )",
        "  selectors=(",
        *sel_pairs,
        "  )",
        "  groups=(",
        *group_pairs,
        "  )",
        "  profiles=(" + " ".join(f"'{p}'" for p in profiles) + ")",
        "  providers=(" + " ".join(f"'{p}'" for p in providers) + ")",
        "  tiers=(" + " ".join(f"'{t}'" for t in tiers) + ")",
        "  lsp_subs=(" + " ".join(f"'{s}'" for s in lsp_subs) + ")",
        "  model_subs=(" + " ".join(f"'{s}'" for s in model_subs) + ")",
        "  shell_subs=(" + " ".join(f"'{s}'" for s in shell_subs) + ")",
        "  completion_subs=(" + " ".join(f"'{s}'" for s in completion_subs) + ")",
        "  pkg_subs=(" + " ".join(f"'{s}'" for s in pkg_subs) + ")",
        "  component_subs=(" + " ".join(f"'{s}'" for s in component_subs) + ")",
        "  ai_subs=(" + " ".join(f"'{s}'" for s in ai_subs) + ")",
        "  agent_subs=(" + " ".join(f"'{s}'" for s in agent_subs) + ")",
        "  lsp_ids=(" + " ".join(f"'{s}'" for s in lsp_ids) + ")",
        "",
        "  _arguments -C \\",
        "    '1:command:->cmd' \\",
        "    '*::arg:->args' && return 0",
        "",
        "  case $state in",
        "  cmd)",
        "    _describe -t commands 'dots command' commands",
        "    ;;",
        "  args)",
        "    case ${words[1]} in",
        "    setup)",
        "      case ${words[CURRENT-1]} in",
        "      --profile|--profile=*)",
        "        _dots_profiles",
        "        ;;",
        "      --with|--with=*|--without|--without=*)",
        "        _describe -t selectors 'component/supergroup' selectors",
        "        ;;",
        "      *)",
        "        _values 'setup options' \\",
        "          '--dry-run[preview without mutating]' \\",
        "          '--yes[noninteractive]' \\",
        "          '--profile[profile name or path]:profile:_dots_profiles' \\",
        "          '--with[components/supergroups]:selector:->setup_sel' \\",
        "          '--without[exclude selectors]:selector:->setup_sel' \\",
        "          '--help[usage]'",
        "        if [[ $state == setup_sel ]]; then",
        "          _describe -t selectors 'component/supergroup' selectors",
        "        fi",
        "        ;;",
        "      esac",
        "      ;;",
        "    help)",
        "      if [[ ${words[CURRENT]} == -* ]]; then",
        "        _values 'help flags' --plain --search --cheatsheet --version --list-topics --markdown",
        "      else",
        "        _describe -t topics 'help topic' topics",
        "      fi",
        "      ;;",
        "    components|component)",
        "      if (( CURRENT == 2 )); then",
        "        _values 'components' ${component_subs[@]}",
        "      elif [[ ${words[2]} == show ]]; then",
        "        _describe -t selectors 'component' selectors",
        "      fi",
        "      ;;",
        "    packages|package)",
        "      if (( CURRENT == 2 )); then",
        "        _values 'packages' ${pkg_subs[@]}",
        "      elif [[ ${words[2]} == group ]]; then",
        "        _describe -t groups 'package group' groups",
        "      fi",
        "      ;;",
        "    lsp)",
        "      if (( CURRENT == 2 )); then",
        "        _values 'lsp' ${lsp_subs[@]}",
        "      elif [[ ${words[2]} == status || ${words[2]} == check ]]; then",
        "        _values 'lsp server' ${lsp_ids[@]}",
        "      fi",
        "      ;;",
        "    models)",
        "      case ${words[CURRENT-1]} in",
        "      --provider) _values 'provider' ${providers[@]} ;;",
        "      --tier) _values 'tier' ${tiers[@]} ;;",
        "      *)",
        "        if (( CURRENT == 2 )); then",
        "          _values 'models' ${model_subs[@]} --provider --tier --help",
        "        fi",
        "        ;;",
        "      esac",
        "      ;;",
        "    ai)",
        "      _values 'ai' ${ai_subs[@]}",
        "      ;;",
        "    agent)",
        "      if (( CURRENT == 3 )) && [[ ${words[2]} == eval ]]; then",
        "        _values 'eval' list run results compare regressions baseline calibrate import-openrouter",
        "      elif (( CURRENT >= 3 )) && [[ ${words[2]} == eval && ${words[3]} == run ]]; then",
        "        _values 'eval-run' --local --remote --suite --model --budget --runs --task-class --help",
        "      elif (( CURRENT == 3 )) && [[ ${words[2]} == route ]]; then",
        "        _values 'route' --task --language --context --output --quality --max-cost --simulate --local --json --help",
        "      else",
        "        _values 'agent' ${agent_subs[@]}",
        "      fi",
        "      ;;",
        "    shell)",
        "      _values 'shell' ${shell_subs[@]}",
        "      ;;",
        "    completion)",
        "      _values 'completion' ${completion_subs[@]}",
        "      ;;",
        "    profile)",
        "      _dots_profiles",
        "      ;;",
        "    restore)",
        "      _dots_snapshots",
        "      ;;",
        "    esac",
        "    ;;",
        "  esac",
        "}",
        "",
        "_dots_profiles() {",
        "  local -a all",
        "  all=(" + " ".join(f"'{p}'" for p in profiles) + ")",
        "  local custom=\"${HOME}/.config/dots/profiles\"",
        "  if [[ -d $custom ]]; then",
        "    local f",
        "    for f in \"$custom\"/*.toml(N); do",
        "      all+=(\"${f:t:r}\")",
        "    done",
        "  fi",
        "  _values 'profile' ${all[@]}",
        "}",
        "",
        "_dots_snapshots() {",
        "  local dir=\"${HOME}/.local/state/dots/backups\"",
        "  local -a snaps",
        "  if [[ -d $dir ]]; then",
        "    local d",
        "    for d in \"$dir\"/*(N/); do",
        "      snaps+=(\"${d:t}\")",
        "    done",
        "  fi",
        "  (( ${#snaps} )) && _values 'snapshot' ${snaps[@]} || return 1",
        "}",
        "",
    ]
    return "\n".join(lines)


def build_bash() -> str:
    cmds = meta.commands()
    topics = meta.topics()
    comps = meta.components()
    sgs = meta.supergroups()
    groups = meta.package_groups()
    servers = meta.lsp_servers()
    profiles = meta.builtin_profiles()
    providers = meta.model_providers()
    tiers = meta.model_tiers()

    cmd_names = " ".join(str(c.get("name")) for c in cmds if c.get("name"))
    topic_names = " ".join(str(t.get("id")) for t in topics if t.get("id"))
    selectors = []
    for row in sgs:
        if row.get("id"):
            selectors.append(str(row["id"]))
    for row in comps:
        if row.get("id"):
            selectors.append(str(row["id"]))
    sel_names = " ".join(selectors)
    group_names = " ".join(str(g.get("name")) for g in groups if g.get("name"))
    lsp_ids = " ".join(str(s.get("id")) for s in servers if s.get("id"))
    prof_names = " ".join(profiles)
    prov_names = " ".join(providers)
    tier_names = " ".join(tiers)

    return f"""{HEADER_BASH}
_dots_complete() {{
  local cur="${{COMP_WORDS[COMP_CWORD]:-}}"
  local prev="${{COMP_WORDS[COMP_CWORD - 1]:-}}"
  local cmd="${{COMP_WORDS[1]:-}}"
  local sub="${{COMP_WORDS[2]:-}}"

  local commands='{cmd_names}'
  local topics='{topic_names}'
  local selectors='{sel_names}'
  local groups='{group_names}'
  local profiles='{prof_names}'
  local providers='{prov_names}'
  local tiers='{tier_names}'
  local lsp_ids='{lsp_ids}'
  local lsp_subs='status install check list'
  local model_subs='discover pull plan --list'
  local shell_subs='status keys startup'
  local completion_subs='status paths'
  local pkg_subs='groups group plan status explain outdated upgrade adopt help'
  local component_subs='list active show help'
  local ai_subs='status doctor up down help'
  local agent_subs='status doctor sandbox models scout route eval run worktrees diff apply discard mcp costs gateway'

  _dots_custom_profiles() {{
    local d="${{HOME}}/.config/dots/profiles" f
    [[ -d $d ]] || return 0
    for f in "$d"/*.toml; do
      [[ -f $f ]] || continue
      printf '%s ' "$(basename "$f" .toml)"
    done
  }}

  _dots_snapshots() {{
    local d="${{HOME}}/.local/state/dots/backups" s
    [[ -d $d ]] || return 0
    for s in "$d"/*; do
      [[ -d $s ]] || continue
      printf '%s ' "$(basename "$s")"
    done
  }}

  if [[ ${{COMP_CWORD}} -eq 1 ]]; then
    COMPREPLY=($(compgen -W "${{commands}}" -- "${{cur}}"))
    return 0
  fi

  case "${{cmd}}" in
  setup)
    case "${{prev}}" in
    --profile)
      COMPREPLY=($(compgen -W "${{profiles}} $(_dots_custom_profiles)" -- "${{cur}}"))
      ;;
    --with|--without)
      COMPREPLY=($(compgen -W "${{selectors}}" -- "${{cur}}"))
      ;;
    *)
      COMPREPLY=($(compgen -W "--dry-run --yes --profile --with --without --help" -- "${{cur}}"))
      ;;
    esac
    ;;
  help)
    if [[ ${{cur}} == -* ]]; then
      COMPREPLY=($(compgen -W "--plain --search --cheatsheet --version --list-topics --markdown" -- "${{cur}}"))
    else
      COMPREPLY=($(compgen -W "${{topics}}" -- "${{cur}}"))
    fi
    ;;
  components|component)
    if [[ ${{COMP_CWORD}} -eq 2 ]]; then
      COMPREPLY=($(compgen -W "${{component_subs}}" -- "${{cur}}"))
    elif [[ ${{sub}} == show ]]; then
      COMPREPLY=($(compgen -W "${{selectors}}" -- "${{cur}}"))
    fi
    ;;
  packages|package)
    if [[ ${{COMP_CWORD}} -eq 2 ]]; then
      COMPREPLY=($(compgen -W "${{pkg_subs}}" -- "${{cur}}"))
    elif [[ ${{sub}} == group ]]; then
      COMPREPLY=($(compgen -W "${{groups}}" -- "${{cur}}"))
    fi
    ;;
  lsp)
    if [[ ${{COMP_CWORD}} -eq 2 ]]; then
      COMPREPLY=($(compgen -W "${{lsp_subs}}" -- "${{cur}}"))
    elif [[ ${{sub}} == status || ${{sub}} == check ]]; then
      COMPREPLY=($(compgen -W "${{lsp_ids}}" -- "${{cur}}"))
    fi
    ;;
  models)
    case "${{prev}}" in
    --provider) COMPREPLY=($(compgen -W "${{providers}}" -- "${{cur}}")) ;;
    --tier) COMPREPLY=($(compgen -W "${{tiers}}" -- "${{cur}}")) ;;
    *)
      if [[ ${{COMP_CWORD}} -eq 2 ]]; then
        COMPREPLY=($(compgen -W "${{model_subs}} --provider --tier --help" -- "${{cur}}"))
      fi
      ;;
    esac
    ;;
  ai)
    COMPREPLY=($(compgen -W "${{ai_subs}}" -- "${{cur}}"))
    ;;
  agent)
    COMPREPLY=($(compgen -W "${{agent_subs}}" -- "${{cur}}"))
    ;;
  shell)
    COMPREPLY=($(compgen -W "${{shell_subs}}" -- "${{cur}}"))
    ;;
  completion)
    COMPREPLY=($(compgen -W "${{completion_subs}}" -- "${{cur}}"))
    ;;
  profile)
    COMPREPLY=($(compgen -W "${{profiles}} $(_dots_custom_profiles)" -- "${{cur}}"))
    ;;
  restore)
    COMPREPLY=($(compgen -W "$(_dots_snapshots)" -- "${{cur}}"))
    ;;
  *)
    COMPREPLY=()
    ;;
  esac
  return 0
}}

if [[ -n ${{BASH_VERSION:-}} ]]; then
  complete -F _dots_complete dots 2>/dev/null || true
  complete -F _dots_complete ./dots 2>/dev/null || true
fi
"""


def write_or_check(path: Path, body: str, check: bool) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    if check:
        if not path.is_file() or path.read_text(encoding="utf-8") != body:
            print(f"drift: {path}", file=sys.stderr)
            return False
        return True
    path.write_text(body, encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)}")
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    zsh = build_zsh()
    bash = build_bash()
    ok = True
    ok &= write_or_check(ZSH_OUT, zsh, args.check)
    ok &= write_or_check(BASH_OUT, bash, args.check)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
