"""Pi RPC client unit tests (protocol helpers; no live Pi)."""

from __future__ import annotations

import json

from dots_agent.pi_rpc import PiRpcClient


def test_send_writes_jsonl(tmp_path, monkeypatch):
    client = PiRpcClient(cwd=str(tmp_path), timeout_seconds=1)

    class FakeStdin:
        def __init__(self):
            self.chunks: list[bytes] = []

        def write(self, data: bytes):
            self.chunks.append(data)

        def flush(self):
            pass

        def close(self):
            pass

    class FakeProc:
        def __init__(self):
            self.stdin = FakeStdin()
            self.stdout = None
            self.returncode = None

        def poll(self):
            return None

        def terminate(self):
            self.returncode = 0

        def kill(self):
            self.returncode = -9

        def wait(self, timeout=None):
            return 0

    client.process = FakeProc()
    cid = client.send({"type": "prompt", "message": "hi"})
    raw = b"".join(client.process.stdin.chunks)
    assert raw.endswith(b"\n")
    obj = json.loads(raw.decode())
    assert obj["type"] == "prompt"
    assert obj["id"] == cid
    assert obj["message"] == "hi"


def test_cancel_safe_without_process():
    client = PiRpcClient(cwd=".")
    client.cancel()  # must not raise
