# Local security and supply-chain tooling

DOTS makes secure behavior **easy and inspectable** without auto-enrolling
devices, creating secrets, modifying YubiKeys, or rewriting SSH config.

## Install

Package group **`security`** (included in `work` / `home` profiles):

```bash
./setup.sh --profile work
# or: ./setup.sh --packages core,modern,security
```

macOS Secure Enclave SSH agent (**Secretive**) is opt-in via:

```bash
./setup.sh --with mactools
```

Secretive is **not** in `security`, `base`, `server`, or `all` auto-include.

## Commands

```bash
./dots check security              # full repository gate
./dots check security status       # host capabilities (informational)
./dots check security secrets      # gitleaks (working tree)
./dots check security deep-secrets # gitleaks including git history
./dots check security sbom         # Syft CycloneDX → Grype
./dots check security verify …     # cosign verify (no key gen)
```

`./dots check fast` does **not** run these scanners (Phase 1 stays cheap).

## Gate stages

| Stage | Tool | Network | Fail threshold |
|-------|------|---------|----------------|
| Secrets | gitleaks | no | any leak |
| Source | Semgrep (local rules only) | no | ERROR findings |
| Dependencies | OSV-Scanner | yes (OSV DB) | any reported vuln |
| Repository | Trivy fs | yes (DB update) | HIGH/CRITICAL |
| SBOM | Syft → Grype | Grype DB | HIGH+ (`--fail-on high`) |

Host capabilities (ykman / age / SOPS / osquery / step / cosign) are
**informational** and do not fail a clean repository.

Offline: set `DOTS_SECURITY_OFFLINE=1` to skip network-dependent scanners
(they report `SKIP`, not `PASS`).

## Privacy invariants

- Semgrep uses `configs/security/semgrep.yml` with `--metrics=off`.
  Never `--config auto` from DOTS.
- Scanners run against the DOTS repository only — not `$HOME`.
- Cosign Phase 2 is **verification-ready**; release signing is **not active**.
- No OIDC login, no key generation, no Sigstore publish.

## SOPS / age / YubiKey

Setup installs CLIs only. Documented user-driven next steps (never automated):

```bash
# Software age identity (user-run)
age-keygen -o ~/.config/age/keys.txt

# YubiKey-backed age plugin (user-run; touches the key)
age-plugin-yubikey --generate   # ONLY when you intend to provision

# Inspect YubiKey without mutation
ykman info
ykman list

# SOPS recipients — author .sops.yaml yourself; DOTS never writes it
```

## osquery

Installs the CLI (`osqueryi` via Darwin cask). DOTS **never**:

- starts `osqueryd`
- enrolls Fleet
- writes daemon config
- sends inventory off-box

Queries live in `configs/security/osquery/`.

## step / mkcert

- `step` — broader PKI/JWT tooling (install-only)
- `mkcert` — local TLS convenience (already in `dev`)

Neither bootstraps a CA or trusts roots during DOTS setup.

## Cosign future (Phase 11+)

Preferred options to evaluate later:

1. Keyless GitHub OIDC signing on release tags
2. Maintainer-held local key-backed signing

Phase 2 only ensures `cosign` is installed and `verify` works when you
pass an artifact + signature.

## Explicit non-goals (Phase 2 setup)

DOTS will **not**:

- modify YubiKey slots / PINs / touch policy
- generate age identities
- create `.sops.yaml` or encrypt files
- rewrite `~/.ssh/config` or launch Secretive
- start osqueryd or enroll agents
- bootstrap a CA or trust certificates
- sign releases or authenticate to external services
