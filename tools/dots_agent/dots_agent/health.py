"""Runtime health probes for status/doctor — report reality, not intent."""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from .config import AgentConfig
from .pi_models import mcp_json_path, models_json_path, resolve_pi_selection
from .providers import LocalProvider, detect_local
from .secrets import litellm_master_key_path, litellm_master_key_status, load_litellm_master_key


def which(name: str) -> str | None:
    return shutil.which(name)


def agent_venv_python(root: Path) -> Path | None:
    p = root / "tools" / "dots_agent" / ".venv" / "bin" / "python"
    return p if p.is_file() and os.access(p, os.X_OK) else None


def scout_executable(root: Path) -> tuple[str, str]:
    """Return (status, path_or_reason)."""
    linked = which("dots-model-scout")
    if linked:
        return "available", linked
    script = root / "scripts" / "dots-model-scout"
    if script.is_file() and os.access(script, os.X_OK):
        return "available", str(script)
    return "missing", "dots-model-scout not on PATH and repo script not executable"


def expert_executable(root: Path) -> tuple[str, str]:
    linked = which("dots-expert")
    if linked:
        return "available", linked
    script = root / "scripts" / "dots-expert"
    if script.is_file() and os.access(script, os.X_OK):
        return "available", str(script)
    return "missing", "dots-expert not on PATH and repo script not executable"


def mcp_configured(names: tuple[str, ...] = ("dots-model-scout", "dots-expert")) -> tuple[str, dict[str, bool]]:
    path = mcp_json_path()
    found = {n: False for n in names}
    if not path.is_file():
        return "no", found
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return "no", found
    servers = data.get("mcpServers") or {}
    if not isinstance(servers, dict):
        return "no", found
    for n in names:
        found[n] = n in servers
    return ("yes" if all(found.values()) else "partial"), found


def probe_litellm(base_url: str, timeout: float = 2.0) -> tuple[str, str]:
    url = base_url.rstrip("/") + "/health"
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")[:200]
            return "OK", body or "healthy"
    except Exception as exc:
        return "UNREACHABLE", str(exc)[:120]


def probe_host_bind(host: str = "127.0.0.1", port: int = 4000) -> str:
    """Check that something listens on host:port (localhost publish)."""
    try:
        with socket.create_connection((host, port), timeout=1.0):
            return f"OK ({host}:{port})"
    except OSError:
        return f"UNREACHABLE ({host}:{port})"


def docker_published_bind(container_name_hint: str = "dots-litellm") -> str:
    """Inspect compose-published ports when docker is available."""
    if not which("docker"):
        return "SKIP (docker missing)"
    try:
        out = subprocess.check_output(
            ["docker", "ps", "--format", "{{.Names}}\t{{.Ports}}"],
            text=True,
            timeout=5,
        )
    except Exception as exc:
        return f"SKIP ({exc})"
    for line in out.splitlines():
        if "litellm" in line.lower() or container_name_hint in line:
            ports = line.split("\t", 1)[-1]
            if "127.0.0.1:4000" in ports:
                return f"OK ({ports.strip()})"
            if ":4000" in ports:
                return f"WARN non-localhost? ({ports.strip()})"
            return f"running ({ports.strip() or 'no ports'})"
    return "not running"


def try_mcp_tools_list(command: str, timeout: float = 8.0) -> dict[str, Any]:
    """Minimal MCP initialize + tools/list over stdio JSON-RPC."""
    init = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "dots-doctor", "version": "0.1"},
        },
    }
    initialized = {"jsonrpc": "2.0", "method": "notifications/initialized"}
    tools = {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
    payload = (
        json.dumps(init) + "\n" + json.dumps(initialized) + "\n" + json.dumps(tools) + "\n"
    )
    try:
        proc = subprocess.run(
            [command],
            input=payload.encode("utf-8"),
            capture_output=True,
            timeout=timeout,
        )
    except FileNotFoundError:
        return {"ok": False, "error": "executable missing"}
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "timeout"}
    lines = []
    for stream in (proc.stdout, proc.stderr):
        if not stream:
            continue
        for line in stream.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                lines.append(json.loads(line.decode("utf-8")))
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
    tool_names: list[str] = []
    for msg in lines:
        if msg.get("id") == 2 and isinstance(msg.get("result"), dict):
            for t in msg["result"].get("tools") or []:
                if isinstance(t, dict) and t.get("name"):
                    tool_names.append(str(t["name"]))
            return {
                "ok": True,
                "tools": tool_names,
                "raw_tools": msg["result"].get("tools") or [],
            }
    return {
        "ok": False,
        "error": f"no tools/list response (exit={proc.returncode})",
        "tools": [],
    }


def pi_mcp_discovery_via_file() -> dict[str, Any]:
    """Config presence only — not runtime discovery."""
    status, found = mcp_configured()
    return {"config_status": status, "servers": found, "path": str(mcp_json_path())}


def secret_perms_ok() -> str:
    path = litellm_master_key_path()
    if not path.is_file():
        return "UNSET"
    mode = path.stat().st_mode & 0o777
    if mode & 0o077:
        return f"INSECURE ({oct(mode)})"
    return "OK (0600-class)"


def build_status_report(cfg: AgentConfig) -> dict[str, Any]:
    local = detect_local(cfg)
    pi = which("pi")
    scout_st, scout_path = scout_executable(cfg.root)
    expert_st, expert_path = expert_executable(cfg.root)
    mcp_st, mcp_found = mcp_configured()
    litellm_st, _ = probe_litellm(cfg.gateway_base_url)
    selection = resolve_pi_selection(local)
    return {
        "pi": "installed" if pi else "missing",
        "pi_path": pi,
        "local": local,
        "selection": selection,
        "litellm": litellm_st,
        "gateway": cfg.gateway_base_url,
        "openrouter": "SET" if os.environ.get("OPENROUTER_API_KEY") else "UNSET",
        "scout_executable": scout_st,
        "scout_path": scout_path,
        "expert_executable": expert_st,
        "expert_path": expert_path,
        "mcp_configured": mcp_st,
        "mcp_servers": mcp_found,
        "master_key": litellm_master_key_status(),
        "venv": agent_venv_python(cfg.root) is not None,
    }


def run_local_inference_smoke(
    local: LocalProvider, *, timeout: float = 60.0
) -> dict[str, Any]:
    """Cheap local completion via OpenAI-compatible HTTP — no OpenRouter."""
    if not local.healthy or not local.model:
        return {"ok": False, "skipped": True, "reason": "no local model"}
    if local.name == "ollama":
        base = local.base_url.rstrip("/")
        if not base.endswith("/v1"):
            base = base + "/v1"
    else:
        base = local.base_url.rstrip("/")
        if not base.endswith("/v1"):
            base = base + "/v1"
    url = base + "/chat/completions"
    body = json.dumps(
        {
            "model": local.model,
            "messages": [
                {
                    "role": "user",
                    "content": "Return exactly:\nDOTS_LOCAL_MODEL_OK",
                }
            ],
            "temperature": 0,
            "max_tokens": 32,
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception as exc:
        return {"ok": False, "skipped": False, "error": str(exc)}
    content = ""
    choices = data.get("choices") or []
    if choices and isinstance(choices[0], dict):
        content = str((choices[0].get("message") or {}).get("content") or "")
    ok = "DOTS_LOCAL_MODEL_OK" in content
    return {
        "ok": ok,
        "skipped": False,
        "content": content[:200],
        "provider": local.name,
        "model": local.model,
        "endpoint": base,
    }


def doctor_checks(cfg: AgentConfig) -> list[tuple[str, str]]:
    checks: list[tuple[str, str]] = []
    local = detect_local(cfg)
    pi = which("pi")
    checks.append(("Pi executable", "OK" if pi else "MISSING"))
    if pi:
        try:
            ver = subprocess.check_output(["pi", "--version"], text=True, timeout=5).strip()
            checks.append(("Pi version", ver))
        except Exception as exc:
            checks.append(("Pi version", f"error: {exc}"))
    try:
        node = subprocess.check_output(["node", "-v"], text=True, timeout=5).strip()
        checks.append(("Node version", node))
    except Exception:
        checks.append(("Node version", "MISSING"))

    # Pi RPC launch probe (start + immediate cancel) — no inference
    if pi:
        try:
            proc = subprocess.Popen(
                [pi, "--mode", "rpc", "--no-session", "--help"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            proc.communicate(timeout=5)
            checks.append(("Pi RPC launch", "OK (--mode rpc available)"))
        except Exception as exc:
            checks.append(("Pi RPC launch", f"FAIL ({exc})"))
    else:
        checks.append(("Pi RPC launch", "SKIP (pi missing)"))

    sel = resolve_pi_selection(local)
    checks.append(("Local provider", f"{local.name} ({local.detail})"))
    checks.append(("Local endpoint", local.base_url or "none"))
    if sel["provider"] and sel["model"]:
        checks.append(
            (
                "Local model resolvable",
                f"{sel['provider']}/{sel['model']} @ {sel['endpoint']}",
            )
        )
        # Ensure models.json has been considered
        models_path = models_json_path()
        checks.append(
            (
                "Pi models.json",
                "present" if models_path.is_file() else "missing (run setup --with pi)",
            )
        )
        smoke = run_local_inference_smoke(local)
        if smoke.get("skipped"):
            checks.append(("Pi local inference", "SKIP: no local model"))
        elif smoke.get("ok"):
            checks.append(("Pi local inference", f"OK ({local.name}/{local.model})"))
        else:
            checks.append(
                (
                    "Pi local inference",
                    f"FAIL ({smoke.get('error') or smoke.get('content', '')[:60]})",
                )
            )
    else:
        checks.append(("Local model resolvable", "none"))
        checks.append(("Pi local inference", "SKIP: no local model"))

    scout_st, scout_path = scout_executable(cfg.root)
    expert_st, expert_path = expert_executable(cfg.root)
    checks.append(("Model Scout executable", "OK" if scout_st == "available" else "MISSING"))
    checks.append(("Expert executable", "OK" if expert_st == "available" else "MISSING"))

    mcp_st, mcp_found = mcp_configured()
    checks.append(
        (
            "Pi MCP configuration",
            "OK" if mcp_st == "yes" else f"{mcp_st} ({mcp_found})",
        )
    )

    # Pi-native discovery (authoritative when pi is installed)
    if pi and which("pi"):
        try:
            mcp_list = subprocess.check_output(
                ["pi", "mcp", "list"], text=True, timeout=30, stderr=subprocess.STDOUT
            )
            scout_ok = "dots-model-scout" in mcp_list and "find_model" in mcp_list
            expert_ok = "dots-expert" in mcp_list and "consult_expert" in mcp_list
            checks.append(
                (
                    "Model Scout MCP discovery",
                    "OK (pi mcp list)" if scout_ok else f"FAIL ({mcp_list[:120]})",
                )
            )
            checks.append(
                (
                    "Expert MCP discovery",
                    "OK (pi mcp list)" if expert_ok else f"FAIL ({mcp_list[:120]})",
                )
            )
        except Exception as exc:
            checks.append(("Model Scout MCP discovery", f"FAIL (pi mcp list: {exc})"))
            checks.append(("Expert MCP discovery", f"FAIL (pi mcp list: {exc})"))
    # Schema/annotation probe via MCP tools/list (stdio) — independent of Pi
    if scout_st == "available":
        scout_tools = try_mcp_tools_list(scout_path)
        if scout_tools.get("ok"):
            names = scout_tools.get("tools") or []
            need = {"find_model", "compare_models", "estimate_cost", "explain_choice"}
            missing = sorted(need - set(names))
            label = (
                f"PARTIAL missing={missing}"
                if missing
                else f"OK ({', '.join(names)})"
            )
            if not pi:
                checks.append(("Model Scout MCP discovery", label))
            else:
                checks.append(("Model Scout tools/list", label))
            for t in scout_tools.get("raw_tools") or []:
                if t.get("name") == "find_model":
                    ann = t.get("annotations") or {}
                    checks.append(
                        (
                            "Model Scout annotations",
                            f"readOnlyHint={ann.get('readOnlyHint')} "
                            f"destructiveHint={ann.get('destructiveHint')}",
                        )
                    )
                    break
        else:
            checks.append(
                (
                    "Model Scout tools/list" if pi else "Model Scout MCP discovery",
                    f"FAIL ({scout_tools.get('error')})",
                )
            )
    elif not pi:
        checks.append(("Model Scout MCP discovery", "SKIP (executable missing)"))

    if expert_st == "available":
        expert_tools = try_mcp_tools_list(expert_path)
        if expert_tools.get("ok"):
            names = expert_tools.get("tools") or []
            label = (
                f"OK ({', '.join(names)})"
                if "consult_expert" in names
                else f"PARTIAL tools={names}"
            )
            if not pi:
                checks.append(("Expert MCP discovery", label))
            else:
                checks.append(("Expert tools/list", label))
        else:
            checks.append(
                (
                    "Expert tools/list" if pi else "Expert MCP discovery",
                    f"FAIL ({expert_tools.get('error')})",
                )
            )
    elif not pi:
        checks.append(("Expert MCP discovery", "SKIP (executable missing)"))

    checks.append(("LiteLLM Compose", "OK" if (cfg.root / "services/litellm/compose.yml").is_file() else "MISSING"))
    litellm_st, _ = probe_litellm(cfg.gateway_base_url)
    checks.append(("LiteLLM health", litellm_st))
    checks.append(("LiteLLM host bind", probe_host_bind()))
    checks.append(("LiteLLM docker ports", docker_published_bind()))
    checks.append(("LiteLLM master key", litellm_master_key_status()))
    checks.append(("Secret permissions", secret_perms_ok()))
    checks.append(("OPENROUTER_API_KEY", "SET" if os.environ.get("OPENROUTER_API_KEY") else "UNSET"))

    # Catalog metadata (no inference)
    try:
        from .scout.catalog import fetch_catalog

        cat = fetch_catalog(
            cache_dir=cfg.cache_dir(),
            catalog_url=cfg.catalog_url,
            catalog_url_public=cfg.catalog_url_public,
            ttl_seconds=cfg.catalog_cache_ttl,
            allow_network=True,
        )
        checks.append(
            (
                "OpenRouter catalog",
                f"{cat.source} ({len(cat.models)} models, age={int(cat.age_seconds)}s)",
            )
        )
    except Exception as exc:
        checks.append(("OpenRouter catalog", f"FAIL ({exc})"))

    checks.append(("Session budget", f"${cfg.session_budget_usd:.2f}"))
    checks.append(("State dir", str(cfg.state_dir())))
    checks.append(("Cache dir", str(cfg.cache_dir())))
    venv = agent_venv_python(cfg.root)
    checks.append(("Agent venv", "OK" if venv else "MISSING (./dots setup --with pi)"))
    return checks
