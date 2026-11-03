"""Pi RPC client — JSONL over stdin/stdout (no TUI scraping)."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Callable


@dataclass
class PiRpcClient:
    cwd: str
    provider: str | None = None
    model: str | None = None
    pi_bin: str = "pi"
    timeout_seconds: int = 1800
    process: subprocess.Popen[bytes] | None = None
    events: list[dict[str, Any]] = field(default_factory=list)
    _reader: threading.Thread | None = None
    _lock: threading.Lock = field(default_factory=threading.Lock)
    settled: bool = False
    last_error: str | None = None

    def start(self) -> None:
        bin_path = shutil.which(self.pi_bin) or self.pi_bin
        cmd = [bin_path, "--mode", "rpc", "--no-session"]
        if self.provider:
            cmd.extend(["--provider", self.provider])
        if self.model:
            cmd.extend(["--model", self.model])
        env = os.environ.copy()
        self.process = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=self.cwd,
            env=env,
        )
        self._reader = threading.Thread(target=self._read_loop, daemon=True)
        self._reader.start()

    def _read_loop(self) -> None:
        assert self.process and self.process.stdout
        while True:
            line = self.process.stdout.readline()
            if not line:
                break
            try:
                record = json.loads(line.decode("utf-8"))
            except json.JSONDecodeError:
                with self._lock:
                    self.last_error = "malformed JSON from Pi"
                continue
            with self._lock:
                self.events.append(record)
                if record.get("type") == "agent_settled":
                    self.settled = True

    def send(self, command: dict[str, Any]) -> str:
        assert self.process and self.process.stdin
        cid = command.get("id") or str(uuid.uuid4())
        command = {**command, "id": cid}
        raw = json.dumps(command).encode("utf-8") + b"\n"
        self.process.stdin.write(raw)
        self.process.stdin.flush()
        return str(cid)

    def wait_response(self, cmd_id: str, timeout: float = 60.0) -> dict[str, Any] | None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            with self._lock:
                for ev in self.events:
                    if (
                        ev.get("type") == "response"
                        and ev.get("id") == cmd_id
                    ):
                        return ev
            time.sleep(0.05)
        return None

    def prompt_and_wait(self, message: str) -> dict[str, Any]:
        self.settled = False
        cid = self.send({"type": "prompt", "message": message})
        resp = self.wait_response(cid, timeout=30.0)
        if not resp or not resp.get("success"):
            return {
                "ok": False,
                "error": (resp or {}).get("error") or "prompt rejected",
                "response": resp,
            }
        deadline = time.time() + self.timeout_seconds
        while time.time() < deadline:
            if self.settled:
                return {"ok": True, "events": list(self.events), "response": resp}
            if self.process and self.process.poll() is not None:
                return {
                    "ok": False,
                    "error": f"Pi exited with {self.process.returncode}",
                    "events": list(self.events),
                }
            time.sleep(0.1)
        self.cancel()
        return {"ok": False, "error": "timeout waiting for agent_settled"}

    def cancel(self) -> None:
        if not self.process:
            return
        try:
            if self.process.stdin:
                self.process.stdin.close()
        except Exception:
            pass
        try:
            self.process.terminate()
            self.process.wait(timeout=5)
        except Exception:
            try:
                self.process.kill()
            except Exception:
                pass

    def close(self) -> None:
        self.cancel()


def mockable_which(name: str) -> str | None:
    return shutil.which(name)
