#!/usr/bin/env python3
"""Read-only model discovery and safe adoption for DOTS ai-server."""
from __future__ import annotations

import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

# Reuse config merge from compose renderer (same repo).
_SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPT_DIR))
from ai_compose_render import expand_home, load_toml, merge_config  # noqa: E402

GGUF_MAGIC = b"GGUF"
MAX_GGUF_FILES_PER_DIR = 500
MAX_HF_GGUF_FILES = 300
MAX_SCAN_DEPTH = 3
IMAGE_EXT = {".safetensors", ".ckpt", ".pt", ".pth", ".bin"}


def merged_config(repo: Path, user_cfg: Path) -> tuple[dict, dict]:
    defaults = load_toml(repo / "configs/ai-server/defaults.toml")
    backends = load_toml(repo / "configs/ai-server/backends.toml")
    user = load_toml(user_cfg) if user_cfg.is_file() else {}
    return merge_config(user, defaults, backends), user


def discovery_path_specs(
    merged: dict, user: dict
) -> list[tuple[str, str, bool]]:
    """Return (path, source_label, managed) entries in scan order."""
    out: list[tuple[str, str, bool]] = []
    models_dir = merged["models_dir"]
    out.append((models_dir, "ai-server", True))
    disc = user.get("ai_server", {}).get("discovery") or {}
    for raw in disc.get("paths") or []:
        p = expand_home(str(raw).strip())
        if p:
            out.append((p, "configured", False))
    home = Path.home()
    for p in (
        home / "models",
        home / "Models",
        home / "ai" / "models",
        home / "srv" / "ai" / "models",
        Path("/srv/ai/models"),
    ):
        out.append((str(p), "convention", False))
    llama_cache = os.environ.get("LLAMA_CACHE") or str(home / ".cache" / "llama.cpp")
    out.append((llama_cache, "llamacpp-cache", False))
    hf = os.environ.get("HF_HOME") or str(home / ".cache" / "huggingface")
    out.append((hf, "huggingface", False))
    if sys.platform == "darwin":
        out.append(
            (
                str(home / "Library" / "Application Support" / "LM Studio" / "models"),
                "lmstudio",
                False,
            )
        )
    else:
        out.append((str(home / ".lmstudio" / "models"), "lmstudio", False))
    return out


def canonical_key(path: Path) -> str | None:
    try:
        if path.is_symlink() and not path.exists():
            return None
        return str(path.resolve())
    except OSError:
        return None


def gguf_header_valid(path: Path) -> bool:
    try:
        with path.open("rb") as fh:
            return fh.read(4) == GGUF_MAGIC
    except OSError:
        return False


def stat_size(path: Path) -> int:
    try:
        return path.stat().st_size
    except OSError:
        return 0


def scan_gguf_directory(
    directory: Path,
    source: str,
    managed: bool,
    seen: set[str],
    records: list[dict],
    depth: int = 0,
) -> None:
    if depth > MAX_SCAN_DEPTH or not directory.is_dir():
        return
    try:
        entries = list(directory.iterdir())
    except OSError:
        return
    count = 0
    for entry in entries:
        if count >= MAX_GGUF_FILES_PER_DIR:
            break
        if entry.name.startswith(".") and entry.name not in (".", ".."):
            continue
        if entry.is_dir():
            if entry.name in (".incomplete", "blobs", "manifests"):
                continue
            scan_gguf_directory(entry, source, managed, seen, records, depth + 1)
            continue
        lower = entry.name.lower()
        if lower.endswith(".gguf"):
            key = canonical_key(entry)
            if not key or key in seen:
                continue
            if not gguf_header_valid(entry):
                continue
            seen.add(key)
            records.append(
                _gguf_record(entry, source, managed, key)
            )
            count += 1
        elif any(lower.endswith(ext) for ext in IMAGE_EXT):
            key = canonical_key(entry)
            if not key or key in seen:
                continue
            seen.add(key)
            records.append(
                {
                    "id": f"image:{key}",
                    "name": entry.name,
                    "path": str(entry),
                    "source": source,
                    "backend": "image",
                    "format": "diffusion",
                    "size_bytes": stat_size(entry),
                    "managed": managed,
                    "compatible": False,
                    "default": False,
                }
            )


def _gguf_record(path: Path, source: str, managed: bool, key: str) -> dict:
    return {
        "id": f"gguf:{key}",
        "name": path.name,
        "path": str(path),
        "source": source,
        "backend": "llama_cpp",
        "format": "gguf",
        "size_bytes": stat_size(path),
        "managed": managed,
        "compatible": True,
        "default": False,
    }


def scan_ollama_cli(seen: set[str], records: list[dict]) -> bool:
    if os.environ.get("DOTS_AI_SKIP_OLLAMA_CLI"):
        return False
    try:
        proc = subprocess.run(
            ["ollama", "list"],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    if proc.returncode != 0:
        return False
    found = 0
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line or line.startswith("NAME"):
            continue
        parts = line.split()
        if not parts:
            continue
        name = parts[0]
        size_bytes = 0
        size_note = "logical size from ollama list (layers may be shared)"
        if len(parts) >= 3:
            size_human = parts[2]
            size_bytes = _parse_human_size(size_human)
        rid = f"ollama:{name}"
        if rid in seen:
            continue
        seen.add(rid)
        records.append(
            {
                "id": rid,
                "name": name,
                "path": _ollama_models_root(),
                "source": "ollama",
                "backend": "ollama",
                "format": "ollama",
                "size_bytes": size_bytes,
                "size_note": size_note,
                "managed": False,
                "compatible": False,
                "default": False,
            }
        )
        found += 1
    return found > 0


def _parse_human_size(token: str) -> int:
    m = re.match(r"^([0-9.]+)\s*([KMGT]?B)?$", token, re.I)
    if not m:
        return 0
    val = float(m.group(1))
    unit = (m.group(2) or "B").upper()
    mult = {"B": 1, "KB": 1024, "MB": 1024**2, "GB": 1024**3, "TB": 1024**4}
    return int(val * mult.get(unit, 1))


def _ollama_models_root() -> str:
    return os.environ.get("OLLAMA_MODELS") or str(Path.home() / ".ollama" / "models")


def scan_ollama_manifests(seen: set[str], records: list[dict]) -> None:
    root = Path(_ollama_models_root()) / "manifests" / "registry.ollama.ai" / "library"
    if not root.is_dir():
        return
    for manifest in root.rglob("*"):
        if not manifest.is_file():
            continue
        rel = manifest.relative_to(root)
        parts = rel.parts
        if len(parts) < 2:
            continue
        name = f"{parts[0]}:{parts[1]}"
        rid = f"ollama:{name}"
        if rid in seen:
            continue
        seen.add(rid)
        records.append(
            {
                "id": rid,
                "name": name,
                "path": str(manifest),
                "source": "ollama",
                "backend": "ollama",
                "format": "ollama",
                "size_bytes": stat_size(manifest),
                "size_note": "manifest size only; blob storage is shared",
                "managed": False,
                "compatible": False,
                "default": False,
            }
        )


def discover(repo: Path, user_cfg: Path) -> dict:
    merged, user = merged_config(repo, user_cfg)
    default_name = merged.get("default_model") or ""
    models_dir = Path(merged["models_dir"])
    records: list[dict] = []
    seen_paths: set[str] = set()
    seen_ids: set[str] = set()

    for path_str, source, managed in discovery_path_specs(merged, user):
        p = Path(expand_home(path_str))
        if source == "huggingface":
            scan_gguf_directory(p / "hub", "huggingface", False, seen_paths, records)
            scan_gguf_directory(p, "huggingface", False, seen_paths, records)
            continue
        scan_gguf_directory(p, source, managed, seen_paths, records)

    if not scan_ollama_cli(seen_ids, records):
        scan_ollama_manifests(seen_ids, records)

    compatible = 0
    for rec in records:
        if rec.get("compatible"):
            compatible += 1
        if default_name and rec.get("format") == "gguf" and rec.get("name") == default_name:
            if Path(models_dir / default_name).exists() or rec.get("managed"):
                rec["default"] = True
        if (
            default_name
            and rec.get("name") == default_name
            and rec.get("compatible")
            and not (models_dir / default_name).exists()
        ):
            rec["default_candidate"] = True

    return {
        "models_dir": str(models_dir),
        "default_model": default_name,
        "records": records,
        "summary": {
            "total": len(records),
            "compatible_llama": compatible,
            "managed_gguf": sum(
                1 for r in records if r.get("managed") and r.get("format") == "gguf"
            ),
            "ollama": sum(1 for r in records if r.get("backend") == "ollama"),
        },
    }


def fmt_size(num: int) -> str:
    if num <= 0:
        return "-"
    size = float(num)
    units = ["B", "KB", "MB", "GB", "TB"]
    for i, unit in enumerate(units):
        if size < 1024 or i == len(units) - 1:
            if unit == "B":
                return f"{int(size)} B"
            return f"{size:.1f} {unit}"
        size /= 1024
    return "-"


def print_table(data: dict, verbose: bool) -> None:
    print("Discovered AI models")
    print("")
    print(f"{'NAME':<36} {'SOURCE':<12} {'FORMAT':<8} {'SIZE':>10} {'LLAMA':>5}")
    for rec in sorted(data["records"], key=lambda r: (r.get("name") or "").lower()):
        llama = "yes" if rec.get("compatible") else "no"
        if rec.get("backend") == "ollama":
            llama = "no*"
        mark = ""
        if rec.get("default"):
            mark = " *"
        print(
            f"{rec.get('name','')[:36]:<36} "
            f"{rec.get('source','')[:12]:<12} "
            f"{rec.get('format','')[:8]:<8} "
            f"{fmt_size(int(rec.get('size_bytes') or 0)):>10} "
            f"{llama:>5}{mark}"
        )
        if verbose:
            print(f"    path: {rec.get('path')}")
            if rec.get("size_note"):
                print(f"    note: {rec.get('size_note')}")
    s = data["summary"]
    print("")
    print(f"{s['total']} models discovered")
    print(f"{s['compatible_llama']} directly usable by llama.cpp")
    if s["total"] > s["managed_gguf"]:
        print("Run `dots ai discover` for the full inventory; `dots ai models` lists managed GGUF.")


def print_managed(data: dict) -> None:
    models_dir = data["models_dir"]
    default_name = data["default_model"]
    managed = [
        r
        for r in data["records"]
        if r.get("managed") and r.get("format") == "gguf"
    ]
    elsewhere = [
        r
        for r in data["records"]
        if r.get("compatible") and not r.get("managed")
    ]
    print(f"Managed models ({models_dir})")
    print("")
    if not managed:
        print("  (none)")
    else:
        print(f"{'MODEL':<40} {'SIZE':>10} {'DEFAULT':>8}")
        for rec in managed:
            mark = "*" if rec.get("name") == default_name else ""
            print(
                f"{rec.get('name','')[:40]:<40} "
                f"{fmt_size(int(rec.get('size_bytes') or 0)):>10} {mark:>8}"
            )
    if elsewhere:
        print("")
        print(
            f"Note: {len(elsewhere)} compatible GGUF model(s) found elsewhere. "
            "Use `dots ai discover` and `dots ai model adopt <path>`."
        )


def doctor_lines(data: dict) -> None:
    s = data["summary"]
    compatible = s["compatible_llama"]
    ollama_n = s["ollama"]
    if compatible:
        print(f"PASS {compatible} llama.cpp-compatible GGUF model(s) discovered")
    else:
        print("WARN no llama.cpp-compatible GGUF models discovered")
    if ollama_n:
        print(
            f"WARN {ollama_n} Ollama model(s) found but not directly usable by llama.cpp"
        )
    managed = s["managed_gguf"]
    if managed == 0:
        print("WARN configured models_dir has no managed GGUF files")
    else:
        print(f"PASS {managed} managed GGUF model(s) in models_dir")
    default_name = data.get("default_model") or ""
    models_dir = Path(data["models_dir"])
    if default_name and not (models_dir / default_name).exists():
        for rec in data["records"]:
            if rec.get("name") == default_name and rec.get("compatible"):
                print(
                    f"INFO matching GGUF '{default_name}' found at {rec.get('path')}; "
                    "run: dots ai model adopt <path>"
                )
                break
        else:
            print(f"WARN configured default model missing: {default_name}")
    elif not default_name:
        if compatible:
            print("INFO compatible GGUF found; run dots ai discover")
        else:
            print("WARN no default model selected")


def safe_adopt(repo: Path, user_cfg: Path, target: str, copy: bool) -> int:
    merged, _user = merged_config(repo, user_cfg)
    models_dir = Path(merged["models_dir"])
    models_dir.mkdir(parents=True, exist_ok=True)
    src = Path(expand_home(target)).expanduser()
    if not src.is_absolute():
        src = Path.cwd() / src
    try:
        src = src.resolve()
    except OSError as exc:
        print(f"Error: cannot resolve source: {exc}", file=sys.stderr)
        return 1
    if ".." in src.parts:
        print("Error: invalid source path", file=sys.stderr)
        return 1
    models_resolved = models_dir.resolve()
    if src == models_resolved or str(src).startswith(str(models_resolved) + os.sep):
        print("Error: source is already under models_dir", file=sys.stderr)
        return 1
    if not src.is_file():
        # Allow adopt by inventory id or basename from discover
        inv = discover(repo, user_cfg)
        match = None
        for rec in inv["records"]:
            if rec.get("id") == target or rec.get("name") == target:
                if rec.get("compatible"):
                    match = Path(rec["path"])
                    break
        if match is None:
            print(f"Error: source not found: {target}", file=sys.stderr)
            return 1
        src = match.resolve()
    if not src.name.lower().endswith(".gguf"):
        print("Error: only .gguf models can be adopted for llama.cpp", file=sys.stderr)
        return 1
    if not gguf_header_valid(src):
        print("Error: file does not look like a GGUF model", file=sys.stderr)
        return 1
    dest = models_dir / src.name
    if dest.exists():
        try:
            if dest.resolve() == src:
                print(f"OK: already adopted {src.name}")
                return 0
        except OSError:
            pass
        print(f"Error: destination already exists: {dest}", file=sys.stderr)
        return 1
    if copy:
        import shutil

        shutil.copy2(src, dest)
        print(f"OK: copied to {dest}")
    else:
        dest.symlink_to(src)
        print(f"OK: symlinked {dest} -> {src}")
    return 0


def resolve_default_status(data: dict) -> dict:
    default_name = data.get("default_model") or ""
    models_dir = Path(data["models_dir"])
    out = {
        "configured": default_name or None,
        "resolved_path": None,
        "source": None,
        "compatible": None,
        "ok": False,
    }
    if not default_name:
        return out
    managed = models_dir / default_name
    if managed.exists():
        out["resolved_path"] = str(managed.resolve())
        out["source"] = "ai-server"
        out["compatible"] = True
        out["ok"] = True
        return out
    for rec in data["records"]:
        if rec.get("name") == default_name and rec.get("compatible"):
            out["resolved_path"] = rec.get("path")
            out["source"] = rec.get("source")
            out["compatible"] = True
            out["ok"] = False
            break
    return out


def main() -> int:
    if len(sys.argv) < 4:
        print(
            "usage: ai_model_inventory.py REPO USER_CONFIG "
            "discover|managed|doctor|adopt|default-status [--json|--verbose] [target] [--copy]",
            file=sys.stderr,
        )
        return 2
    repo = Path(sys.argv[1])
    user_cfg = Path(sys.argv[2])
    cmd = sys.argv[3]
    args = sys.argv[4:]
    verbose = "--verbose" in args
    as_json = "--json" in args
    copy = "--copy" in args
    args = [a for a in args if a not in ("--verbose", "--json", "--copy")]

    if cmd == "discover":
        data = discover(repo, user_cfg)
        if as_json:
            print(json.dumps(data, indent=2))
        else:
            print_table(data, verbose)
        return 0
    if cmd == "managed":
        data = discover(repo, user_cfg)
        if as_json:
            print(json.dumps(data, indent=2))
        else:
            print_managed(data)
        return 0
    if cmd == "doctor":
        data = discover(repo, user_cfg)
        if as_json:
            print(json.dumps(data["summary"], indent=2))
        else:
            doctor_lines(data)
        return 0
    if cmd == "default-status":
        data = discover(repo, user_cfg)
        st = resolve_default_status(data)
        if as_json:
            print(json.dumps(st, indent=2))
        else:
            print(json.dumps(st))
        return 0
    if cmd == "adopt":
        if not args:
            print("Error: adopt target required", file=sys.stderr)
            return 1
        return safe_adopt(repo, user_cfg, args[0], copy)
    print(f"Unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
