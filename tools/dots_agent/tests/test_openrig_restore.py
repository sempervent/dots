"""Seat projection survives simulated restore (config only; no conversation wipe)."""

from __future__ import annotations

import json
from pathlib import Path

from dots_agent.openrig.provision import provision_pi_seat


def test_reprovision_preserves_dots_seat_and_does_not_require_history(tmp_path: Path):
    project = tmp_path / "p"
    project.mkdir()
    or_home = tmp_path / "or"
    meta1 = provision_pi_seat(
        rig_name="dots-pair",
        member_id="builder",
        role="builder",
        project=project,
        worktree=tmp_path / "wt",
        openrig_home_path=or_home,
        force=True,
    )
    (tmp_path / "wt").mkdir(exist_ok=True)
    agent = Path(meta1["agent_dir"])
    # Simulate OpenRig conversation artifact that must not be wiped by our provisioner
    sessions = agent.parent / "sessions"
    sessions.mkdir(exist_ok=True)
    (sessions / "fake-session.json").write_text('{"ok":true}\n', encoding="utf-8")

    meta2 = provision_pi_seat(
        rig_name="dots-pair",
        member_id="builder",
        role="builder",
        project=project,
        worktree=tmp_path / "wt",
        openrig_home_path=or_home,
        force=True,
    )
    assert Path(meta2["agent_dir"]) == agent
    assert (agent / "dots-seat.json").is_file()
    assert (agent / "sandbox.json").is_file()
    # Conversation artifact still present (we don't delete sibling sessions/)
    assert (sessions / "fake-session.json").is_file()
    seat = json.loads((agent / "dots-seat.json").read_text(encoding="utf-8"))
    assert seat["history_copied"] is False
