"""JSON exact / schema scorers (stdlib only)."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def _load_json(path: Path) -> tuple[Any | None, str | None]:
    if not path.is_file():
        return None, f"missing:{path.name}"
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except json.JSONDecodeError as exc:
        return None, f"invalid_json:{exc}"


def _type_ok(value: Any, expected_type: str) -> bool:
    mapping = {
        "object": dict,
        "array": list,
        "string": str,
        "integer": int,
        "number": (int, float),
        "boolean": bool,
        "null": type(None),
    }
    py = mapping.get(expected_type)
    if py is None:
        return True
    if expected_type == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected_type == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    return isinstance(value, py)


def validate_schema(value: Any, schema: dict[str, Any]) -> list[str]:
    """Minimal JSON Schema subset (type/required/properties/additionalProperties)."""
    errs: list[str] = []
    t = schema.get("type")
    if t and not _type_ok(value, str(t)):
        errs.append(f"type:{t}")
        return errs
    if str(t) == "object" and isinstance(value, dict):
        req = schema.get("required") or []
        for key in req:
            if key not in value:
                errs.append(f"required:{key}")
        props = schema.get("properties") or {}
        if isinstance(props, dict):
            for key, sub in props.items():
                if key in value and isinstance(sub, dict):
                    errs.extend(f"{key}.{e}" for e in validate_schema(value[key], sub))
        if schema.get("additionalProperties") is False:
            allowed = set(props.keys()) if isinstance(props, dict) else set()
            for key in value:
                if key not in allowed:
                    errs.append(f"additional:{key}")
    if str(t) == "array" and isinstance(value, list):
        items = schema.get("items")
        if isinstance(items, dict):
            for i, item in enumerate(value):
                errs.extend(f"[{i}].{e}" for e in validate_schema(item, items))
    return errs


def score_json_exact(
    work_dir: Path,
    scorer: dict[str, Any],
    expected: dict[str, Any],
) -> dict[str, Any]:
    rel = str(scorer.get("path") or "answer.json")
    data, err = _load_json(work_dir / rel)
    if err:
        return {"passed": False, "status": "MODEL_FAIL", "summary": err}
    want = expected.get("equals")
    passed = data == want
    return {
        "passed": passed,
        "status": "PASS" if passed else "MODEL_FAIL",
        "summary": "exact_match" if passed else "value_mismatch",
        "got": data,
    }


def score_json_schema(
    work_dir: Path,
    scorer: dict[str, Any],
    expected: dict[str, Any],
) -> dict[str, Any]:
    rel = str(scorer.get("path") or "answer.json")
    data, err = _load_json(work_dir / rel)
    if err:
        return {"passed": False, "status": "MODEL_FAIL", "summary": err}
    schema = scorer.get("schema") or {}
    if not isinstance(schema, dict):
        return {
            "passed": False,
            "status": "HARNESS_ERROR",
            "summary": "schema must be object",
        }
    schema_errs = validate_schema(data, schema)
    if schema_errs:
        return {
            "passed": False,
            "status": "MODEL_FAIL",
            "summary": "schema:" + ",".join(schema_errs),
        }
    if "equals" in expected:
        if data != expected.get("equals"):
            return {
                "passed": False,
                "status": "MODEL_FAIL",
                "summary": "value_mismatch",
                "got": data,
            }
    return {"passed": True, "status": "PASS", "summary": "schema_ok"}
