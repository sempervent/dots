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

Shared ergonomic CLI + Git evolution / structural search / log inspection

**Required:** `bat`, `zoxide`, `direnv`, `htop`, `tree`

**Optional:** `eza`, `atuin`, `lazygit`, `btop`, `yq`, `uv`, `gh`, `just`, `git-delta`, `leaf`, `jj`, `git-town`, `git-filter-repo`, `git-sizer`, `ast-grep`, `lnav`

## `workstation`

Desktop-user tools (not headless)

**Required:** `ranger`

**Optional:** `terminal-notifier`, `chafa`, `poppler`

## `infra`

Docker CLI / Helm / Terraform (k8s operator CLIs live in group k8s)

**Required:** (none)

**Optional:** `docker`, `docker-compose`, `helm`, `terraform`

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

Local CI / lint / docs validation / Rust ergonomics (install-only; no shell aliases)

**Required:** (none)

**Optional:** `act`, `difftastic`, `mergiraf`, `actionlint`, `cargo-nextest`, `bacon`, `pre-commit`, `hadolint`, `taplo`, `mkcert`, `kondo`, `zizmor`, `git-cliff`, `lychee`, `markdownlint-cli2`, `cspell`

## `security`

Secrets / SBOM / signing / YubiKey / host-inspection CLIs (install-only; no auth or enrollment)

**Required:** (none)

**Optional:** `gitleaks`, `trivy`, `sops`, `age`, `syft`, `grype`, `cosign`, `osv-scanner`, `semgrep`, `ykman`, `age-plugin-yubikey`, `step`, `osquery`

## `network`

Network / remote CLIs (install-only; no scans, captures, iperf, or Tailscale up)

**Required:** (none)

**Optional:** `tailscale`, `mosh`, `rclone`, `bandwhich`, `gping`, `doggo`, `grpcurl`, `websocat`, `mtr`, `nmap`, `iperf3`, `termshark`, `tshark`

## `hardware`

Storage / bus / serial diagnostics (install-only; no SMART tests, fio workloads, or serial I/O)

**Required:** (none)

**Optional:** `smartmontools`, `fio`, `picocom`, `usbutils`, `pciutils`

## `data`

PostgreSQL inspection + tabular / analytical CLIs (install-only; no DB connections)

**Required:** (none)

**Optional:** `duckdb`, `qsv`, `visidata`, `miller`, `jless`, `pgcli`, `pg_activity`

## `backup`

Backup / recovery CLIs (install-only; no repo init, backup, restore, or sync daemon)

**Required:** (none)

**Optional:** `restic`

## `geo`

Geospatial CLI tooling

**Required:** (none)

**Optional:** `gdal`, `tippecanoe`, `pmtiles`

## `containers`

OCI / container operator CLIs (install-only; no runtime start, pull, or compose up)

**Required:** (none)

**Optional:** `lazydocker`, `dive`, `skopeo`, `crane`, `oras`, `devcontainer`, `dagger`

## `k8s`

Kubernetes / GitOps operator CLIs (install-only; no cluster create, context switch, or deploy)

**Required:** (none)

**Optional:** `kubernetes-cli`, `k9s`, `kubectx`, `stern`, `krew`, `kubeconform`, `kubescape`, `popeye`, `helmfile`, `argocd`

