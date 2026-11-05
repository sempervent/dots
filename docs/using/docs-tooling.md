# Technical documentation toolchain

Package group **`docs`** installs Graphviz, Pandoc, Vale, Mermaid CLI, and Typst.
Phase 1 validators (`markdownlint-cli2`, `cspell`, `lychee`) remain owned by
package group **`dev`** — they are not duplicated into `docs`.

MkDocs remains the authoritative documentation **site** generator. The `tex`
component (`--with tex`) remains the TeXlive environment. Pandoc may use TeX
when present but does **not** require it for baseline Markdown → HTML.

## Install

```bash
./setup.sh --packages core,modern,dev,docs
# work / home / all profiles already include docs (+dev)
```

## Tool roles

| Tool | Role |
|------|------|
| MkDocs | Documentation site (existing; not replaced) |
| markdownlint-cli2 | Markdown structure/style (`dev`) |
| cspell | Spelling (`dev`) |
| Vale | Prose / terminology (`docs`) |
| Lychee | Link checking (`dev`) |
| Graphviz (`dot`) | Graph / architecture diagrams |
| Mermaid CLI (`mmdc`) | Mermaid diagram rendering |
| Pandoc | Document conversion |
| Typst | Standalone technical publishing (PDF) |
| TeX (`--with tex`) | TeXlive — complementary, not folded into `docs` |

## Diagnostics

```bash
./dots check docs              # full pipeline
./dots check docs --offline    # no external HTTP
./dots check docs status       # tooling inventory
./dots check docs render       # non-mutating previews → temp
./dots check docs render --output /tmp/dots-docs-preview
./dots check docs gate         # Vale + diagram/publish stages
./dots check docs examples
```

### Default pipeline stages

1. markdownlint-cli2
2. cspell
3. Vale
4. Lychee (external links unless `--offline`)
5. Graphviz validation (temp SVG; no overwrite)
6. Mermaid validation when a local browser runtime is available
7. Typst validation when `*.typ` sources exist
8. Pandoc capability (fixture Markdown → HTML)

`./dots check fast` stays cheap: markdownlint + cspell + offline lychee — **no**
Vale or diagram rendering.

### What default checks never do

- Rewrite Markdown / README sources
- Overwrite checked-in diagram artifacts
- Publish / deploy (GitHub Pages, uploads, release attachments)
- Download Chromium / Puppeteer browsers
- Call mermaid.ink or other remote renderers
- Auto-convert every document
- Modify `~/.config/vale`, `~/.pandoc`, or user Typst configuration
- Fetch remote images/CSS/JS for fixtures
- Require GitHub auth, publishing credentials, or a YubiKey

## Vale policy

Project config: `.vale.ini` + `.vale/styles/DOTS/` (vendor/local only).

The initial style pack is **intentionally conservative**: terminology swaps
(e.g. `Github` → `GitHub`) and obvious repetition. Spelling stays with cspell.
Styles are not downloaded from the network during checks. Source is never
uploaded.

Vocabulary: `.vale/styles/config/vocabularies/DOTS/accept.txt`.

## Graphviz

Discovers repository `*.dot` / `*.gv` (excludes vendor, fixtures, generated).
Validates with Graphviz SVG render to a temporary file. Checked-in artifacts are never overwritten.
No sources → `SKIP: no Graphviz diagrams`.

## Mermaid CLI and browser runtime

Homebrew `mermaid-cli` depends on **Node** only. Rendering still needs a local
Chromium/Chrome (or `PUPPETEER_EXECUTABLE_PATH` / `DOTS_MERMAID_EXECUTABLE`).

| Situation | Behavior |
|-----------|----------|
| `mmdc` missing | `SKIP` |
| `mmdc` present, no browser | `SKIP_RUNTIME_UNAVAILABLE` (not a silent PASS) |
| Browser present | Local render to temp |

`./dots check docs` **never** downloads a browser package. Offline rendering
works only when a local runtime already exists. DOTS does not use remote Mermaid
services.

Heavy browser runtimes are **not** hard requirements of `base`/`server` profiles.
The `docs` group installs the CLI; render runtime remains optional.

## Pandoc

Baseline proof: Markdown → HTML (no remote assets). PDF requires an external
engine (pdfLaTeX, XeLaTeX, Typst, …). Status reports:

```text
Pandoc PDF backend: AVAILABLE (…) / NOT CONFIGURED
```

## Typst

Discovers `*.typ`. Compiles to temporary PDF. Dependency-free fixtures are the
baseline. Documents that import `@preview` packages need network/package cache —
DOTS reports failure rather than surprise-downloading during ordinary checks.

## Generated artifacts

| Action | Output |
|--------|--------|
| Normal `check docs` | Temporary only |
| `check docs render` | Temp dir (or explicit `--output DIR`) |
| Publishing | **Out of scope** for Phase 8 |

Test fixtures live under `scripts/tests/fixtures/docs/` and are never treated as
repository diagram sources during discovery.

## Related

- `docs/using/local-ci.md` — Phase 1 validators and `check fast`
- MkDocs: `mkdocs.yml`
- TeX: `./setup.sh --with tex`
