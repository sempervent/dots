"""dots-help — interactive / plain DOTS documentation and lifecycle TUI."""

from __future__ import annotations

__all__ = ["__version__"]


def _resolve_version() -> str:
    try:
        from .registry import dots_root

        vf = dots_root() / "VERSION"
        if vf.is_file():
            ver = vf.read_text(encoding="utf-8").strip()
            if ver:
                return ver
    except Exception:
        pass
    try:
        from importlib.metadata import version

        return version("dots-help")
    except Exception:
        return "0.0.0"


__version__ = _resolve_version()
