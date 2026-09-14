# helpers/ai_consent.sh — strict opt-in isolation for AI clients/providers
#
# DESIGN RULE:
#   Software presence on the machine is NOT configuration consent.
#   DOTS may only mutate a client's config when that client was EXPLICITLY
#   selected via --with / bootstrap profile for THIS invocation.
#
# Binary presence may be used for diagnostics and checks only.
#
# Requires: has_component() from setup.sh / bootstrap

# True when the named AI client was explicitly selected this run.
# Clients: hermes | herdr | ollama | opencode | codex | cursor | drawthings
dots_client_selected() {
  has_component "$1"
}

# True when we may register MCP / mutate Hermes config this run.
dots_may_configure_hermes() {
  dots_client_selected hermes
}

dots_may_configure_cursor() {
  dots_client_selected cursor
}

dots_may_configure_opencode() {
  dots_client_selected opencode
}

dots_may_configure_codex() {
  dots_client_selected codex
}

dots_may_configure_ollama() {
  dots_client_selected ollama
}

dots_may_configure_drawthings() {
  dots_client_selected drawthings
}

# Herdr integrations: only when herdr AND the agent client are both selected.
dots_may_install_herdr_integration() {
  local agent="$1"
  dots_client_selected herdr || return 1
  case "${agent}" in
    hermes|opencode|codex|cursor) dots_client_selected "${agent}" ;;
    *) return 1 ;;
  esac
}

# Print ownership matrix (for --help / docs / dry-run notes)
dots_print_client_ownership_matrix() {
  cat <<'EOF'
AI client ownership (explicit --with / profile only):

  Component     May configure when selected
  ------------------------------------------------------------
  hermes        ~/.hermes/*  (MCP registration, notify hooks)
  herdr         ~/.config/herdr managed sections + integrations
                ONLY for co-selected agents
  ollama        local Ollama service notes / wiring when selected
  opencode      OpenCode config + Hermes MCP (if hermes also selected)
  codex         Codex adapter + Hermes MCP (if hermes also selected)
  cursor        ~/.cursor/* (cli-config merge, mcp.json merge) +
                Herdr cursor integration (if herdr also selected)
  drawthings    Draw Things bridge/launcher/config; MCP into a client
                ONLY when that client is also selected
  skills        ~/.agents/skills global store; Hermes exposure only
                when hermes is selected
  ai-skills     same store; AI pack only; no client config from pack alone

Binary presence alone NEVER authorizes configuration.
EOF
}
