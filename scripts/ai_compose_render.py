#!/usr/bin/env python3
"""Render DOTS ai-server compose project from template + machine config."""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

try:
    import tomllib
except ImportError:  # pragma: no cover
    print("Python >=3.11 required", file=sys.stderr)
    raise SystemExit(1)


def load_toml(path: Path) -> dict:
    with path.open("rb") as fh:
        return tomllib.load(fh)


def expand_home(value: str) -> str:
    if value.startswith("~/"):
        return str(Path.home() / value[2:])
    if value == "~":
        return str(Path.home())
    return value


def default_runtime_root() -> str:
    if sys.platform == "darwin":
        return str(Path.home() / "srv" / "ai")
    return "/srv/ai"


def merge_config(user: dict, defaults: dict, backends: dict) -> dict:
    base = defaults.get("ai_server", {}).copy()
    base.update(user.get("ai_server", {}))
    ow = defaults.get("ai_server", {}).get("open_webui", {})
    ow = {**ow, **user.get("ai_server", {}).get("open_webui", {})}
    ll = defaults.get("ai_server", {}).get("llama", {})
    ll = {**ll, **user.get("ai_server", {}).get("llama", {})}
    backend_id = str(base.get("backend") or "cpu")
    backend = None
    for b in backends.get("backends") or []:
        if b.get("id") == backend_id:
            backend = b
            break
    if backend is None:
        raise ValueError(f"unknown backend: {backend_id}")
    rt = str(base.get("runtime_root") or "").strip()
    if not rt or rt in ('""', "''"):
        rt = default_runtime_root()
    rt = expand_home(rt)
    models = str(base.get("models_dir") or "").strip()
    if not models:
        models = str(Path(rt) / "models")
    else:
        models = expand_home(models)
    webui_data = str(Path(rt) / "open-webui")
    state_dir = str(Path(rt) / "state")
    gpu_layers = base.get("gpu_layers")
    if gpu_layers is None:
        gpu_layers = backend.get("gpu_layers_default", 0)
    threads = int(base.get("threads") or 0)
    parallel = int(base.get("parallel") or 1)
    ctx = int(base.get("context_size") or 8192)
    llama_port = int(base.get("llama_port") or 8080)
    webui_port = int(base.get("webui_port") or 3000)
    default_model = str(base.get("default_model") or "").strip()
    if default_model and ("/" in default_model or ".." in default_model):
        raise ValueError("default_model must be a basename")
    llama_image = str(backend.get("llama_image") or "").strip()
    compose_enabled = backend.get("compose", True)
    if compose_enabled is False:
        compose_enabled = False
    else:
        compose_enabled = True
    webui_image = str(ow.get("image") or "ghcr.io/open-webui/open-webui:main")
    extra_args = ll.get("extra_args") or []
    if not isinstance(extra_args, list):
        raise ValueError("ai_server.llama.extra_args must be a list")
    return {
        "backend_id": backend_id,
        "backend": backend,
        "runtime_root": rt,
        "models_dir": models,
        "webui_data_dir": webui_data,
        "state_dir": state_dir,
        "gpu_layers": str(gpu_layers),
        "threads": str(threads or 4),
        "parallel": str(parallel),
        "context_size": str(ctx),
        "llama_port": str(llama_port),
        "webui_port": str(webui_port),
        "default_model": default_model,
        "llama_image": llama_image,
        "webui_image": webui_image,
        "compose_enabled": compose_enabled,
        "extra_args": [str(x) for x in extra_args],
        "publish_llama": bool(base.get("publish_llama")),
    }


def substitute(template: str, env: dict[str, str]) -> str:
    out = template
    for key, val in env.items():
        out = out.replace("${" + key + "}", val)
    if "${" in out:
        missing = sorted(set(re.findall(r"\$\{([^}]+)\}", out)))
        raise ValueError(f"unexpanded template keys: {missing}")
    return out


def gpu_override(backend_id: str) -> str:
    if backend_id == "cuda":
        return """services:
  llama:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
"""
    if backend_id == "rocm":
        return """services:
  llama:
    devices:
      - /dev/kfd
      - /dev/dri
    group_add:
      - video
"""
    return ""


def main() -> int:
    if len(sys.argv) != 5:
        print(
            "usage: ai_compose_render.py REPO_ROOT USER_CONFIG OUT_DIR MODE",
            file=sys.stderr,
        )
        return 2
    repo = Path(sys.argv[1])
    user_cfg = Path(sys.argv[2])
    out_dir = Path(sys.argv[3])
    mode = sys.argv[4]
    defaults = load_toml(repo / "configs/ai-server/defaults.toml")
    backends = load_toml(repo / "configs/ai-server/backends.toml")
    user = load_toml(user_cfg) if user_cfg.is_file() else {}
    merged = merge_config(user, defaults, backends)
    template_path = repo / "configs/ai-server/compose.template.yml"
    template = template_path.read_text(encoding="utf-8")
    env = {
        "LLAMA_IMAGE": merged["llama_image"],
        "WEBUI_IMAGE": merged["webui_image"],
        "LLAMA_PORT": merged["llama_port"],
        "WEBUI_HOST_PORT": merged["webui_port"],
        "WEBUI_CONTAINER_PORT": "8080",
        "MODELS_DIR": merged["models_dir"],
        "WEBUI_DATA_DIR": merged["webui_data_dir"],
        "DEFAULT_MODEL": merged["default_model"] or "REPLACE_ME.gguf",
        "CONTEXT_SIZE": merged["context_size"],
        "THREADS": merged["threads"],
        "PARALLEL": merged["parallel"],
        "GPU_LAYERS": merged["gpu_layers"],
        "WEBUI_SECRET_KEY": os.environ.get("DOTS_AI_WEBUI_SECRET", "dots-change-me"),
    }
    if mode == "print-json":
        import json

        print(json.dumps(merged, indent=2))
        return 0
    if not merged["compose_enabled"]:
        print("native backend: compose not rendered", file=sys.stderr)
        return 0
    out_dir.mkdir(parents=True, exist_ok=True)
    compose = substitute(template, env)
    # Append extra llama args as additional command entries (safe structured list)
    if merged["extra_args"]:
        lines = compose.splitlines()
        cmd_idx = None
        for i, line in enumerate(lines):
            if line.strip() == "command:":
                cmd_idx = i
                break
        if cmd_idx is not None:
            insert_at = cmd_idx + 1
            # find end of command block (next key at same indent as command)
            while insert_at < len(lines) and (
                lines[insert_at].startswith("      -") or lines[insert_at].strip() == ""
            ):
                insert_at += 1
            extra_lines = []
            for arg in merged["extra_args"]:
                extra_lines.append(f'      - "{arg.replace(chr(34), "")}"')
            lines[insert_at:insert_at] = extra_lines
            compose = "\n".join(lines) + "\n"
    if merged["publish_llama"]:
        # Inject ports publish (discouraged; test-only path)
        compose = compose.replace(
            "expose:\n      - \"${LLAMA_PORT}\"",
            f'ports:\n      - "{merged["llama_port"]}:{merged["llama_port"]}"',
        )
    (out_dir / "compose.yml").write_text(compose, encoding="utf-8")
    override = gpu_override(merged["backend_id"])
    override_path = out_dir / "compose.override.yml"
    if override.strip():
        override_path.write_text(override, encoding="utf-8")
    elif override_path.is_file():
        override_path.unlink()
    env_lines = [
        f"LLAMA_IMAGE={env['LLAMA_IMAGE']}",
        f"WEBUI_IMAGE={env['WEBUI_IMAGE']}",
        f"MODELS_DIR={env['MODELS_DIR']}",
        f"WEBUI_DATA_DIR={env['WEBUI_DATA_DIR']}",
        f"WEBUI_SECRET_KEY={env['WEBUI_SECRET_KEY']}",
    ]
    (out_dir / ".env").write_text("\n".join(env_lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
