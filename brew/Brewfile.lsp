# DOTS first-class language-server toolchain.
# Binary/provider details: configs/lsp/servers.toml
brew "rust-analyzer"
brew "basedpyright"
brew "gopls"
brew "bash-language-server"
brew "yaml-language-server"
brew "vscode-langservers-extracted"
brew "lua-language-server"
brew "markdown-oxide"
brew "taplo"
brew "terraform-ls"
brew "dockerfile-language-server"

# R's language server is a CRAN package; helpers/lsp.sh installs it idempotently.
brew "r"
