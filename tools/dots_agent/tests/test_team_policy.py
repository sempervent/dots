"""Role sandbox / MCP policy tests."""

from __future__ import annotations

import json
from pathlib import Path

from dots_agent.openrig.provision import provision_pi_seat
from dots_agent.openrig.roles import load_roles
from dots_agent.openrig.terminal import preferred_provider

ROOT = Path(__file__).resolve().parents[3]


def test_reviewer_write_denied(tmp_path: Path):
    project = tmp_path / "p"
    project.mkdir()
    meta = provision_pi_seat(
        rig_name="dots-triad",
        member_id="reviewer",
        role="reviewer",
        project=project,
        openrig_home_path=tmp_path / "or",
        force=True,
    )
    sb = json.loads(Path(meta["agent_dir"], "sandbox.json").read_text(encoding="utf-8"))
    assert sb["dots"]["write_allowed"] is False
    assert str(project.resolve()) in sb["filesystem"]["denyWrite"]


def test_investigator_read_only(tmp_path: Path):
    roles, _ = load_roles(ROOT / "configs" / "agents" / "openrig" / "roles.toml")
    assert roles["investigator"].write is False
    assert roles["investigator"].sandbox == "read_only"


def test_lead_coordination_flag():
    roles, _ = load_roles(ROOT / "configs" / "agents" / "openrig" / "roles.toml")
    assert roles["lead"].coordination is True
    assert roles["builder"].coordination is False


def test_terminal_provider_selection():
    assert preferred_provider(herdr_ok=True) == "herdr"
    assert preferred_provider(herdr_ok=False) == "tmux"
