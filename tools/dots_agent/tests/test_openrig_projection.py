"""Pi seat projection isolation tests."""

from __future__ import annotations

import json
from pathlib import Path

from dots_agent.openrig.provision import (
    assert_seat_isolation,
    pi_seat_agent_dir,
    provision_pi_seat,
    seat_session_name,
)

ROOT = Path(__file__).resolve().parents[3]


def test_separate_seat_dirs(tmp_path: Path):
    project = tmp_path / "repo"
    project.mkdir()
    or_home = tmp_path / "openrig"
    wt = tmp_path / "wt-builder"
    wt.mkdir()
    builder = provision_pi_seat(
        rig_name="dots-triad",
        member_id="builder",
        role="builder",
        project=project,
        worktree=wt,
        openrig_home_path=or_home,
        force=True,
    )
    reviewer = provision_pi_seat(
        rig_name="dots-triad",
        member_id="reviewer",
        role="reviewer",
        project=project,
        worktree=None,
        openrig_home_path=or_home,
        force=True,
    )
    assert builder["agent_dir"] != reviewer["agent_dir"]
    assert builder["user_pi_agent_symlinked"] is False
    assert builder["history_copied"] is False
    assert builder["unrelated_mcp_copied"] is False

    bdir = Path(builder["agent_dir"])
    rdir = Path(reviewer["agent_dir"])
    assert assert_seat_isolation(bdir)["only_safe_mcp"]
    assert assert_seat_isolation(rdir)["only_safe_mcp"]

    b_sb = json.loads((bdir / "sandbox.json").read_text(encoding="utf-8"))
    r_sb = json.loads((rdir / "sandbox.json").read_text(encoding="utf-8"))
    assert b_sb["dots"]["write_allowed"] is True
    assert r_sb["dots"]["write_allowed"] is False
    assert str(project) in r_sb["filesystem"]["denyWrite"]


def test_session_naming():
    assert seat_session_name(pod_id="team", member_id="lead", rig_name="dots-pair") == (
        "team-lead@dots-pair"
    )


def test_pi_seat_path_under_openrig_home(tmp_path: Path):
    session = "team-builder@dots-triad"
    d = pi_seat_agent_dir(session, home=tmp_path)
    assert d == tmp_path / "state" / "pi" / session / "agent"
