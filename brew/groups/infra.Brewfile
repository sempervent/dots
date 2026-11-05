# brew/groups/infra.Brewfile — Docker / Helm / Terraform + IaC engineering CLIs
#
# Install-only. DOTS never:
#   - terraform/tofu init against remote backends
#   - terraform/tofu/terragrunt apply|destroy
#   - ansible-playbook against hosts
#   - vault login / token use
#   - packer build / packer init (plugin download)
#   - infracost API / cloud cost calls
#
# k9s / kubectl / GitOps CLIs live in brew/groups/k8s.Brewfile
# HashiCorp tooling uses the same hashicorp/tap already required for terraform.
#
# tflint: not currently in homebrew/core or hashicorp/tap (verified Phase 7).
#   Install from https://github.com/terraform-linters/tflint/releases or Linux pkgs.
#   Declared in configs/packages/groups.toml; Darwin Brewfile intentionally omits it.

brew "docker"
brew "docker-compose"
brew "docker-buildx"
brew "helm"

tap "hashicorp/tap"
brew "hashicorp/tap/terraform"
brew "terraform-ls"
brew "hashicorp/tap/vault"
brew "hashicorp/tap/packer"

# homebrew/core IaC companions
brew "terraform-docs"
brew "checkov"
brew "infracost"
brew "terragrunt"
brew "ansible"
brew "ansible-lint"
