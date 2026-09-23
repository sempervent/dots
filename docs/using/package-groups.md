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

## known ≠ selected ≠ installed

| Term | Meaning |
|------|---------|
| **known** | Appears in `brew/groups/*.Brewfile` (or a component brewfile) |
| **selected** | Active via profile `packages=` / resolved groups |
| **installed** | Present on the machine |

An installed tool whose owner group is not selected is **INACTIVE**, not
**UNDECLARED**. See [Components](components.md) and
[Packages](../concepts/packages.md).

## Composition

Builtin profiles declare membership in TOML (SoT):

| Profile | Groups (summary) |
|---------|------------------|
| `base` | `core` `modern` |
| `work` | + `workstation` `dev` `data` `geo` `security` `gui` |
| `home` | + `infra` `media` `gui` + `dev` `network` `data` `geo` `security` |
| `server` | `core` `modern` `server` |
| `all` | workstation set + `dev` `security` `network` `data` `geo` |

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

## CLI (read-only)

```bash
./dots packages groups                    # all groups + active marker
./dots packages group geo                 # brewfile, membership, platform map, states
./dots packages plan --profile home       # resolved groups + components + counts
./dots packages plan --profile ./my.toml
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

### mitmproxy (deferred)

`mitmproxy` is **not** in the `network` group. TLS interception is a different
consent surface than ordinary networking CLIs. Future opt-in only — not in this
control-plane release.

## Platform maps

Linux native names live in `configs/packages/{apt,pacman,dnf,xbps}.toml`.
Empty string `""` means unsupported on that manager (SKIP / WARN for optional).
Homebrew uses `brew/groups/<id>.Brewfile` tokens directly.

## See also

- [Packages ownership](../concepts/packages.md)
- [Profiles](../concepts/profiles.md)
- [Components and `--with`](components.md)
- [Extending](extending.md)
