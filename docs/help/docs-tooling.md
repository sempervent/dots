# Documentation tooling

```bash
./setup.sh --packages dev,docs
./dots check docs
./dots check docs --offline
./dots check docs status
./dots check docs render
```

Technical documentation CLIs (Graphviz, Pandoc, Vale, Mermaid CLI, Typst) plus
Phase 1 markdownlint/cspell/Lychee. Checks never rewrite sources, publish docs,
or download browsers.

See `docs/using/docs-tooling.md`.
