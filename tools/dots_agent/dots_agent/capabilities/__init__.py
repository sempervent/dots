"""Computed capability view over DOTS registries.

Authorities stay where they are:

* ``configs/skills/manifest.toml`` — skill inventory
* ``configs/agents/mcp-trust.toml`` — MCP inventory and trust
* ``configs/components.toml`` — installable clients and packs
* ``configs/runtime-requirements.toml`` — runtime constraints
* profiles — desired state

This package composes those sources. It does not copy them.
"""

from dots_agent.capabilities.inventory import build_inventory

__all__ = ["build_inventory"]
