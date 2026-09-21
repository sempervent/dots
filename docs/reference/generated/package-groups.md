<!--
GENERATED — DO NOT EDIT.
Source: configs/packages/groups.toml
Generator: scripts/docs/generate_reference.py
-->

# Package groups (generated)

Logical groups from `configs/packages/groups.toml`. Homebrew ownership: `brew/groups/<name>.Brewfile`.

## `core`

Portable essentials

**Required:** `bash`, `zsh`, `tmux`, `git`, `curl`, `wget`, `jq`, `ripgrep`, `fd`, `fzf`, `neovim`, `rsync`

**Optional:** `shellcheck`, `fnm`, `starship`

## `modern`

Shared ergonomic CLI

**Required:** `bat`, `zoxide`, `direnv`, `htop`, `tree`

**Optional:** `eza`, `atuin`, `lazygit`, `btop`, `yq`, `uv`, `gh`, `just`, `git-delta`, `leaf`

## `workstation`

Desktop-user tools (not headless)

**Required:** `ranger`

**Optional:** `terminal-notifier`, `chafa`, `poppler`

## `infra`

Containers / k8s / terraform

**Required:** (none)

**Optional:** `docker`, `docker-compose`, `helm`, `k9s`, `terraform`

## `media`

Image / video processing

**Required:** (none)

**Optional:** `ffmpeg`, `imagemagick`, `exiftool`

## `gui`

macOS GUI / fonts

**Required:** `font-jetbrains-mono-nerd-font`

**Optional:** (none)

## `server`

Headless extras

**Required:** `htop`

**Optional:** (none)

## `dev`

Local CI / lint / Rust ergonomics (install-only; no shell aliases)

**Required:** (none)

**Optional:** `act`, `difftastic`, `mergiraf`, `actionlint`, `cargo-nextest`, `bacon`, `pre-commit`, `hadolint`, `taplo`, `mkcert`, `kondo`

## `security`

Secrets scanning / SBOM / signing CLIs (install-only; no auth)

**Required:** (none)

**Optional:** `gitleaks`, `trivy`, `sops`, `age`, `syft`, `grype`, `cosign`, `osv-scanner`, `semgrep`

## `network`

Network / remote / k8s context CLIs (install-only; no Tailscale up)

**Required:** (none)

**Optional:** `tailscale`, `mosh`, `rclone`, `bandwhich`, `gping`, `doggo`, `stern`, `kubectx`, `grpcurl`, `websocat`

## `data`

Tabular / analytical CLIs

**Required:** (none)

**Optional:** `duckdb`, `qsv`, `visidata`, `miller`, `jless`

## `geo`

Geospatial CLI tooling

**Required:** (none)

**Optional:** `gdal`, `tippecanoe`, `pmtiles`

