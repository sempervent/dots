# brew/groups/docs.Brewfile — technical documentation / publishing CLIs
#
# Install-only. DOTS never during setup/check:
#   - rewrite Markdown / README sources
#   - overwrite checked-in diagram artifacts
#   - publish / deploy documentation (GitHub Pages, uploads)
#   - download Chromium/Puppeteer browsers during validation
#   - fetch remote Vale style packages on every check
#   - convert every document automatically
#   - modify ~/.config/vale, ~/.pandoc, or user Typst cache config
#
# Phase 1 docs validators remain in brew/groups/dev.Brewfile:
#   lychee, markdownlint-cli2, cspell
# MkDocs stays Python/site tooling; TeX stays --with tex (Brewfile.tex).

brew "graphviz"
brew "pandoc"
brew "vale"
# mermaid-cli (mmdc): Homebrew formula depends on node only.
# Rendering still needs a local Chromium/Chrome (or PUPPETEER_EXECUTABLE_PATH).
# ./dots check docs never downloads a browser; absent runtime → SKIP_RUNTIME_UNAVAILABLE.
brew "mermaid-cli"
brew "typst"
