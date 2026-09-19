# OrbStack ↔ Docker Desktop migration (manual, reversible)

DOTS may install **OrbStack** via `--with mactools`. That does **not** remove
Docker Desktop or migrate workloads. Treat migration as a deliberate project.

## Inventory (read-only)

```bash
./scripts/mactools/docker-orbstack-audit.sh

docker context ls
docker context show
docker ps -a
docker images
docker volume ls
docker network ls
docker system df
```

Repo note: Homebrew already installs the Docker **CLI** (`docker`,
`docker-compose`, `docker-buildx`) via the infra/core Brewfiles. OrbStack
provides an alternative engine/context; the CLI remains useful either way.

## Risks / differences to verify empirically

Do not assume breakage — check your projects against:

| Area | Why it matters |
|------|----------------|
| VM / virt backend | Resource limits, CPU/RAM caps |
| Filesystem mounts | Bind-mount performance and permissions |
| Networking | Host ports, DNS, `host.docker.internal` |
| Docker context / socket | Which engine `docker` talks to |
| Volumes | Named volume data location and persistence |
| Credential helpers | Registry login stores |
| Compose / K8s extras | Optional Desktop features vs OrbStack |

## Safe migration path

1. **Inventory** with `./scripts/mactools/docker-orbstack-audit.sh`.
2. List **named volumes** that are not reproducible from Git/Compose.
3. **Backup** non-reproducible data (volume tar, DB dumps, `.env` offline).
4. **Stop** workloads cleanly (`compose down` / stop containers).
5. Ensure **OrbStack** is installed (`./setup.sh --with mactools` or cask) and running.
6. Inspect **contexts**: `docker context ls` — select OrbStack’s context when ready.
7. Verify CLI: `docker info`, `docker run --rm hello-world`.
8. **Rebuild** reproducible stacks from Compose/Dockerfiles.
9. **Restore** volume data only where required; re-test.
10. Run representative project smoke tests.
11. **Only then** consider quitting Docker Desktop. Uninstall is optional and manual.

## Rollback

1. Switch Docker context back to Docker Desktop (`docker context use …`).
2. Start Docker Desktop from `/Applications`.
3. Re-run `docker ps` / Compose projects.
4. Restore volume backups if the OrbStack experiment mutated data.

```bash
docker context ls
# docker context use desktop-linux   # typical Desktop context name — verify on your machine
```

## What DOTS will not do

- Uninstall Docker Desktop
- Delete volumes or images
- Rewrite Compose files
- Change default context without your action

## See also

- `docs/MACTOOLS.md` — mactools package set
- `brew/Brewfile.mactools` — `cask "orbstack"`
