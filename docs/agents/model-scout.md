# Model Scout

Read-only MCP server: `dots-model-scout`.

## Tools

| Tool | Purpose |
|------|---------|
| `find_model` | Cheapest qualifying OpenRouter model |
| `compare_models` | Cost compare explicit ids |
| `estimate_cost` | Price estimate for one model |
| `explain_choice` | Deterministic why/why-not |

## Catalog

Authenticated (preferred):

```text
GET https://openrouter.ai/api/v1/models/user
```

Public fallback when `OPENROUTER_API_KEY` is unset:

```text
GET https://openrouter.ai/api/v1/models
```

Cache: `~/.cache/dots/agents/openrouter-models.json` (default TTL 15m).

## Selection order

1. Account availability (user catalog when keyed)
2. Required modality (vision)
3. Required context length
4. Required API/tool parameters
5. Local capability quality floor (`configs/agents/model-capabilities.toml`)
6. Maximum estimated request cost
7. Sort remaining by estimated task cost

## Cost formula

```text
estimated_cost =
    input_tokens  * pricing.prompt
  + output_tokens * pricing.completion
```

Missing price metadata → cannot auto-select (never treat as free).

## Provider routing

After a **model** is selected, OpenRouter provider preference uses
`provider.sort = "price"` (verified OpenRouter provider routing docs).
Model selection ≠ provider selection.

## Developer: MCP Inspector (optional)

Phase 1 does **not** install a persistent Inspector service. For local schema
checks without a browser:

```bash
npx -y @modelcontextprotocol/inspector --cli "$(pwd)/scripts/dots-model-scout" \
  --method tools/list
npx -y @modelcontextprotocol/inspector --cli "$(pwd)/scripts/dots-expert" \
  --method tools/list
```

Authoritative Pi discovery after setup:

```bash
pi mcp list
```

Fuller DOTS developer-tool integration is Phase 2.
