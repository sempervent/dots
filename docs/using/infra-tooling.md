# Infrastructure engineering tooling

Package group **`infra`** installs Docker/Helm/Terraform plus IaC engineering
CLIs. DOTS validates tooling locally and does **not** deploy infrastructure.

## Install

```bash
./setup.sh --packages infra
# home / all already include infra
```

## Tooling map

| Tool | Role |
|------|------|
| `terraform` | IaC engine (`hashicorp/tap/terraform` on Homebrew; `pacman` on Arch) |
| `tofu` | OpenTofu (`opentofu` package in `infra`: Homebrew, Fedora, Arch, Void; `apt` unsupported without external repo; **not** auto-migrated) |
| `terraform-docs` | Module documentation generator |
| `tflint` | Terraform linter (no current Homebrew formula; install from releases/Linux) |
| `checkov` | Static IaC policy/security scan (**owned by infra**; local CLI) |
| `conftest` | Rego assertions on JSON/YAML (complements Checkov; local fixtures in gate) |
| `terragrunt` | DRY wrapper around Terraform/OpenTofu |
| `ansible` / `ansible-lint` | Config management + lint |
| `vault` | HashiCorp Vault CLI (same tap as terraform; install ≠ login) |
| `packer` | Image templates (install ≠ build) |
| `infracost` | Cost estimation CLI (API key optional; unused by default) |
| `helm` | Kubernetes packaging (pre-existing infra) |

## Terraform vs OpenTofu

Terraform and OpenTofu are complementary supported IaC engines in `infra`. DOTS
installs `opentofu` (`tofu` binary) on platforms with an authoritative native or
Homebrew package (macOS/Linuxbrew, Fedora, Arch/Manjaro, Void), while reporting
`apt` honestly as unsupported rather than enrolling third-party repositories.

`./dots check infra` reports version metadata for both `terraform` and `tofu`
when present, and `./dots check infra gate` runs non-mutating `fmt -check`
against local fixtures using whichever engines are installed. DOTS **never**
renames providers, rewrites `required_version`, runs `init`, converts `.tfstate`,
or migrates backends between Terraform and OpenTofu.

## Diagnostics

```bash
./dots check infra           # tool presence + local metadata
./dots check infra gate      # static fmt/lint on fixtures (no init)
./dots check infra examples
```

### What default checks never do

- `terraform`/`tofu`/`terragrunt` `init` against remote backends
- `apply` / `destroy` / Terragrunt `run-all`
- Ansible playbook execution, SSH, or fact gathering
- `vault login` or Vault server contact
- `packer init` / `packer build`
- Infracost API / cloud cost calls
- Reading `*.tfstate` (often secret-bearing)
- Printing cloud/Vault/Infracost/Terraform Cloud credentials

### Safe skips

`terraform validate` and `packer validate` need initialized plugins. Without
init, DOTS reports `SKIPPED_NOT_INITIALIZED` rather than contacting registries.

## ansible-vault vs HashiCorp Vault

| Tool | Purpose |
|------|---------|
| `ansible-vault` | Encrypt Ansible data at rest |
| `vault` (HashiCorp) | Secrets management server CLI |

DOTS does not decrypt Ansible Vault files or authenticate to HashiCorp Vault.

## HashiCorp packaging

`terraform`, `vault`, and `packer` use **`hashicorp/tap`** (already required for
Terraform). Linux native maps are often empty → SKIP unless Homebrew-on-Linux
or vendor repos are configured through DOTS-approved paths (never `curl|sh`).

## TFLint note

As of Phase 7 recon, **tflint is not** in `homebrew/core` or `hashicorp/tap`.
The package id remains declared; Darwin Brewfile omits it. Install from
[terraform-linters/tflint releases](https://github.com/terraform-linters/tflint/releases)
or distro packages when available.
