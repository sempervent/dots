"""dots-expert MCP — billable remote consultation (no filesystem tools)."""

from __future__ import annotations

import json
import os

from mcp.server.fastmcp import FastMCP

from dots_agent.budget import Budget
from dots_agent.config import load_config
from dots_agent.expert.consult import consult_expert
from dots_agent.ledger import RunLedger

mcp = FastMCP("dots-expert")

# Process-local budget for MCP sessions (harness may pass tighter limits via env)
_budget: Budget | None = None


def _get_budget() -> Budget:
    global _budget
    if _budget is None:
        cfg = load_config()
        _budget = Budget(
            session_budget_usd=float(
                os.environ.get("DOTS_AGENT_BUDGET", cfg.session_budget_usd)
            ),
            max_remote_calls=int(
                os.environ.get("DOTS_AGENT_MAX_REMOTE", cfg.max_remote_calls)
            ),
        )
    return _budget


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "openWorldHint": True,
    }
)
def consult_expert_tool(
    model: str,
    question: str,
    context: str = "",
    desired_output: str = "concise actionable advice",
    max_cost_usd: float = 0.5,
    estimated_cost_usd: float | None = None,
) -> str:
    """Ask a remote expert via LiteLLM → OpenRouter under the DOTS session budget.

    This tool has NO filesystem, git, or shell access. The local agent must apply advice.
    Prefer find_model (model-scout) before calling this tool.
    """
    cfg = load_config()
    local_only = os.environ.get("DOTS_AGENT_LOCAL", "").strip() in ("1", "true", "yes")
    approve = os.environ.get("DOTS_AGENT_APPROVE_EXPENSIVE", "").strip() in (
        "1",
        "true",
        "yes",
    )
    result = consult_expert(
        cfg=cfg,
        budget=_get_budget(),
        model=model,
        question=question,
        context=context,
        desired_output=desired_output,
        max_cost_usd=max_cost_usd,
        estimated_cost_usd=estimated_cost_usd,
        allow_network=not local_only,
        approve_expensive=approve,
        interactive=False,
    )
    # Ledger (metadata only)
    try:
        ledger = RunLedger(cfg.runs_dir(), run_id=os.environ.get("DOTS_AGENT_RUN_ID"))
        ledger.cost(
            model=model,
            estimated_usd=result.get("estimated_cost_usd"),
            actual_usd=result.get("actual_cost_usd") or result.get("charged_usd"),
            ok=result.get("ok"),
            via="consult_expert",
        )
        ledger.event("consult_expert", ok=bool(result.get("ok")), model=model)
    except Exception:
        pass
    # Never echo env secrets
    return json.dumps(result, indent=2)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
