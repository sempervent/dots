# configs/mactools — portable GUI app exports (opt-in, reviewed before commit)
#
# DOTS does not scrape ~/Library or live application databases.
# Export via each app's supported UI (or documented CLI), then ingest with:
#
#   ./scripts/mactools/export-configs.sh <tool> <exported-file>
#   ./scripts/mactools/import-configs.sh <tool>
#
# See docs/MACTOOLS.md for status of each application.
#
# Tracked: README files and documented procedures.
# Untracked by default: *.plist / *.kmmacros / Hazel rule dumps (may contain paths).
