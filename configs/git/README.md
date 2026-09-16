# configs/git/README.md — Git identity separation

DOTS manages **shared ergonomics** only (`~/.config/git/common`).

Identity stays machine-local:

| File | Purpose |
|------|---------|
| `~/.config/git/common` | aliases, editor, rerere, push/pull (managed link) |
| `~/.config/git/personal` | personal `user.name` / `user.email` (created once from template) |
| `~/.config/git/work` | work identity (created once from template) |
| `~/.config/git/config` | includes common + includeIf rules (created once, never overwritten) |

Default includeIf directories (edit `~/.config/git/config` to match your layout):

```ini
[include]
    path = ~/.config/git/common

[includeIf "gitdir:~/dev/"]
    path = ~/.config/git/personal

[includeIf "gitdir:~/work/"]
    path = ~/.config/git/work
```

Bootstrap never replaces an existing valid `user.email` in your global config.
If you already have `~/.gitconfig`, DOTS leaves it alone and only ensures the
XDG layout exists for new machines.
