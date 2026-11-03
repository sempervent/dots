"""CLI smoke for team dry-run / list / status (no live OpenRig required)."""

from __future__ import annotations

from pathlib import Path

from dots_agent.cli import main

ROOT = Path(__file__).resolve().parents[3]


def test_team_list(capsys):
    assert main(["team", "list"]) == 0
    out = capsys.readouterr().out
    assert "dots-pair" in out
    assert "dots-triad" in out
    assert "dots-investigate" in out


def test_team_up_dry_run(tmp_path, capsys, monkeypatch):
    monkeypatch.setenv("DOTS_DIR", str(ROOT))
    project = tmp_path / "proj"
    project.mkdir()
    rc = main(
        [
            "team",
            "up",
            "dots-triad",
            "--project",
            str(project),
            "--dry-run",
        ]
    )
    assert rc == 0
    out = capsys.readouterr().out
    assert "DOTS Team Plan" in out
    assert "reviewer" in out
    assert "No changes made" in out


def test_team_status_json(capsys, monkeypatch):
    monkeypatch.setenv("DOTS_DIR", str(ROOT))
    assert main(["team", "status", "--json"]) == 0
    out = capsys.readouterr().out
    assert '"openrig"' in out
    assert '"routing": "eval-driven"' in out or "eval-driven" in out
