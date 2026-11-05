# Kubernetes and GitOps tooling

Package group **`k8s`** installs operator CLIs. It does **not** create clusters,
modify kubeconfig, switch context/namespace, deploy workloads, or sync Argo CD.

## Install

```bash
./setup.sh --packages core,modern,k8s
# or:
./setup.sh --profile home
```

Helm itself remains in package group **`infra`** (Helmfile soft-depends on it).

## Commands

```bash
./dots check k8s            # kubectl client + local manifest validation
./dots check k8s status     # tools vs connected environment
```

## Tools

| Tool | Role |
|------|------|
| kubernetes (`kubernetes-cli`) | kubectl client |
| k9s | Cluster TUI |
| kubectx / kubens | Context/namespace helpers (**one** Homebrew formula: `kubectx`) |
| stern | Multi-pod log tail |
| krew | kubectl plugin manager (plugins **not** auto-installed) |
| kubeconform | Local manifest schema validation |
| kubescape | Local manifest/policy scan (no cloud login) |
| popeye | Live cluster sanitation (opt-in use only) |
| helmfile | Declarative Helm (no apply during checks) |
| argocd | Argo CD CLI (no login/sync during checks) |

## Validation

Default gate:

1. `kubectl` client available
2. Discover YAML with `apiVersion` + `kind` (skips Actions/Compose/MkDocs)
3. `kubeconform` when manifests exist
4. Optional local `kubescape` when manifests exist

**No Kubernetes manifests → SKIP, not FAIL.**

Cluster reachability is **informational**. A workstation with tools but no
kubeconfig is valid.

## Explicit non-goals

Setup / `./dots check k8s` will **not**:

- create or join a cluster
- modify `~/.kube/config`
- `kubectl config use-context` / `kubens` / `kubectx` automatically
- install krew plugins
- `helmfile apply` / destroy
- `argocd login` / sync
- require a YubiKey
