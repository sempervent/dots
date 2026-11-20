# Package groups

Package groups are **capability domains**: portable tool sets selected by a
profile's `packages = […]`. They are distinct from optional **components**
(`with` / `--with`).

```text
PACKAGE GROUPS                         OPTIONAL COMPONENTS
configs/packages/groups.toml           configs/components.toml
brew/groups/<id>.Brewfile              brew/Brewfile.<id>
profile packages = […]                 profile with= / --with
```

Authority for valid group ids is **only** `configs/packages/groups.toml`
([generated reference](../reference/generated/package-groups.md)).

## Groups vs components

| | Package group | Optional component |
|---|---|---|
| Example | `dev`, `geo`, `security` | `herdr`, `ollama`, `mactools` |
| Select | `packages = ["dev"]` | `with = ["herdr"]` / `--with herdr` |
| Activate hint | profile `packages=` | `--with` / profile `with=` |

Do **not** use `./dots setup --with geo` — `geo` is a group, not a component.

## Required vs optional

In `groups.toml`, each group lists **required** and **optional** portable ids.

- **required** → ERROR after install if missing (profile contract)
- **optional** → WARN if missing; may be `""` (SKIP) on some Linux maps

## known ≠ installable ≠ installed ≠ selected

| Term | Meaning |
|------|---------|
| **known** | Appears in `configs/packages/groups.toml`, `brew/groups/*.Brewfile`, or a component registry entry |
| **installable** | DOTS has an authoritative installation mechanism for this package on the current platform |
| **unsupported** | Known capability has no DOTS-supported install route on this platform |
| **installed** | Present on the machine |
| **external** | Present on the machine, not owned by DOTS's selected install mechanism |
| **selected** | Active via profile `packages=` / resolved groups or `with=` |

An installed tool whose owner group is not selected is **INACTIVE**, not
**UNDECLARED**. Direct `./dots install <package>` refuses packages that are
known but **unsupported** on the current platform, while selecting the owning
group (`./dots install <group>`) remains valid when only optional members are
unavailable. See [Components](components.md) and [Packages](../concepts/packages.md).

## Composition

Builtin profiles declare membership in TOML (SoT):

| Profile | Groups (summary) |
|---------|------------------|
| `base` | `core` `modern` |
| `work` | + `workstation` `dev` `docs` `data` `geo` `security` `gui` |
| `home` | + `infra` `media` `gui` + `dev` `docs` `network` `data` `geo` `security` `backup` `hardware` (+ containers/k8s when present) |
| `server` | `core` `modern` `server` (add `backup`/`network`/`hardware` selectively; see examples) |
| `all` | workstation set + `dev` `docs` `security` `network` `data` `geo` `backup` `hardware` (Syncthing remains `omit_from_all`) |

Custom profiles extend and adjust:

```toml
[profile]
name = "geo-dev"
extends = "base"
packages = [
  "core",
  "modern",
  "dev",
  "data",
  "geo",
]
```

Or additive on an existing role:

```toml
[profile]
name = "work-network"
extends = "work"

[packages]
add = ["network"]
```

Examples: `examples/profiles/developer.toml`, `data-geo.toml`, `work-network.toml`.

## Adding capabilities persistently

Use `./dots install` or `./dots profile add` to persist package groups,
components, supergroups, or package-owned tools into a sparse overlay
(`~/.config/dots/profiles/<name>-local.toml`) without editing built-in profiles:

```bash
./dots install dev              # activate package group 'dev' + apply
./dots install hyperfine        # resolves owner group:dev automatically
./dots install geo --no-apply   # persist desired state, apply later
./dots profile remove geo       # remove from desired state (no uninstall)
```

## CLI (read-only)

```bash
./dots packages groups                    # all groups + active marker + supported counts
./dots packages group geo                 # brewfile, membership, platform map, states
./dots packages plan --profile home       # resolved groups + components + counts
./dots packages plan --profile ./my.toml
./dots packages audit [--json]            # offline registry / Brewfile / map integrity audit
```

`plan` never installs, authenticates, or runs `brew outdated`. Reading a plan
that lists AI components is **not** consent to configure them.

## Install-only boundaries

These tools may be installed via groups; DOTS does **not** configure them:

| Tool | Boundary |
|------|----------|
| **Tailscale** | Install only — never `tailscale up` / login / join |
| **mkcert** | Install only — never `mkcert -install` (trust store) |
| **difftastic / mergiraf** | Install only — no global Git config; opt in per-repo |
| **SOPS / age / Cosign** | Install only — no key generation |
| **rclone** | Install only — no remotes / credentials |

### mitmproxy (explicit opt-in component)

`mitmproxy` is **not** in the default `network` group because TLS interception
is a distinct consent surface from ordinary networking CLIs. It is available as
an explicit opt-in component (`--with mitmproxy` or `./dots install mitmproxy`,
`omit_from_all = true`; see [Components reference](../reference/generated/components.md)).

## Platform maps

Linux native names live in `configs/packages/{apt,pacman,dnf,xbps}.toml`.
Empty string `""` means unsupported on that manager (SKIP / WARN for optional).
Homebrew uses `brew/groups/<id>.Brewfile` tokens directly.

## See also

- [Packages ownership](../concepts/packages.md)
- [Profiles](../concepts/profiles.md)
- [Components and `--with`](components.md)
- [Extending](extending.md)
