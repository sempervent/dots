# AI

AI-related optional components are registry-driven (`configs/components.toml`).
Typical ids include hermes, ollama, llamacpp, drawthings, opencode, codex, cursor,
fluidvoice, ai-server — availability depends on host platform and selection.

```bash
./dots setup --with ai
./dots ai status
./dots models discover
```

`dots-help` does not download models or start servers.
