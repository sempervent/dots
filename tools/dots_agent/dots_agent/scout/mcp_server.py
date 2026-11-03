"""dots-model-scout MCP — read-only OpenRouter catalog selection."""

from __future__ import annotations

import json
from typing import Any

from mcp.server.fastmcp import FastMCP

from dots_agent.config import load_config
from dots_agent.scout.catalog import fetch_catalog
from dots_agent.scout.select import Requirements, explain_choice, select_model
from dots_agent.scout.cost import estimate_cost

mcp = FastMCP("dots-model-scout")


def _catalog(*, allow_network: bool = True, force_live: bool = False):
    cfg = load_config()
    return fetch_catalog(
        cache_dir=cfg.cache_dir(),
        catalog_url=cfg.catalog_url,
        catalog_url_public=cfg.catalog_url_public,
        ttl_seconds=cfg.catalog_cache_ttl,
        allow_network=allow_network,
        force_live=force_live,
    )


@mcp.tool(
    annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": True}
)
def find_model(
    task_type: str = "general",
    languages: list[str] | None = None,
    context_tokens: int = 8000,
    expected_output_tokens: int = 2000,
    requires_tools: bool = False,
    requires_structured_output: bool = False,
    requires_vision: bool = False,
    quality_floor: str = "strong",
    max_cost_usd: float = 0.5,
) -> str:
    """Select the cheapest OpenRouter model that meets structured requirements.

    Queries MODEL METADATA only — does not send task text or source code to any model.
    """
    cfg = load_config()
    cat = _catalog()
    req = Requirements(
        task_type=task_type,
        languages=list(languages or []),
        context_tokens=context_tokens,
        expected_output_tokens=expected_output_tokens,
        requires_tools=requires_tools,
        requires_structured_output=requires_structured_output,
        requires_vision=requires_vision,
        quality_floor=quality_floor,
        max_cost_usd=max_cost_usd,
    )
    result = select_model(
        cat.models,
        req,
        capabilities_path=cfg.capabilities_path(),
        max_candidates=cfg.max_candidates,
        provider_sort=cfg.provider_sort,
    )
    result["catalog"] = {
        "source": cat.source,
        "age_seconds": int(cat.age_seconds),
        "stale": cat.stale,
        "url": cat.url,
    }
    return json.dumps(result, indent=2)


@mcp.tool(
    annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": True}
)
def compare_models(
    model_ids: list[str],
    context_tokens: int = 8000,
    expected_output_tokens: int = 2000,
) -> str:
    """Compare estimated costs for explicit model ids (metadata only)."""
    cat = _catalog()
    by_id = {str(m.get("id")): m for m in cat.models}
    rows = []
    for mid in model_ids:
        m = by_id.get(mid)
        if not m:
            rows.append({"model": mid, "ok": False, "reason": "not_in_catalog"})
            continue
        est = estimate_cost(
            m, input_tokens=context_tokens, output_tokens=expected_output_tokens
        )
        rows.append({"model": mid, **est})
    return json.dumps({"comparisons": rows, "catalog_source": cat.source}, indent=2)


@mcp.tool(
    name="estimate_cost",
    annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False},
)
def estimate_cost_tool(
    model: str,
    context_tokens: int = 8000,
    expected_output_tokens: int = 2000,
) -> str:
    """Estimate request cost for one model from cached/live catalog pricing."""
    cat = _catalog(allow_network=True)
    m = next((x for x in cat.models if str(x.get("id")) == model), None)
    if not m:
        return json.dumps({"ok": False, "reason": "not_in_catalog", "model": model})
    return json.dumps(
        {
            "model": model,
            **estimate_cost(
                m, input_tokens=context_tokens, output_tokens=expected_output_tokens
            ),
        },
        indent=2,
    )


@mcp.tool(
    name="explain_choice",
    annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": True},
)
def explain_choice_tool(
    task_type: str = "debugging",
    context_tokens: int = 18000,
    expected_output_tokens: int = 4000,
    requires_tools: bool = True,
    quality_floor: str = "strong",
    max_cost_usd: float = 0.5,
    model: str | None = None,
) -> str:
    """Deterministic explanation of why a model won or was excluded (no completion)."""
    cfg = load_config()
    cat = _catalog()
    req = Requirements(
        task_type=task_type,
        context_tokens=context_tokens,
        expected_output_tokens=expected_output_tokens,
        requires_tools=requires_tools,
        quality_floor=quality_floor,
        max_cost_usd=max_cost_usd,
    )
    return json.dumps(
        explain_choice(
            cat.models, req, capabilities_path=cfg.capabilities_path(), model_id=model
        ),
        indent=2,
    )


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
