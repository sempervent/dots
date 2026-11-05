# GENERATED — DO NOT EDIT
# Source: configs/help/commands.toml + registries via scripts/docs/generate_completions.py
# Bash completion for `dots` / `./dots`. No Textual/Python at Tab time.


_dots_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]:-}"
  local prev="${COMP_WORDS[COMP_CWORD - 1]:-}"
  local cmd="${COMP_WORDS[1]:-}"
  local sub="${COMP_WORDS[2]:-}"

  local commands='setup status components lsp ai agent packages backup backups restore profile models check update help shell completion'
  local topics='overview getting-started shell completion keybindings profiles components supergroups packages ai models lsp skills backup data agent network agent-security hardware infra docs-tooling geo diagnostics media update commands files agent-evals agent-routing agent-teams'
  local selectors='ai herdr hermes ollama llamacpp archify skills ai-skills drawthings opencode codex cursor fluidvoice images tex mactools orbstack mitmproxy syncthing lsp ai-server pi litellm agent-sandbox openrig'
  local groups='core modern workstation infra media gui server dev security network hardware data backup geo containers k8s docs'
  local profiles='base home work server all'
  local providers='ollama llamacpp drawthings fluidvoice all'
  local tiers='auto minimal balanced large max'
  local lsp_ids='rust-analyzer basedpyright gopls bash-language-server yaml-language-server vscode-json-language-server lua-language-server markdown-oxide taplo terraform-ls dockerfile-language-server r-languageserver'
  local lsp_subs='status install check list'
  local model_subs='discover pull plan --list'
  local shell_subs='status keys startup'
  local completion_subs='status paths'
  local pkg_subs='groups group plan status explain outdated upgrade adopt help'
  local component_subs='list active show help'
  local ai_subs='status doctor up down help'
  local agent_subs='status doctor sandbox models scout route eval team run worktrees diff apply discard mcp costs gateway'

  _dots_custom_profiles() {
    local d="${HOME}/.config/dots/profiles" f
    [[ -d $d ]] || return 0
    for f in "$d"/*.toml; do
      [[ -f $f ]] || continue
      printf '%s ' "$(basename "$f" .toml)"
    done
  }

  _dots_snapshots() {
    local d="${HOME}/.local/state/dots/backups" s
    [[ -d $d ]] || return 0
    for s in "$d"/*; do
      [[ -d $s ]] || continue
      printf '%s ' "$(basename "$s")"
    done
  }

  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
    return 0
  fi

  case "${cmd}" in
  setup)
    case "${prev}" in
    --profile)
      COMPREPLY=($(compgen -W "${profiles} $(_dots_custom_profiles)" -- "${cur}"))
      ;;
    --with|--without)
      COMPREPLY=($(compgen -W "${selectors}" -- "${cur}"))
      ;;
    *)
      COMPREPLY=($(compgen -W "--dry-run --yes --profile --with --without --help" -- "${cur}"))
      ;;
    esac
    ;;
  help)
    if [[ ${cur} == -* ]]; then
      COMPREPLY=($(compgen -W "--plain --search --cheatsheet --version --list-topics --markdown" -- "${cur}"))
    else
      COMPREPLY=($(compgen -W "${topics}" -- "${cur}"))
    fi
    ;;
  components|component)
    if [[ ${COMP_CWORD} -eq 2 ]]; then
      COMPREPLY=($(compgen -W "${component_subs}" -- "${cur}"))
    elif [[ ${sub} == show ]]; then
      COMPREPLY=($(compgen -W "${selectors}" -- "${cur}"))
    fi
    ;;
  packages|package)
    if [[ ${COMP_CWORD} -eq 2 ]]; then
      COMPREPLY=($(compgen -W "${pkg_subs}" -- "${cur}"))
    elif [[ ${sub} == group ]]; then
      COMPREPLY=($(compgen -W "${groups}" -- "${cur}"))
    fi
    ;;
  lsp)
    if [[ ${COMP_CWORD} -eq 2 ]]; then
      COMPREPLY=($(compgen -W "${lsp_subs}" -- "${cur}"))
    elif [[ ${sub} == status || ${sub} == check ]]; then
      COMPREPLY=($(compgen -W "${lsp_ids}" -- "${cur}"))
    fi
    ;;
  models)
    case "${prev}" in
    --provider) COMPREPLY=($(compgen -W "${providers}" -- "${cur}")) ;;
    --tier) COMPREPLY=($(compgen -W "${tiers}" -- "${cur}")) ;;
    *)
      if [[ ${COMP_CWORD} -eq 2 ]]; then
        COMPREPLY=($(compgen -W "${model_subs} --provider --tier --help" -- "${cur}"))
      fi
      ;;
    esac
    ;;
  ai)
    COMPREPLY=($(compgen -W "${ai_subs}" -- "${cur}"))
    ;;
  agent)
    COMPREPLY=($(compgen -W "${agent_subs}" -- "${cur}"))
    ;;
  shell)
    COMPREPLY=($(compgen -W "${shell_subs}" -- "${cur}"))
    ;;
  completion)
    COMPREPLY=($(compgen -W "${completion_subs}" -- "${cur}"))
    ;;
  profile)
    COMPREPLY=($(compgen -W "${profiles} $(_dots_custom_profiles)" -- "${cur}"))
    ;;
  restore)
    COMPREPLY=($(compgen -W "$(_dots_snapshots)" -- "${cur}"))
    ;;
  *)
    COMPREPLY=()
    ;;
  esac
  return 0
}

if [[ -n ${BASH_VERSION:-} ]]; then
  complete -F _dots_complete dots 2>/dev/null || true
  complete -F _dots_complete ./dots 2>/dev/null || true
fi
