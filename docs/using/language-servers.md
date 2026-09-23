# Language servers

DOTS provides a first-class local `lsp` component for code intelligence. It is
managed through the primary interface:

```bash
./dots lsp
./dots lsp status
./dots lsp install --yes
./dots lsp check
```

The direct automation interfaces are equivalent:

```bash
./dots setup --with lsp
./setup.sh --with lsp
./bootstrap.sh --profile base --with lsp
./setup.sh --with ai
```

`ai` includes the LSP toolchain so it produces a complete AI-assisted local
development environment. Selecting `lsp` alone installs and configures no AI or
cloud provider. Supergroup membership is not provider consent.

## Coverage

| Language / filetype | Server | Neovim id |
|---|---|---|
| Rust | rust-analyzer | `rust_analyzer` |
| Python | basedpyright | `basedpyright` |
| Go / modules / workspaces | gopls | `gopls` |
| Bash-compatible shell | bash-language-server | `bashls` |
| Markdown / MDX | markdown-oxide | `markdown_oxide` |
| TOML | Taplo | `taplo` |
| Terraform / HCL | terraform-ls | `terraformls` |
| Dockerfile | dockerfile-language-server | `dockerls` |
| Docker Compose | yaml-language-server + Compose schema | `yamlls` |
| R / R Markdown | CRAN languageserver | `r_language_server` |
| YAML | yaml-language-server | `yamlls` |
| JSON / JSONC | vscode-json-language-server | `jsonls` |
| Lua / Neovim Lua | lua-language-server | `lua_ls` |

`markdown-mathjax-lsp` was investigated for this release but no current,
maintained installable package/project under that name could be verified. DOTS
therefore does not invent an installer for it. `markdown-oxide` supplies general
links, references, headings, and workspace navigation; MathJax-specific LSP
support remains an explicit provider gap.

## Provider matrix

DOTS first accepts an already-working server binary, then uses Homebrew on
Homebrew systems or apt where the default Ubuntu/Debian repository actually has
the server. Only then does it use the declared official ecosystem/release
fallback.

| Server | Homebrew | Ubuntu 24.04 apt | Debian 13 apt | Trusted fallback |
|---|---|---|---|---|
| rust-analyzer | `rust-analyzer` | unavailable | `rust-analyzer` | official rust-analyzer GitHub binary |
| basedpyright | `basedpyright` | unavailable | unavailable | official PyPI package in an isolated venv |
| gopls | `gopls` | `gopls` | `gopls` | official `go install` module |
| bash-language-server | `bash-language-server` | unavailable | unavailable | official npm package |
| yaml-language-server | `yaml-language-server` | unavailable | unavailable | official npm package |
| vscode-json-language-server | `vscode-langservers-extracted` | unavailable | unavailable | upstream npm package |
| lua-language-server | `lua-language-server` | unavailable | unavailable | official LuaLS GitHub release |
| markdown-oxide | `markdown-oxide` | unavailable | unavailable | official GitHub release |
| Taplo | `taplo` | unavailable | unavailable | official `@taplo/cli` npm package |
| terraform-ls | `terraform-ls` | unavailable in default repos | unavailable in default repos | official Go module |
| Dockerfile language server | `dockerfile-language-server` | unavailable | unavailable | upstream `dockerfile-language-server-nodejs` npm package |
| R languageserver | `r` runtime | unavailable | unavailable | official CRAN `languageserver` package |

The npm fallback bootstraps a current Node runtime with the official `fnm`
release when the host Node is absent or older than Node 20. No `curl | sh`, PPA,
random mirror, or editor-private package directory is used.

## File ownership

Correct ownership is deliberate:

- Bash buffers use bash-language-server; Docker Compose does not.
- YAML and Compose YAML use yaml-language-server; TOML does not.
- Taplo owns TOML.
- terraform-ls owns `.tf`, `.tfvars`, and HCL buffers.
- dockerfile-language-server owns Dockerfile syntax.
- vscode-json-language-server owns JSON and JSONC.

Schema associations for Compose, GitHub Actions, and Kubernetes enhance YAML
when online. The YAML server still provides syntax intelligence offline; remote
schema downloads are not an installation dependency.

## Desired state

Every provider starts with its health contract. A valid executable already on
`PATH` (or an already-installed R `languageserver` namespace) is logged as
`already installed` and skipped, regardless of which package manager originally
provided it. Re-running `./dots lsp install` therefore converges without an
unnecessary reinstall loop.
