#!/usr/bin/env python3
"""DOTS Draw Things MCP bridge — wraps first-party ``draw-things-cli``.

Hermes (and other MCP clients) talk to this stdio server. The server invokes
``draw-things-cli`` for model listing and generation. It does NOT treat Draw
Things as a chat/LLM provider.

Optional GUI HTTP API (localhost:7860) is reported by ``status`` but is not
required for generation.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tomllib
from datetime import datetime, timezone
from pathlib import Path

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("drawthings")


def _dots_root() -> Path:
    env = os.environ.get("DOTS_DIR")
    if env:
        return Path(env).expanduser()
    return Path(__file__).resolve().parents[2]


def _config_path() -> Path:
    override = os.environ.get("DOTS_DRAWTHINGS_CONFIG")
    if override:
        return Path(override).expanduser()
    live = Path.home() / ".config" / "drawthings-mcp" / "config.toml"
    if live.is_file():
        return live
    return _dots_root() / "configs" / "drawthings" / "config.toml"


def load_config() -> dict:
    path = _config_path()
    if not path.is_file():
        return {}
    with path.open("rb") as fh:
        return tomllib.load(fh)


def cfg_get(section: str, key: str, default=None):
    return (load_config().get(section) or {}).get(key, default)


def expand_path(value: str) -> Path:
    return Path(value).expanduser().resolve()


def cli_bin() -> str:
    name = str(cfg_get("cli", "binary", "draw-things-cli"))
    path = shutil.which(name)
    if not path:
        raise RuntimeError(
            f"'{name}' not found on PATH. Install with: ./setup.sh --with drawthings"
        )
    return path


def output_dir() -> Path:
    raw = str(cfg_get("output", "dir", "~/Pictures/AI/DrawThings"))
    path = expand_path(raw)
    path.mkdir(parents=True, exist_ok=True)
    return path


def run_cli(args: list[str], *, timeout: int | None = 120) -> subprocess.CompletedProcess[str]:
    cmd = [cli_bin(), *args]
    return subprocess.run(
        cmd,
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def parse_models_table(text: str) -> list[dict[str, str]]:
    """Parse ``draw-things-cli models list`` table output."""
    rows: list[dict[str, str]] = []
    for line in text.splitlines():
        if not line.strip() or line.startswith("Models directory:") or set(line.strip()) <= {"-", " "}:
            continue
        if line.startswith("MODEL") and "NAME" in line:
            continue
        # Columns are padded; split on 2+ spaces
        parts = re.split(r"\s{2,}", line.strip())
        if len(parts) < 2:
            continue
        model_id = parts[0]
        if not model_id.endswith(".ckpt") and "flux" not in model_id.lower():
            # Still accept unknown suffixes if first col looks like an id
            if " " in model_id:
                continue
        rows.append(
            {
                "id": parts[0],
                "name": parts[1] if len(parts) > 1 else "",
                "source": parts[2] if len(parts) > 2 else "",
                "downloaded": parts[3] if len(parts) > 3 else "",
                "hugging_face": parts[4] if len(parts) > 4 else "",
            }
        )
    return rows


def resolve_model(model: str | None) -> str:
    if model:
        return model
    configured = cfg_get("model", "default", "") or ""
    if configured:
        return str(configured)
    proc = run_cli(["models", "list", "--downloaded-only", "--offline"], timeout=60)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "models list failed")
    rows = parse_models_table(proc.stdout)
    if not rows:
        raise RuntimeError("No downloaded Draw Things models found.")
    return rows[0]["id"]


def maybe_unload_ollama() -> list[str]:
    policy = str(cfg_get("memory", "policy", "manual")).strip().lower()
    notes: list[str] = []
    if policy != "unload_ollama":
        return notes
    if not shutil.which("ollama"):
        notes.append("memory.policy=unload_ollama but ollama not on PATH")
        return notes
    ps = subprocess.run(["ollama", "ps"], capture_output=True, text=True, check=False)
    if ps.returncode != 0:
        notes.append(f"ollama ps failed: {ps.stderr.strip()}")
        return notes
    lines = [ln for ln in ps.stdout.splitlines() if ln.strip()]
    if len(lines) <= 1:
        notes.append("no Ollama models loaded")
        return notes
    # Skip header
    for ln in lines[1:]:
        name = ln.split()[0] if ln.split() else ""
        if not name or name.upper() == "NAME":
            continue
        stop = subprocess.run(["ollama", "stop", name], capture_output=True, text=True, check=False)
        if stop.returncode == 0:
            notes.append(f"stopped ollama model: {name}")
        else:
            notes.append(f"failed to stop {name}: {stop.stderr.strip()}")
    return notes


def default_output_path(prefix: str = "gen") -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return output_dir() / f"{prefix}-{stamp}.png"


@mcp.tool()
def status() -> str:
    """Check Draw Things CLI, GUI app, optional HTTP API, and bridge config."""
    cfg_path = _config_path()
    lines = [
        f"config: {cfg_path} ({'ok' if cfg_path.is_file() else 'missing'})",
        f"output_dir: {output_dir()}",
        f"memory.policy: {cfg_get('memory', 'policy', 'manual')}",
        f"default_model: {cfg_get('model', 'default', '') or '(first downloaded)'}",
    ]
    try:
        binary = cli_bin()
        ver = run_cli(["--version"], timeout=15)
        lines.append(f"cli: {binary} ({(ver.stdout or ver.stderr).strip() or 'ok'})")
    except Exception as exc:  # noqa: BLE001
        lines.append(f"cli: unavailable ({exc})")

    app = Path(str(cfg_get("app", "path", "/Applications/Draw Things.app"))).expanduser()
    lines.append(f"app: {app} ({'present' if app.exists() else 'missing — install from App Store / drawthings.ai'})")

    host = str(cfg_get("http_api", "host", "127.0.0.1"))
    port = int(cfg_get("http_api", "port", 7860) or 7860)
    if host not in {"127.0.0.1", "localhost", "::1"}:
        lines.append(f"http_api: WARNING non-localhost host configured ({host}) — prefer 127.0.0.1")
    try:
        import urllib.request

        with urllib.request.urlopen(f"http://{host}:{port}/", timeout=1.5) as resp:
            lines.append(f"http_api: reachable http://{host}:{port}/ (status {resp.status})")
    except Exception:
        lines.append(
            f"http_api: not reachable at http://{host}:{port}/ "
            "(optional; CLI bridge does not need it)"
        )
    return "\n".join(lines)


@mcp.tool()
def list_models(downloaded_only: bool = True) -> str:
    """List Draw Things models available to the CLI (dynamic inventory)."""
    args = ["models", "list", "--offline"]
    if downloaded_only:
        args.append("--downloaded-only")
    proc = run_cli(args, timeout=90)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "models list failed")
    rows = parse_models_table(proc.stdout)
    if not rows:
        return proc.stdout.strip() or "No models found."
    out = ["id\tname\tdownloaded\tsource"]
    for row in rows:
        out.append(f"{row['id']}\t{row['name']}\t{row['downloaded']}\t{row['source']}")
    return "\n".join(out)


@mcp.tool()
def generate(
    prompt: str,
    model: str | None = None,
    width: int = 512,
    height: int = 512,
    steps: int | None = None,
    seed: int | None = None,
    negative_prompt: str | None = None,
    output_path: str | None = None,
) -> str:
    """Generate an image with draw-things-cli and return the saved file path.

    Prefer modest width/height/steps on 24 GB Apple Silicon. Draw Things is a
    pixel renderer; Hermes/Ollama should own prompt reasoning.
    """
    model_id = resolve_model(model)
    out = Path(output_path).expanduser() if output_path else default_output_path("gen")
    out.parent.mkdir(parents=True, exist_ok=True)

    mem_notes = maybe_unload_ollama()
    args = [
        "generate",
        "--model",
        model_id,
        "--prompt",
        prompt,
        "--width",
        str(width),
        "--height",
        str(height),
        "--output",
        str(out),
    ]
    if steps is not None:
        args.extend(["--steps", str(steps)])
    if seed is not None:
        args.extend(["--seed", str(seed)])
    if negative_prompt:
        args.extend(["--negative-prompt", negative_prompt])

    # Generation can be slow; allow several minutes.
    proc = run_cli(args, timeout=60 * 15)
    payload = {
        "ok": proc.returncode == 0,
        "model": model_id,
        "output": str(out) if out.exists() else None,
        "stdout": (proc.stdout or "").strip()[-2000:],
        "stderr": (proc.stderr or "").strip()[-2000:],
        "memory": mem_notes,
    }
    if proc.returncode != 0:
        raise RuntimeError(
            f"draw-things-cli generate failed (code {proc.returncode}): "
            f"{payload['stderr'] or payload['stdout']}"
        )
    if not out.exists():
        raise RuntimeError(f"Generation reported success but output missing: {out}")
    return (
        f"saved: {out}\n"
        f"model: {model_id}\n"
        f"size: {out.stat().st_size} bytes\n"
        + ("memory: " + "; ".join(mem_notes) + "\n" if mem_notes else "")
    )


@mcp.tool()
def img2img(
    prompt: str,
    image_path: str,
    strength: float = 0.35,
    model: str | None = None,
    width: int | None = None,
    height: int | None = None,
    steps: int | None = None,
    seed: int | None = None,
    negative_prompt: str | None = None,
    output_path: str | None = None,
) -> str:
    """Image-to-image via draw-things-cli ``--image`` / ``--strength``."""
    src = Path(image_path).expanduser()
    if not src.is_file():
        raise RuntimeError(f"image_path not found: {src}")
    model_id = resolve_model(model)
    out = Path(output_path).expanduser() if output_path else default_output_path("img2img")
    out.parent.mkdir(parents=True, exist_ok=True)
    mem_notes = maybe_unload_ollama()
    args = [
        "generate",
        "--model",
        model_id,
        "--prompt",
        prompt,
        "--image",
        str(src),
        "--strength",
        str(strength),
        "--output",
        str(out),
    ]
    if width is not None:
        args.extend(["--width", str(width)])
    if height is not None:
        args.extend(["--height", str(height)])
    if steps is not None:
        args.extend(["--steps", str(steps)])
    if seed is not None:
        args.extend(["--seed", str(seed)])
    if negative_prompt:
        args.extend(["--negative-prompt", negative_prompt])
    proc = run_cli(args, timeout=60 * 15)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "img2img failed")
    if not out.exists():
        raise RuntimeError(f"img2img reported success but output missing: {out}")
    return (
        f"saved: {out}\n"
        f"model: {model_id}\n"
        f"source: {src}\n"
        + ("memory: " + "; ".join(mem_notes) + "\n" if mem_notes else "")
    )


if __name__ == "__main__":
    mcp.run()
