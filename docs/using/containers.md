# Containers and OCI tooling

Package group **`containers`** installs operator CLIs. It does **not** start a
container runtime, pull images, or run Compose services.

## Install

```bash
./setup.sh --packages core,modern,containers
# or home profile (includes containers):
./setup.sh --profile home
```

## Commands

```bash
./dots check containers          # OCI CLI presence + static Dockerfile/Compose
./dots check containers status   # runtime/OrbStack informational report
```

## Tools

| Tool | Role |
|------|------|
| lazydocker | Docker TUI (needs reachable runtime to *use*) |
| dive | Image layer explorer |
| skopeo | Copy/inspect images across registries |
| crane | Registry client |
| oras | OCI artifact CLI |
| devcontainer | Dev Container CLI |
| dagger | Portable pipelines CLI |

Docker CLI / Compose / Buildx remain in package group **`infra`**.

Image vulnerability scanning stays in **`security`** (Trivy / Syft / Grype).

## Runtime detection

Status reports whether a Docker-compatible API is reachable. Absence of a
running daemon is **informational** — static checks still run.

## OrbStack (optional)

```bash
./setup.sh --with orbstack   # Darwin only; omit_from_all
```

Install-only. DOTS never launches OrbStack, changes Docker context, migrates
images, or removes Docker Desktop. OrbStack coexists with Docker Desktop.

See also historical notes in `docs/ORBSTACK_MIGRATION.md` if present.

## Explicit non-goals

Setup / `./dots check containers` will **not**:

- start OrbStack or Docker Desktop
- change Docker context
- `docker pull` / `compose up`
- start Dagger engine
- open VS Code / build Dev Containers
- require a YubiKey
