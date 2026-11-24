# Security review

Review a candidate skill before it becomes desired state.

1. Read `SKILL.md`, `scripts/`, `references/`, and `assets/`.
2. Record the license and the reviewed git ref.
3. Run static review. Do not execute bundled scripts.
4. Reject `curl | sh`, unexpected shell execution, path escapes, and unpinned `main`.
5. Stage an update beside the installed copy. Replace the installed copy only after validation succeeds.

`dots skills update NAME --plan` prints the diff and review. `--yes` applies a candidate that already passed.

Removing a skill from a profile does not delete the installed files.
