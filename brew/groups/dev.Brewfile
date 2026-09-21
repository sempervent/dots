# brew/groups/dev.Brewfile — local CI / lint / Rust ergonomics
#
# Install-only. No shell aliases. difftastic / mergiraf are not wired into
# global Git config by DOTS — opt in per-repo if desired:
#   git config diff.external difft
#   git config merge.mergiraf.name mergiraf
#   git config merge.mergiraf.driver "mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L"
#
# mitmproxy intentionally omitted (opt-in later; not in default profiles).

brew "act"
brew "difftastic"
brew "mergiraf"
brew "actionlint"
brew "cargo-nextest"
brew "bacon"
brew "pre-commit"
brew "hadolint"
brew "taplo"
brew "mkcert"
brew "kondo"
