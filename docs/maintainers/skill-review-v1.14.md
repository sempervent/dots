# Skill review for DOTS v1.14

Reviewed 2026-11-24. Scripts inside candidate skills were not executed.

## Accepted

| Skill | Source | Ref | License | Why |
| --- | --- | --- | --- | --- |
| security-audit | cloudflare/security-audit-skill | c1c8a8c1471069fb0e188eeaff69b8e8db6564a8 | MIT | Source-first defensive audit. Instruction plus an optional validator script. Engineering pack only. |
| agents-md | getsentry/skills | a582c51ee29d0f35e6ac321340796f77d43da733 | Apache-2.0 | Keep AGENTS.md short and reference-backed. Instruction only. |
| code-simplifier | getsentry/skills | a582c51ee29d0f35e6ac321340796f77d43da733 | Apache-2.0 | Reduce generated complexity without changing behavior. Instruction only. |
| hf-cli | huggingface/skills | d67b12054923df5bbfa07c5ff1331412deebdf4f | Apache-2.0 | Hugging Face CLI operations for models, datasets, Spaces, and jobs. AI pack only. |
| frontend-design | anthropics/skills | e4bb5d960d87126ff3b3a8af1a104b7db67560ba | Apache-2.0 | Visual direction. Optional frontend pack, not the ai supergroup and not headless profiles. |
| skill-authoring | skills/skill-authoring | dots-v1.14.0 | MIT | DOTS-owned authoring policy. Written for this repo; not copied from an upstream skill. |

## Rejected

| Candidate | Source | Why |
| --- | --- | --- |
| web-design-guidelines | vercel-labs/agent-skills @ 5a37a6329fbad3666c3207392a6a7c0110e92efb | Repository has no LICENSE and package.json license is unset. Not curated until a license is declared. |
| remaining huggingface/skills catalog | huggingface/skills | hf-cli covers the useful workstation surface. The rest of the catalog is out of scope. |
| GitHub MCP | official GitHub remote | Not added. Remote write and OAuth behavior were not re-verified against a pinned release in this change, so it stays undiscovered-only. |
| filesystem MCP, shell MCP | — | DOTS already has local tools and a sandbox. These do not enter the safe default set. |

Draw Things is a curated local MCP because `tools/drawthings_mcp/server.py` is the in-repo stdio bridge. It writes images, so `safe_default` is false and safe mode does not load it.
