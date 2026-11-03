# Architecture diagrams

Explorable Archify diagrams for the current DOTS agent stack. Open a diagram to
pan/zoom, switch light/dark, follow guided views, and export SVG/PNG.

These pages describe the **live** system documented on GitHub Pages — not a
frozen release snapshot. Narrative overview:
[Agent architecture](architecture.md).

| Diagram | What it shows |
|---------|----------------|
| [System overview](../diagrams/dots-agent-system-overview.html) | Local Pi, sandbox, scout/evals, budget/LiteLLM, OpenRig, autonomy |
| [Trust boundary](../diagrams/dots-agent-trust-boundary.html) | Safe default, worktree, env scrub, MCP allowlist, unsafe-host opt-in |
| [Routing and eval](../diagrams/dots-agent-routing-eval.html) | Local-first → Wilson floor → expected cost → remote consult |
| [OpenRig teams](../diagrams/dots-openrig-teams.html) | DOTS vs OpenRig ownership; seat projection into sandboxed Pi |
| [Autonomy ladder](../diagrams/dots-agent-autonomy-ladder.html) | Structural fingerprint → recovery ladder → attention / verified |
| [OpenRig install](../diagrams/dots-openrig-install.html) | `setup --with openrig` → fnm → Node → npm → CLI → ABI → doctor |

## Sources

JSON specifications for regeneration with Archify live beside the HTML under
`docs/diagrams/src/` (for example
[`dots-agent-system-overview.architecture.json`](../diagrams/src/dots-agent-system-overview.architecture.json)).
Delivered HTML is the reader artifact — edit the JSON and re-deliver rather than
hand-editing the HTML.
