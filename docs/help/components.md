# Components

Optional features are declared in `configs/components.toml` and selected via
profile `with=` or:

```bash
./dots setup --with lsp
./dots setup --with herdr,hermes
./dots components list
./dots components active
./dots components show lsp
```

Presence of a binary ≠ authorization. Consent comes from profile / `--with` only.
