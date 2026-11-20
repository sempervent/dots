<!--
GENERATED — DO NOT EDIT.
Source: configs/packages/groups.toml + brew/groups/*.Brewfile + configs/packages/{apt,dnf,pacman,xbps}.toml
Generator: scripts/docs/generate_reference.py
-->

# Package groups (generated)

Logical groups from `configs/packages/groups.toml` with per-platform install routes (`brew/groups/<name>.Brewfile`, helper packages, and `configs/packages/*.toml`).

## `core`

Portable essentials

**Required:** `bash`, `zsh`, `tmux`, `git`, `curl`, `wget`, `jq`, `ripgrep`, `fd`, `fzf`, `neovim`, `rsync`

**Optional:** `shellcheck`, `fnm`, `starship`

**Brew companions:** `bash-completion@2`, `zsh-completions`, `shfmt`, `coreutils`, `findutils`, `gnu-sed`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `bash` | required | `bash` | apt, dnf, pacman, xbps |
| `zsh` | required | `zsh` | apt, dnf, pacman, xbps |
| `tmux` | required | `tmux` | apt, dnf, pacman, xbps |
| `git` | required | `git` | apt, dnf, pacman, xbps |
| `curl` | required | `curl` | apt, dnf, pacman, xbps |
| `wget` | required | `wget` | apt, dnf, pacman, xbps |
| `jq` | required | `jq` | apt, dnf, pacman, xbps |
| `ripgrep` | required | `ripgrep` | apt, dnf, pacman, xbps |
| `fd` | required | `fd` | apt, dnf, pacman, xbps |
| `fzf` | required | `fzf` | apt, dnf, pacman, xbps |
| `neovim` | required | `neovim` | apt, dnf, pacman, xbps |
| `rsync` | required | `rsync` | apt, dnf, pacman, xbps |
| `shellcheck` | optional | `shellcheck` | apt, dnf, pacman, xbps |
| `fnm` | optional | `fnm` | unsupported |
| `starship` | optional | `starship` | pacman, xbps |

## `modern`

Shared ergonomic CLI + Git evolution / structural search / log inspection

**Required:** `bat`, `zoxide`, `direnv`, `htop`, `tree`

**Optional:** `eza`, `atuin`, `lazygit`, `btop`, `yq`, `uv`, `gh`, `just`, `git-delta`, `leaf`, `jj`, `git-town`, `git-filter-repo`, `git-sizer`, `ast-grep`, `lnav`, `mise`, `dust`, `duf`, `jc`, `navi`, `sd`, `procs`, `ouch`

**Brew companions:** `git-lfs`, `moreutils`, `fastfetch`, `vim`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `bat` | required | `bat` | apt, dnf, pacman, xbps |
| `zoxide` | required | `zoxide` | apt, dnf, pacman, xbps |
| `direnv` | required | `direnv` | apt, dnf, pacman, xbps |
| `htop` | required | `htop` | apt, dnf, pacman, xbps |
| `tree` | required | `tree` | apt, dnf, pacman, xbps |
| `eza` | optional | `eza` | apt, dnf, pacman, xbps |
| `atuin` | optional | `atuin` | pacman |
| `lazygit` | optional | `lazygit` | apt, dnf, pacman, xbps |
| `btop` | optional | `btop` | apt, dnf, pacman, xbps |
| `yq` | optional | `yq` | apt, dnf, pacman, xbps |
| `uv` | optional | `uv` | pacman |
| `gh` | optional | `gh` | apt, dnf, pacman, xbps |
| `just` | optional | `just` | pacman |
| `git-delta` | optional | `git-delta` | apt, dnf, pacman, xbps |
| `leaf` | optional | `leaf-markdown-viewer` | unsupported |
| `jj` | optional | `jj` | pacman |
| `git-town` | optional | `git-town` | unsupported |
| `git-filter-repo` | optional | `git-filter-repo` | pacman |
| `git-sizer` | optional | `git-sizer` | unsupported |
| `ast-grep` | optional | `ast-grep` | unsupported |
| `lnav` | optional | `lnav` | pacman |
| `mise` | optional | `mise` | pacman |
| `dust` | optional | `dust` | apt, dnf, pacman |
| `duf` | optional | `duf` | apt, dnf, pacman, xbps |
| `jc` | optional | `jc` | apt, dnf, pacman |
| `navi` | optional | `navi` | pacman |
| `sd` | optional | `sd` | apt, dnf, pacman |
| `procs` | optional | `procs` | apt, dnf, pacman |
| `ouch` | optional | `ouch` | pacman |

## `workstation`

Desktop-user tools (not headless)

**Required:** `ranger`

**Optional:** `terminal-notifier`, `chafa`, `poppler`, `yazi`

**Brew companions:** `media-info`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `ranger` | required | `ranger` | apt, dnf, pacman, xbps |
| `terminal-notifier` | optional | `terminal-notifier` | unsupported |
| `chafa` | optional | `chafa` | apt, dnf, pacman, xbps |
| `poppler` | optional | `poppler` | apt, dnf, pacman, xbps |
| `yazi` | optional | `yazi` | pacman |

## `infra`

Docker/Helm/Terraform + IaC engineering CLIs (install-only; no apply/login/build)

**Required:** (none)

**Optional:** `docker`, `docker-compose`, `helm`, `terraform`, `opentofu`, `terraform-docs`, `tflint`, `checkov`, `infracost`, `terragrunt`, `ansible`, `ansible-lint`, `vault`, `packer`, `conftest`

**Brew companions:** `docker-buildx`, `terraform-ls`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `docker` | optional | `docker` | apt, dnf, pacman, xbps |
| `docker-compose` | optional | `docker-compose` | apt, dnf, pacman, xbps |
| `helm` | optional | `helm` | pacman |
| `terraform` | optional | `terraform` | pacman |
| `opentofu` | optional | `opentofu` | dnf, pacman, xbps |
| `terraform-docs` | optional | `terraform-docs` | unsupported |
| `tflint` | optional | unsupported | unsupported |
| `checkov` | optional | `checkov` | unsupported |
| `infracost` | optional | `infracost` | unsupported |
| `terragrunt` | optional | `terragrunt` | unsupported |
| `ansible` | optional | `ansible` | apt, dnf, pacman, xbps |
| `ansible-lint` | optional | `ansible-lint` | apt, dnf, pacman |
| `vault` | optional | `vault` | unsupported |
| `packer` | optional | `packer` | unsupported |
| `conftest` | optional | `conftest` | apt, dnf, pacman |

## `media`

Image / audio / video / retrieval CLIs (install-only; no capture, playback, or downloads)

**Required:** (none)

**Optional:** `ffmpeg`, `imagemagick`, `exiftool`, `sox`, `yt-dlp`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `ffmpeg` | optional | `ffmpeg` | apt, dnf, pacman, xbps |
| `imagemagick` | optional | `imagemagick` | apt, dnf, pacman, xbps |
| `exiftool` | optional | `exiftool` | apt, dnf, pacman, xbps |
| `sox` | optional | `sox` | apt, dnf, pacman, xbps |
| `yt-dlp` | optional | `yt-dlp` | apt, dnf, pacman, xbps |

## `gui`

macOS GUI / fonts

**Required:** `font-jetbrains-mono-nerd-font`

**Optional:** (none)

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `font-jetbrains-mono-nerd-font` | required | `font-jetbrains-mono-nerd-font` | unsupported |

## `server`

Headless extras

**Required:** `htop`

**Optional:** (none)

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `htop` | required | `htop` | apt, dnf, pacman, xbps |

## `dev`

Local CI / lint / docs validation / Rust ergonomics (install-only; no shell aliases)

**Required:** (none)

**Optional:** `act`, `difftastic`, `mergiraf`, `actionlint`, `cargo-nextest`, `bacon`, `pre-commit`, `hadolint`, `taplo`, `mkcert`, `kondo`, `zizmor`, `git-cliff`, `lychee`, `markdownlint-cli2`, `cspell`, `watchexec`, `hyperfine`, `mprocs`, `xh`, `hexyl`, `tokei`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `act` | optional | `act` | pacman |
| `difftastic` | optional | `difftastic` | pacman |
| `mergiraf` | optional | `mergiraf` | unsupported |
| `actionlint` | optional | `actionlint` | pacman |
| `cargo-nextest` | optional | `cargo-nextest` | unsupported |
| `bacon` | optional | `bacon` | unsupported |
| `pre-commit` | optional | `pre-commit` | apt, dnf, pacman |
| `hadolint` | optional | `hadolint` | unsupported |
| `taplo` | optional | `taplo` | unsupported |
| `mkcert` | optional | `mkcert` | apt, dnf, pacman |
| `kondo` | optional | `kondo` | unsupported |
| `zizmor` | optional | `zizmor` | unsupported |
| `git-cliff` | optional | `git-cliff` | unsupported |
| `lychee` | optional | `lychee` | unsupported |
| `markdownlint-cli2` | optional | `markdownlint-cli2` | unsupported |
| `cspell` | optional | `cspell` | unsupported |
| `watchexec` | optional | `watchexec` | apt, dnf, pacman |
| `hyperfine` | optional | `hyperfine` | apt, dnf, pacman, xbps |
| `mprocs` | optional | `dekit` | unsupported |
| `xh` | optional | `xh` | apt, dnf, pacman |
| `hexyl` | optional | `hexyl` | apt, dnf, pacman |
| `tokei` | optional | `tokei` | apt, dnf, pacman |

## `security`

Secrets / SBOM / signing / YubiKey / host-inspection CLIs (install-only; no auth or enrollment)

**Required:** (none)

**Optional:** `gitleaks`, `trivy`, `sops`, `age`, `syft`, `grype`, `cosign`, `osv-scanner`, `semgrep`, `ykman`, `age-plugin-yubikey`, `step`, `osquery`, `ssh-audit`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `gitleaks` | optional | `gitleaks` | pacman |
| `trivy` | optional | `trivy` | pacman |
| `sops` | optional | `sops` | pacman |
| `age` | optional | `age` | apt, dnf, pacman, xbps |
| `syft` | optional | `syft` | unsupported |
| `grype` | optional | `grype` | unsupported |
| `cosign` | optional | `cosign` | pacman |
| `osv-scanner` | optional | `osv-scanner` | unsupported |
| `semgrep` | optional | `semgrep` | unsupported |
| `ykman` | optional | `ykman` | apt, dnf, pacman |
| `age-plugin-yubikey` | optional | `age-plugin-yubikey` | unsupported |
| `step` | optional | `step` | unsupported |
| `osquery` | optional | `osquery` | unsupported |
| `ssh-audit` | optional | `ssh-audit` | apt, dnf, pacman, xbps |

## `network`

Network / remote CLIs (install-only; no scans, captures, iperf, or Tailscale up)

**Required:** (none)

**Optional:** `tailscale`, `mosh`, `rclone`, `bandwhich`, `gping`, `doggo`, `grpcurl`, `websocat`, `mtr`, `nmap`, `iperf3`, `termshark`, `tshark`, `sshuttle`, `autossh`, `sshs`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `tailscale` | optional | `tailscale` | pacman |
| `mosh` | optional | `mosh` | apt, dnf, pacman, xbps |
| `rclone` | optional | `rclone` | apt, dnf, pacman, xbps |
| `bandwhich` | optional | `bandwhich` | pacman |
| `gping` | optional | `gping` | pacman |
| `doggo` | optional | `doggo` | pacman |
| `grpcurl` | optional | `grpcurl` | unsupported |
| `websocat` | optional | `websocat` | pacman |
| `mtr` | optional | `mtr` | apt, dnf, pacman, xbps |
| `nmap` | optional | `nmap` | apt, dnf, pacman, xbps |
| `iperf3` | optional | `iperf3` | apt, dnf, pacman, xbps |
| `termshark` | optional | unsupported | apt |
| `tshark` | optional | unsupported | apt, dnf, pacman, xbps |
| `sshuttle` | optional | `sshuttle` | apt, dnf, pacman, xbps |
| `autossh` | optional | `autossh` | apt, dnf, pacman, xbps |
| `sshs` | optional | `sshs` | pacman |

## `hardware`

Storage / bus / serial diagnostics (install-only; no SMART tests, fio workloads, or serial I/O)

**Required:** (none)

**Optional:** `smartmontools`, `fio`, `picocom`, `usbutils`, `pciutils`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `smartmontools` | optional | `smartmontools` | apt, dnf, pacman, xbps |
| `fio` | optional | `fio` | apt, dnf, pacman, xbps |
| `picocom` | optional | `picocom` | apt, dnf, pacman, xbps |
| `usbutils` | optional | `usbutils` | apt, dnf, pacman, xbps |
| `pciutils` | optional | `pciutils` | apt, dnf, pacman, xbps |

## `data`

PostgreSQL inspection + tabular / analytical CLIs (install-only; no DB connections)

**Required:** (none)

**Optional:** `duckdb`, `qsv`, `visidata`, `miller`, `jless`, `pgcli`, `pg_activity`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `duckdb` | optional | `duckdb` | pacman |
| `qsv` | optional | `qsv` | unsupported |
| `visidata` | optional | `visidata` | apt, dnf, pacman |
| `miller` | optional | `miller` | apt, dnf, pacman, xbps |
| `jless` | optional | `jless` | pacman |
| `pgcli` | optional | `pgcli` | unsupported |
| `pg_activity` | optional | `pg_activity` | unsupported |

## `backup`

Backup / recovery CLIs (install-only; no repo init, backup, restore, or sync daemon)

**Required:** (none)

**Optional:** `restic`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `restic` | optional | `restic` | apt, dnf, pacman, xbps |

## `geo`

Geospatial CLI tooling (OSM / tiles / geometry; install-only; no data download or DB import)

**Required:** (none)

**Optional:** `gdal`, `tippecanoe`, `pmtiles`, `osmium-tool`, `osm2pgsql`, `mapshaper`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `gdal` | optional | `gdal` | apt, dnf, pacman, xbps |
| `tippecanoe` | optional | `tippecanoe` | unsupported |
| `pmtiles` | optional | `pmtiles` | unsupported |
| `osmium-tool` | optional | `osmium-tool` | apt, dnf, pacman |
| `osm2pgsql` | optional | `osm2pgsql` | apt, dnf, pacman |
| `mapshaper` | optional | helper (`helpers/mapshaper.sh`) | helper (`helpers/mapshaper.sh`) |

## `containers`

OCI / container operator CLIs (install-only; no runtime start, pull, or compose up)

**Required:** (none)

**Optional:** `lazydocker`, `dive`, `skopeo`, `crane`, `oras`, `devcontainer`, `dagger`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `lazydocker` | optional | `lazydocker` | pacman |
| `dive` | optional | `dive` | pacman |
| `skopeo` | optional | `skopeo` | apt, dnf, pacman, xbps |
| `crane` | optional | `crane` | unsupported |
| `oras` | optional | `oras` | unsupported |
| `devcontainer` | optional | `devcontainer` | unsupported |
| `dagger` | optional | `dagger` | unsupported |

## `k8s`

Kubernetes / GitOps operator CLIs (install-only; no cluster create, context switch, or deploy)

**Required:** (none)

**Optional:** `kubernetes-cli`, `k9s`, `kubectx`, `stern`, `krew`, `kubeconform`, `kubescape`, `popeye`, `helmfile`, `argocd`, `kustomize`, `kyverno`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `kubernetes-cli` | optional | `kubernetes-cli` | pacman |
| `k9s` | optional | `k9s` | pacman |
| `kubectx` | optional | `kubectx` | pacman |
| `stern` | optional | `stern` | pacman |
| `krew` | optional | `krew` | unsupported |
| `kubeconform` | optional | `kubeconform` | unsupported |
| `kubescape` | optional | `kubescape` | unsupported |
| `popeye` | optional | `popeye` | unsupported |
| `helmfile` | optional | `helmfile` | unsupported |
| `argocd` | optional | `argocd` | unsupported |
| `kustomize` | optional | `kustomize` | dnf, pacman |
| `kyverno` | optional | `kyverno` | dnf, pacman |

## `docs`

Technical documentation / publishing CLIs (install-only; no rewrite, publish, or browser download)

**Required:** (none)

**Optional:** `graphviz`, `pandoc`, `vale`, `mermaid-cli`, `typst`

| package | class | darwin/brew | linux native |
| --- | --- | --- | --- |
| `graphviz` | optional | `graphviz` | apt, dnf, pacman, xbps |
| `pandoc` | optional | `pandoc` | apt, dnf, pacman, xbps |
| `vale` | optional | `vale` | unsupported |
| `mermaid-cli` | optional | `mermaid-cli` | unsupported |
| `typst` | optional | `typst` | pacman |

