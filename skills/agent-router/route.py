#!/usr/bin/env python3
"""Deterministic DOTS agent-router classifier (no embeddings / LLM calls).

Used by scripts/router_policy_test.sh and readable as the executable form of
skills/agent-router/SKILL.md policy.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass


DEST_DIRECT = "hermes_direct"
DEST_LOCAL = "local"
DEST_ARCHIFY = "archify"
DEST_OPENCODE = "opencode"
DEST_CODEX = "codex"
DEST_CURSOR = "cursor"
DEST_DRAWTHINGS = "drawthings"
DEST_IMAGES = "images"


@dataclass
class Decision:
    destination: str
    category: str
    reason: str
    cwd_required: bool
    escalation: str | None
    override: bool
    degraded: bool = False
    note: str | None = None

    def to_dict(self) -> dict:
        return asdict(self)


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


OVERRIDE_PATTERNS: list[tuple[re.Pattern[str], str, str]] = [
    # Cursor ONLY via explicit user request — never auto-selected
    (re.compile(r"\b(use|with|via|through)\s+cursor\b|\bcursor\s+to\b|\bkeep this on cursor\b"), DEST_CURSOR, "coding-cursor"),
    (re.compile(r"\b(use|with|via|through)\s+codex\b|\bcodex\s+to\b|\bkeep this on codex\b"), DEST_CODEX, "coding-frontier"),
    (re.compile(r"\b(use|with|via)\s+opencode\b|\bopencode\s+to\b"), DEST_OPENCODE, "coding-local"),
    (re.compile(r"\b(use|with|via)\s+draw\s*things\b|\bgenerate (this |an? )?(image|png|jpg).*\bdraw\b"), DEST_DRAWTHINGS, "visual"),
    (re.compile(r"\b(use|with|via)\s+archify\b|\banalyze (the )?architecture with archify\b"), DEST_ARCHIFY, "architecture"),
    (re.compile(r"\bkeep (this |it )?local\b|\bno cloud\b|\bdon'?t (use|escalate to) codex\b"), DEST_OPENCODE, "coding-local"),
]


def apply_override(text: str) -> Decision | None:
    n = _norm(text)
    for pat, dest, cat in OVERRIDE_PATTERNS:
        if pat.search(n):
            # "keep this local and inspect this repo" → opencode, not cloud
            if dest == DEST_OPENCODE and "keep" in n and "local" in n:
                return Decision(
                    destination=DEST_OPENCODE,
                    category=cat,
                    reason="user override: keep local (no Codex escalation)",
                    cwd_required=True,
                    escalation=None,
                    override=True,
                )
            cwd_req = dest in {DEST_OPENCODE, DEST_CODEX, DEST_CURSOR, DEST_ARCHIFY}
            return Decision(
                destination=dest,
                category=cat,
                reason=f"user override → {dest}",
                cwd_required=cwd_req,
                escalation=None,
                override=True,
            )
    return None


def classify(text: str, *, available: set[str] | None = None) -> Decision:
    """Classify a user request into a destination.

    ``available`` is a set of destination ids that exist on this machine.
    Missing destinations trigger graceful degradation notes.
    """
    available = available or {
        DEST_DIRECT,
        DEST_LOCAL,
        DEST_ARCHIFY,
        DEST_OPENCODE,
        DEST_CODEX,
        DEST_CURSOR,
        DEST_DRAWTHINGS,
        DEST_IMAGES,
    }

    override = apply_override(text)
    if override:
        return degrade(override, available)

    n = _norm(text)

    # Deterministic image toolkit (NOT generative)
    image_det = any(
        k in n
        for k in (
            "resize",
            "convert svg",
            "svg to png",
            "webp to png",
            "png to jpg",
            "jpg to png",
            "remove metadata",
            "strip exif",
            "show exif",
            "exif",
            "compress this png",
            "optimize png",
            "pngquant",
            "imagemagick",
            "trim ",
            "crop ",
        )
    ) and any(k in n for k in ("png", "jpg", "jpeg", "webp", "svg", "image", "gif", "tiff"))
    # Explicit generate/create image → Draw Things
    generative = any(
        k in n
        for k in (
            "generate an image",
            "generate a image",
            "create an image",
            "create a image",
            "draw an image",
            "img2img",
            "image of ",
            "picture of ",
            "synthwave image",
            "generate this with draw",
        )
    ) or (re.search(r"\b(generate|create|paint|render)\b.*\b(image|picture|illustration|artwork)\b", n) is not None)

    if image_det and not generative:
        d = Decision(
            destination=DEST_IMAGES,
            category="visual",
            reason="deterministic image conversion/optimization/metadata",
            cwd_required=False,
            escalation=None,
            override=False,
        )
        return degrade(d, available)

    if generative:
        d = Decision(
            destination=DEST_DRAWTHINGS,
            category="visual",
            reason="generative image request",
            cwd_required=False,
            escalation=None,
            override=False,
        )
        return degrade(d, available)

    # Architecture
    if any(
        k in n
        for k in (
            "architecture",
            "system decomposition",
            "dependency map",
            "dependency/structure",
            "design review",
            "architectural diagram",
            "analyze the architecture",
            "unfamiliar codebase",
        )
    ):
        d = Decision(
            destination=DEST_ARCHIFY,
            category="architecture",
            reason="architecture / structure analysis",
            cwd_required=True,
            escalation=None,
            override=False,
            note="If followed by implementation: Archify → Hermes synthesis → OpenCode/Codex",
        )
        return degrade(d, available)

    # Frontier coding
    frontier = any(
        k in n
        for k in (
            "difficult",
            "multi-package refactor",
            "multi package refactor",
            "substantial refactor",
            "hard debugging",
            "security-sensitive",
            "security sensitive",
            "consequential",
            "architecture-to-implementation",
            "escalate",
            "frontier",
        )
    ) or re.search(r"\b(large|complex)\s+(refactor|rewrite|migration)\b", n) is not None

    if frontier:
        d = Decision(
            destination=DEST_CODEX,
            category="coding-frontier",
            reason="difficult / high-consequence coding task",
            cwd_required=True,
            escalation=None,
            override=False,
        )
        return degrade(d, available)

    # Local coding
    coding = any(
        k in n
        for k in (
            "inspect this repository",
            "inspect this repo",
            "failing tests",
            "fix the bug",
            "bug fix",
            "refactor",
            "implement",
            "write a test",
            "run the tests",
            "code change",
            "edit the code",
            "local coding",
        )
    ) or re.search(r"\b(fix|debug|patch|modify)\b.*\b(code|repo|test|file)\b", n) is not None

    if coding:
        d = Decision(
            destination=DEST_OPENCODE,
            category="coding-local",
            reason="routine repository coding / inspection",
            cwd_required=True,
            escalation=DEST_CODEX if DEST_CODEX in available else None,
            override=False,
            note="Escalate to Codex only on failure/timeout/inability/high consequence/user request",
        )
        return degrade(d, available)

    # Local reasoning
    local = any(
        k in n
        for k in (
            "summarize",
            "summary",
            "extract",
            "first-pass",
            "first pass",
            "private",
            "low-cost",
            "routine text",
            "transform this text",
        )
    )
    if local:
        d = Decision(
            destination=DEST_LOCAL,
            category="local",
            reason="local/low-cost reasoning via Hermes/Ollama",
            cwd_required=False,
            escalation=None,
            override=False,
        )
        return degrade(d, available)

    # Default: Hermes direct
    d = Decision(
        destination=DEST_DIRECT,
        category="direct",
        reason="conversation / planning / orchestration without specialized backend",
        cwd_required=False,
        escalation=None,
        override=False,
    )
    return degrade(d, available)


def degrade(decision: Decision, available: set[str]) -> Decision:
    if decision.destination in available:
        return decision

    # Cursor: never silently substitute another cloud coding provider (work policy).
    if decision.destination == DEST_CURSOR:
        return Decision(
            destination=DEST_DIRECT,
            category=decision.category,
            reason=decision.reason,
            cwd_required=False,
            escalation=None,
            override=decision.override,
            degraded=True,
            note="Cursor unavailable; report unavailable — do not silently substitute Codex/OpenCode",
        )

    # Graceful degradation map
    fallbacks = {
        DEST_CODEX: (DEST_OPENCODE, "Codex unavailable; using OpenCode; no cloud escalation"),
        DEST_DRAWTHINGS: (DEST_DIRECT, "Draw Things unavailable; report missing generative backend"),
        DEST_ARCHIFY: (DEST_DIRECT, "Archify unavailable; Hermes performs normal analysis"),
        DEST_OPENCODE: (DEST_DIRECT, "OpenCode unavailable; Hermes can only advise"),
        DEST_IMAGES: (DEST_DIRECT, "images toolkit unavailable; report missing CLI tools"),
        DEST_LOCAL: (DEST_DIRECT, "local path unavailable; Hermes direct"),
    }
    fb, note = fallbacks.get(decision.destination, (DEST_DIRECT, "destination unavailable"))
    if fb not in available:
        fb = DEST_DIRECT
    return Decision(
        destination=fb,
        category=decision.category,
        reason=decision.reason,
        cwd_required=decision.cwd_required if fb in {DEST_OPENCODE, DEST_CODEX, DEST_CURSOR, DEST_ARCHIFY} else False,
        escalation=None,
        override=decision.override,
        degraded=True,
        note=note,
    )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="DOTS agent-router policy classifier")
    p.add_argument("prompt", nargs="?", help="User prompt to classify")
    p.add_argument("--json", action="store_true", help="JSON output")
    p.add_argument(
        "--available",
        default="",
        help="Comma-separated available destinations (default: all)",
    )
    args = p.parse_args(argv)
    if not args.prompt:
        p.error("prompt required")
    avail = None
    if args.available.strip():
        avail = {x.strip() for x in args.available.split(",") if x.strip()}
    decision = classify(args.prompt, available=avail)
    if args.json:
        print(json.dumps(decision.to_dict(), indent=2))
    else:
        print(f"{decision.destination}\t{decision.category}\t{decision.reason}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
