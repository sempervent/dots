"""Local capability registry loader and quality-floor checks."""

from __future__ import annotations

import re
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any


TIER_ORDER = ["unrated", "basic", "capable", "strong", "frontier"]


@dataclass
class FamilyRule:
    id_pattern: str
    quality: str
    task_classes: list[str]
    source: str
    reviewed_date: str
    notes: str = ""

    def matches(self, model_id: str) -> bool:
        return re.search(self.id_pattern, model_id, re.IGNORECASE) is not None


def load_capabilities(path: Path) -> tuple[list[FamilyRule], list[str]]:
    if not path.is_file():
        return [], list(TIER_ORDER)
    with path.open("rb") as fh:
        data = tomllib.load(fh)
    tiers = list(data.get("tiers", {}).get("order") or TIER_ORDER)
    rules: list[FamilyRule] = []
    for row in data.get("families") or []:
        if not isinstance(row, dict):
            continue
        rules.append(
            FamilyRule(
                id_pattern=str(row.get("id_pattern") or ""),
                quality=str(row.get("quality") or "unrated"),
                task_classes=[str(x) for x in (row.get("task_classes") or [])],
                source=str(row.get("source") or ""),
                reviewed_date=str(row.get("reviewed_date") or ""),
                notes=str(row.get("notes") or ""),
            )
        )
    return rules, tiers


def quality_of(model_id: str, rules: list[FamilyRule]) -> str:
    for rule in rules:
        if rule.id_pattern and rule.matches(model_id):
            return rule.quality if rule.quality in TIER_ORDER else "unrated"
    return "unrated"


def tier_index(quality: str, tiers: list[str]) -> int:
    q = quality if quality in tiers else "unrated"
    try:
        return tiers.index(q)
    except ValueError:
        return 0


def meets_floor(quality: str, floor: str, tiers: list[str]) -> bool:
    if floor in ("", "any", "unrated"):
        return True
    # unrated never satisfies an explicit higher floor
    if quality == "unrated" and floor not in ("unrated", "any", ""):
        return False
    return tier_index(quality, tiers) >= tier_index(floor, tiers)


def supports_task(model_id: str, task_type: str, rules: list[FamilyRule]) -> bool | None:
    """True/False if known; None if unrated (unknown)."""
    for rule in rules:
        if rule.id_pattern and rule.matches(model_id):
            if not task_type:
                return True
            return task_type in rule.task_classes
    return None
