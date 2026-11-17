# brew/groups/security.Brewfile — secrets / SBOM / signing / YubiKey / inventory CLIs
# Install-only. No secrets, keys, auth, YubiKey mutation, CA bootstrap, or osquery enrollment.

brew "gitleaks"
brew "trivy"
brew "sops"
brew "age"
brew "syft"
brew "grype"
brew "cosign"
brew "osv-scanner"
brew "semgrep"
# v1.7 Phase 2
brew "ykman"
brew "age-plugin-yubikey"
brew "step"
# Darwin: Homebrew ships osquery as a cask (CLI + optional agent bits). DOTS never starts osqueryd.
cask "osquery"
# v1.8 — explicit SSH audits only when user runs ssh-audit (DOTS never audits hosts)
brew "ssh-audit"
