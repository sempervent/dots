# LSP (Language Server Protocol) tools for IDE support
# Use ./setup.sh --with lsp
#
# Provides language servers for common filetypes:
#   bash-language-server  → .sh, docker-compose.yml
#   yaml-language-server  → .yml, .yaml, .toml (for some LSP clients)
#   json-language-server   → .json
#   lua-language-server    → .lua
#   markdown-mathjax-lsp   → .md with MathJax support

brew "bash-language-server"
brew "rusty.vim"  # rust-analyzer + language server
brew "yamllint"    # YAML schema support via yamlschema
brew "jsonlint"    # JSON validation (schema support)
brew "deno"        # Lua/JavaScript LSP via deno
