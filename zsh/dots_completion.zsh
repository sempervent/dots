# Zsh completion for ./dots — wraps shared shell/dots_completion.sh via bashcompinit
# when available; otherwise installs a native compsys completer.

autoload -Uz bashcompinit 2>/dev/null && bashcompinit 2>/dev/null || true

if [[ -f "${DOTS_DIR}/shell/dots_completion.sh" ]]; then
  # shellcheck disable=SC1091
  source "${DOTS_DIR}/shell/dots_completion.sh"
fi

_dots_zsh() {
  local -a cmds topics
  cmds=(
    setup status components lsp ai packages backup backups restore
    profile models check update help
  )
  topics=(
    overview getting-started shell completion keybindings profiles
    components supergroups packages ai models lsp skills backup
    diagnostics update commands files
  )

  if (( CURRENT == 2 )); then
    _describe -t commands 'dots command' cmds
    return
  fi

  case "${words[2]}" in
  help)
    if [[ ${words[CURRENT]} == -* ]]; then
      _values 'help flags' --plain --search --version --list-topics
    else
      _describe -t topics 'help topic' topics
    fi
    ;;
  components)
    _values 'components' list active show help
    ;;
  packages)
    _values 'packages' groups group plan status explain outdated upgrade adopt help
    ;;
  lsp)
    _values 'lsp' status check install list help
    ;;
  models)
    _values 'models' discover pull plan help
    ;;
  ai)
    _values 'ai' status doctor up down help
    ;;
  setup)
    _values 'setup' --dry-run --yes --profile --with --without --help
    ;;
  esac
}

compdef _dots_zsh dots 2>/dev/null || true
