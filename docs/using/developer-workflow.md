# Developer workflow and inspection tooling

Phase 4 adds high-leverage Git, search, log, and API tools **without** changing
default Git behavior, rewriting repositories, intercepting traffic, or trusting
proxy certificates.

## Install

```bash
# CLIs (jj, git-town, git-filter-repo, git-sizer, ast-grep, lnav):
./setup.sh --packages core,modern

# Opt-in HTTP interception (never in default profiles):
./setup.sh --with mitmproxy

# Bruno + Proxyman GUIs (Darwin, via mactools omit_from_all):
./setup.sh --with mactools
```

## Diagnostics

```bash
./dots check dev          # presence/version report (non-mutating)
./dots check dev repo     # optional read-only git-sizer
```

## Git evolution

| Tool | Role |
|------|------|
| **git** | Authoritative / default VCS (unchanged) |
| lazygit | Existing Git TUI (`modern`) |
| **jj** | Additive Jujutsu CLI — never auto-inits or converts repos |
| **git-town** | Branch lifecycle automation — install-only; no aliases |
| **git-filter-repo** | **Destructive** history rewrite — never run by DOTS |
| **git-sizer** | Read-only repository size diagnostics |

DOTS never creates `.jj/`, never writes git-town config, and never rewrites history.

## Structural search

`ast-grep` (`sg`) is for structural search/preview. Mutation (`-U` / rewrite)
is **explicit user invocation only**.

## Logs

`lnav` is interactive log exploration. DOTS never scrapes system/user logs
during setup or `./dots check`.

## HTTP / API

| Tool | Role |
|------|------|
| xh / curl | Direct request CLIs (already present) |
| Bruno | Collections / API workspace GUI (mactools) |
| mitmproxy | Terminal/scriptable interception (`--with mitmproxy`) |
| Proxyman | Optional macOS GUI interception (mactools) |

Install does **not** start proxies, install/trust CAs, or change system/browser
proxy settings. No Bruno/Proxyman auto-launch or launch-at-login.

## Explicit non-goals

- Convert repositories to jj
- Change Git aliases / merge / rebase policy
- Run `git filter-repo` or ast-grep rewrites
- Start mitmproxy or trust interception certificates
- Launch Bruno / Proxyman
- Require GitHub / Bruno / Proxyman accounts
- Require a YubiKey
