# Components and `--with`

Optional software layers are **components** (and **supergroups** that expand to
components). Select them with profile `with` / `without` or CLI `--with` /
`--without` for **that run**.

Authority: `configs/components.toml`
([generated components](../reference/generated/components.md),
[generated `--with` options](../reference/generated/with-options.md),
[supergroups](../reference/generated/supergroups.md)).

## known ≠ selected ≠ installed

| Term | Meaning |
|------|---------|
| **known** | Package appears in `brew/groups/*.Brewfile` or a component `brewfile=` |
| **selected** | Active package group and/or last-recorded `--with` / profile `with` |
| **installed** | Present on the machine (Homebrew or app) |

Installed optional tools (Herdr, Ollama, mactools formulae, …) can look
“missing from DOTS” when they are only **known** and **installed**, not
**selected**. That is **INACTIVE**, not **UNDECLARED**.

```text
INACTIVE   = known owner(s), none selected, installed
UNDECLARED = no DOTS group/component owner
MANAGED    = selected (desired set) and package-manager owned
```

## Consent (informational last-with)

`~/.config/dots/active-profile` records `DOTS_LAST_WITH_INFO` and
`DOTS_ACTIVE_COMPONENTS` for **read-only discovery** (`./dots packages`,
`./dots components active`).

These fields are **informational only**. They must **not** auto-feed mutating
AI setup. Binary presence ≠ consent. Mutating setup still needs profile
`with` / `./setup.sh --with` (or `./dots setup --with`) for **that** invocation.

## CLI

```bash
./dots components list              # registry + host compatibility
./dots components active            # last selection (informational)
./dots components show mactools     # Brewfile tokens, skills, activate hint
./dots setup --with herdr,mactools
./dots setup --with ai --without cursor
./dots packages status              # MANAGED / INACTIVE / UNDECLARED sections
./dots packages explain dust        # owners + activate hint
```

Docs site: <https://sempervent.github.io/dots/using/components/>

## Upgrade scope (unchanged)

`./dots packages upgrade` upgrades **active managed** outdated packages only.
`./dots packages upgrade --all` is broader (opt-in). Inactive packages are not
in the desired set and are skipped unless `--all`.

## See also

- [Packages ownership model](../concepts/packages.md)
- [Components registry (concept)](../concepts/components.md)
- [Extending](extending.md)
