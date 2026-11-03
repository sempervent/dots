"""OpenRig roles, templates, and RigSpec fixtures."""

from __future__ import annotations

from pathlib import Path

from dots_agent.openrig.roles import load_roles, role_names_for_template
from dots_agent.openrig.specs import list_templates, render_team_bundle

ROOT = Path(__file__).resolve().parents[3]


def test_roles_loaded():
    roles, defaults = load_roles(ROOT / "configs" / "agents" / "openrig" / "roles.toml")
    assert set(roles) >= {"lead", "builder", "reviewer", "investigator"}
    assert roles["reviewer"].write is False
    assert roles["reviewer"].sandbox == "read_only"
    assert roles["builder"].write is True
    assert defaults.team_budget_usd == 3.0
    assert defaults.max_review_rounds == 2


def test_templates_present():
    names = list_templates(ROOT)
    assert names == ["dots-pair", "dots-triad", "dots-investigate"]


def test_render_bundle(tmp_path: Path):
    project = tmp_path / "proj"
    project.mkdir()
    bundle = render_team_bundle(
        "dots-triad",
        project=project,
        staging_root=tmp_path / "staging",
        repo_root=ROOT,
    )
    assert Path(bundle["rig_yaml"]).is_file()
    assert (Path(bundle["staging"]) / "agents" / "lead" / "agent.yaml").is_file()
    assert (Path(bundle["staging"]) / "agents" / "reviewer" / "agent.yaml").is_file()
    roles = {s["role"] for s in bundle["seats"]}
    assert roles == {"lead", "builder", "reviewer"}


def test_pair_roles():
    _, defaults = load_roles(ROOT / "configs" / "agents" / "openrig" / "roles.toml")
    assert role_names_for_template("dots-pair", defaults) == ("lead", "builder")
