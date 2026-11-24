"""Headless Textual Pilot and dynamic registry tests for the DOTS v1.11 lifecycle TUI."""

from __future__ import annotations

import asyncio
import hashlib
import os
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]


@pytest.fixture
def isolated_env(tmp_path, monkeypatch):
    home = tmp_path / "home"
    (home / ".config" / "dots" / "profiles").mkdir(parents=True)
    (home / ".local" / "state" / "dots" / "backups").mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("DOTS_DIR", str(ROOT))
    monkeypatch.setenv("NO_COLOR", "1")
    for k in (
        "DOTS_PROFILE",
        "DOTS_ACTIVE_COMPONENTS",
        "DOTS_PACKAGE_GROUPS",
        "DOTS_MULTIPLEXER",
        "DOTS_PROFILE_FILE",
        "DOTS_GROUPS_REGISTRY",
        "DOTS_COMPONENTS_REGISTRY",
        "DOTS_FORCE_OS",
        "DOTS_FORCE_DARWIN_MAJOR",
        "DOTS_PKG_MOCK_FORMULAE",
        "DOTS_PKG_MOCK_CASKS",
        "DOTS_PKG_MOCK_OUTDATED_FORMULAE",
        "DOTS_PKG_MOCK_OUTDATED_CASKS",
    ):
        monkeypatch.delenv(k, raising=False)
    return home


def _write_active(home: Path, name: str, profile_file: Path, groups: str = "core modern", comps: str = "") -> None:
    (home / ".config" / "dots" / "active-profile").write_text(
        f"DOTS_PROFILE='{name}'\n"
        f"DOTS_PROFILE_FILE='{profile_file}'\n"
        f"DOTS_PACKAGE_GROUPS='{groups}'\n"
        f"DOTS_ACTIVE_COMPONENTS='{comps}'\n"
        f"DOTS_LAST_WITH_INFO='{comps}'\n",
        encoding="utf-8",
    )


def test_version_synchronized_with_repo_version():
    import dots_help
    from dots_help.registry import Registry

    repo_ver = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    assert dots_help.__version__ == repo_ver
    assert Registry(ROOT).version() == repo_ver


def test_dynamic_synthetic_registry_groups_components_supergroups(isolated_env, tmp_path):
    from dots_help.backend import DotsBackend
    from dots_help.model import DesiredStateModel
    from dots_help.tui import DotsTuiApp

    _write_active(isolated_env, "base", ROOT / "configs" / "bootstrap" / "profiles" / "base.toml")

    syn_groups = tmp_path / "groups.toml"
    syn_groups.write_text(
        'version = 1\n\n'
        '[[groups]]\nname = "core"\ndescription = "Core"\nrequired = ["bash"]\noptional = []\n\n'
        '[[groups]]\nname = "modern"\ndescription = "Modern"\nrequired = ["bat"]\noptional = []\n\n'
        '[[groups]]\nname = "quantum-cabbage"\ndescription = "Synthetic quantum cabbage tools"\n'
        'required = ["cabbage-cli"]\noptional = ["quantum-probe"]\n',
        encoding="utf-8",
    )
    syn_comps = tmp_path / "components.toml"
    syn_comps.write_text(
        'version = 1\n\n'
        '[[components]]\nid = "fake-widget"\nlabel = "Fake Widget"\n'
        'category = "synthetic_labs"\nplatforms = ["darwin", "linux"]\n'
        'description = "Synthetic dynamic widget"\n\n'
        '[[supergroups]]\nid = "fake-bundle"\nlabel = "Fake Bundle"\n'
        'description = "Synthetic bundle"\nmembers = ["fake-widget"]\n',
        encoding="utf-8",
    )

    backend = DotsBackend(
        root=ROOT,
        env_overrides={
            "DOTS_GROUPS_REGISTRY": str(syn_groups),
            "DOTS_COMPONENTS_REGISTRY": str(syn_comps),
        },
    )
    model = DesiredStateModel(backend)
    model.load()
    assert any(g.id == "quantum-cabbage" for g in model.groups)
    assert any(c.id == "fake-widget" for c in model.components)
    assert any(s.id == "fake-bundle" and s.members == ["fake-widget"] for s in model.supergroups)

    async def _run() -> None:
        app = DotsTuiApp(backend=backend, dry_run=True)
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            lv = app.query_one("#capability-list")
            rendered = "\n".join(str(lbl.render()) for lbl in lv.query("Label"))
            assert "Fake Widget" in rendered
            assert "Fake Bundle" in rendered
            assert "Synthetic Labs" in rendered
            # Unknown formulae make the synthetic group unavailable, so it stays
            # hidden until Show unavailable.
            if "quantum-cabbage" not in rendered:
                await pilot.click("#btn-toggle-unsup")
                await pilot.pause()
                rendered = "\n".join(str(lbl.render()) for lbl in lv.query("Label"))
            assert "quantum-cabbage" in rendered

    asyncio.run(_run())


def test_platform_filtering_darwin_linux_and_darwin_version(isolated_env):
    from dots_help.backend import DotsBackend
    from dots_help.model import DesiredStateModel, SelectionState

    _write_active(isolated_env, "base", ROOT / "configs" / "bootstrap" / "profiles" / "base.toml")

    # Linux: karabiner-elements (darwin-only) visible & disabled with reason
    m_linux = DesiredStateModel(
        DotsBackend(root=ROOT, env_overrides={"DOTS_FORCE_OS": "linux"})
    )
    m_linux.load()
    karab_l = m_linux.get("component:karabiner-elements")
    assert karab_l is not None
    assert not karab_l.supported
    assert karab_l.working == SelectionState.UNSUPPORTED
    assert "macOS" in karab_l.unsupported_reason
    ok, _ = m_linux.toggle("component:karabiner-elements")
    assert not ok

    # Darwin 14: fluidvoice (min_darwin = "15") disabled with reason
    m_d14 = DesiredStateModel(
        DotsBackend(
            root=ROOT,
            env_overrides={"DOTS_FORCE_OS": "darwin", "DOTS_FORCE_DARWIN_MAJOR": "14"},
        )
    )
    m_d14.load()
    fv14 = m_d14.get("component:fluidvoice")
    assert fv14 is not None
    assert not fv14.supported
    assert "15" in fv14.unsupported_reason

    # Darwin 15: fluidvoice supported and toggleable
    m_d15 = DesiredStateModel(
        DotsBackend(
            root=ROOT,
            env_overrides={"DOTS_FORCE_OS": "darwin", "DOTS_FORCE_DARWIN_MAJOR": "15"},
        )
    )
    m_d15.load()
    fv15 = m_d15.get("component:fluidvoice")
    assert fv15 is not None
    assert fv15.supported
    ok15, _ = m_d15.toggle("component:fluidvoice")
    assert ok15


def test_selection_states_inherited_local_excluded_absent(isolated_env):
    from dots_help.backend import DotsBackend
    from dots_help.model import DesiredStateModel, SelectionState

    overlay = isolated_env / ".config" / "dots" / "profiles" / "base-local.toml"
    # Use base-local extending base for clear absent + local + excluded + inherited
    overlay.write_text(
        "# DOTS managed profile overlay\n\n"
        '[profile]\nname = "base-local"\nextends = "base"\n\n'
        '[packages]\nadd = ["geo"]\nremove = ["modern"]\n\n'
        '[components]\nwith = ["herdr"]\n',
        encoding="utf-8",
    )
    _write_active(isolated_env, "base-local", overlay, groups="core geo", comps="herdr")

    m = DesiredStateModel(
        DotsBackend(root=ROOT, env_overrides={"DOTS_FORCE_OS": "linux"})
    )
    m.load()
    assert m.get("group:core").working == SelectionState.INHERITED
    assert m.get("group:geo").working == SelectionState.LOCAL_ADD
    assert m.get("group:modern").working == SelectionState.LOCAL_EXCLUDE
    assert m.get("group:dev").working == SelectionState.NOT_SELECTED
    assert m.get("component:herdr").working == SelectionState.LOCAL_ADD
    assert m.get("component:karabiner-elements").working == SelectionState.UNSUPPORTED

    # Non-color text tags & glyphs exist for every state
    for st in SelectionState:
        assert st.glyph()
        assert st.tag

    # Toggle inherited -> excluded, then back -> inherited (0 pending)
    m.toggle("group:core")
    assert m.get("group:core").working == SelectionState.LOCAL_EXCLUDE
    assert m.pending_removes() == ["group:core"]
    m.toggle("group:core")
    assert m.get("group:core").working == SelectionState.INHERITED
    assert not m.has_unsaved_changes


def test_package_search_and_owner_resolution(isolated_env):
    from dots_help.backend import DotsBackend
    from dots_help.model import DesiredStateModel

    _write_active(isolated_env, "base", ROOT / "configs" / "bootstrap" / "profiles" / "base.toml")
    backend = DotsBackend(root=ROOT)
    model = DesiredStateModel(backend)
    model.load()

    expected = {
        "hyperfine": "group:dev",
        "yazi": "group:workstation",
        "sshuttle": "group:network",
        "ssh-audit": "group:security",
        "karabiner-elements": "component:karabiner-elements",
    }
    for pkg, owner in expected.items():
        res = backend.resolve_selector(pkg)
        assert res["status"] == "ok"
        assert res["owner"] == owner
        hits = model.search(pkg)
        assert hits, f"search missing {pkg}"

    # Ambiguous owner: taplo belongs to component:lsp and group:dev
    amb = backend.resolve_selector("taplo")
    assert amb["status"] == "ambiguous"
    assert set(amb["choices"]) >= {"component:lsp", "group:dev"}


def test_builtin_protection_batch_save_only_and_discard_pilot(isolated_env, tmp_path):
    from dots_help.backend import DotsBackend
    from dots_help.model import SelectionState
    from dots_help.tui import DotsTuiApp

    home_toml = ROOT / "configs" / "bootstrap" / "profiles" / "home.toml"
    home_hash_before = hashlib.sha256(home_toml.read_bytes()).hexdigest()
    _write_active(isolated_env, "home", home_toml)

    boot_log = tmp_path / "boot.log"
    mock_boot = tmp_path / "mock-boot.sh"
    mock_boot.write_text(
        f'#!/usr/bin/env bash\necho "boot $*" >> "{boot_log}"\nexit 0\n',
        encoding="utf-8",
    )
    mock_boot.chmod(0o755)

    backend = DotsBackend(
        root=ROOT,
        env_overrides={
            "DOTS_FORCE_OS": "darwin",
            "DOTS_FORCE_DARWIN_MAJOR": "15",
            "DOTS_BOOTSTRAP_SH": str(mock_boot),
            "DOTS_PKG_MOCK_FORMULAE": "bash\njq",
            "DOTS_PKG_MOCK_CASKS": "",
        },
    )

    # 1) Discard test: toggle items, then discard -> zero file writes
    async def _test_discard() -> None:
        app = DotsTuiApp(backend=backend, dry_run=False)
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            app.model.toggle("group:network")
            app.model.toggle("component:karabiner-elements")
            assert app.model.has_unsaved_changes
            app.action_discard()
            await pilot.pause()
            assert not app.model.has_unsaved_changes

    asyncio.run(_test_discard())
    assert not (isolated_env / ".config" / "dots" / "profiles" / "home-local.toml").exists()
    assert not boot_log.exists()

    # 2) Dry-run save/apply -> zero file writes
    async def _test_dry_run() -> None:
        app = DotsTuiApp(backend=backend, dry_run=True)
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            app.model.toggle("component:karabiner-elements")
            app.action_save_only()
            app.action_save_apply()
            await pilot.pause()

    asyncio.run(_test_dry_run())
    assert not (isolated_env / ".config" / "dots" / "profiles" / "home-local.toml").exists()
    assert not boot_log.exists()

    # 3) Batch Save Only: remove network + add karabiner-elements -> one atomic overlay write, 0 bootstrap calls
    async def _test_save_only() -> None:
        app = DotsTuiApp(backend=backend, dry_run=False)
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            app.model.toggle("group:network")
            app.model.toggle("component:karabiner-elements")
            await pilot.press("p")
            await pilot.pause()
            # Close preview modal via Back
            await pilot.press("escape")
            await pilot.pause()
            await pilot.press("s")
            await pilot.pause()

    asyncio.run(_test_save_only())
    home_hash_after = hashlib.sha256(home_toml.read_bytes()).hexdigest()
    assert home_hash_before == home_hash_after
    overlay = isolated_env / ".config" / "dots" / "profiles" / "home-local.toml"
    assert overlay.is_file()
    ov_text = overlay.read_text(encoding="utf-8")
    assert "# DOTS managed profile overlay" in ov_text
    assert 'extends = "home"' in ov_text
    assert '"network"' in ov_text
    assert '"karabiner-elements"' in ov_text
    assert not boot_log.exists()

    # Reload model and confirm persisted states match
    m2 = backend.profile_show()
    assert m2["groups"]["network"]["state"] == SelectionState.LOCAL_EXCLUDE.value
    assert m2["components"]["karabiner-elements"]["state"] == SelectionState.LOCAL_ADD.value


def test_batch_save_and_apply_runs_bootstrap_once_and_preserves_custom(isolated_env, tmp_path):
    from dots_help.backend import DotsBackend
    from dots_help.tui import DotsTuiApp

    custom = isolated_env / ".config" / "dots" / "profiles" / "bertha.toml"
    custom.write_text(
        '# Hand-authored custom profile\n'
        '[profile]\nname = "bertha"\nextends = "server"\ndescription = "Custom"\n',
        encoding="utf-8",
    )
    custom_hash1 = hashlib.sha256(custom.read_bytes()).hexdigest()
    _write_active(isolated_env, "bertha", custom, groups="core modern server")

    boot_log = tmp_path / "boot-apply.log"
    mock_boot = tmp_path / "mock-boot-ok.sh"
    mock_boot.write_text(
        f'#!/usr/bin/env bash\necho "apply $*" >> "{boot_log}"\nexit 0\n',
        encoding="utf-8",
    )
    mock_boot.chmod(0o755)

    backend = DotsBackend(
        root=ROOT,
        env_overrides={
            "DOTS_FORCE_OS": "linux",
            "DOTS_BOOTSTRAP_SH": str(mock_boot),
            "DOTS_PKG_MOCK_FORMULAE": "",
            "DOTS_PKG_MOCK_CASKS": "",
        },
    )

    async def _run() -> None:
        app = DotsTuiApp(backend=backend, dry_run=False)
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            app.model.toggle("group:dev")
            app.model.toggle("group:geo")
            app.action_save_apply()
            await pilot.pause(0.5)
            # Close ApplyProgressModal once worker completes
            closed = False
            for _ in range(150):
                await pilot.pause(0.1)
                if len(app.screen_stack) > 1:
                    btn = app.screen.query_one("#btn-close")
                    if not btn.disabled:
                        await pilot.click("#btn-close")
                        closed = True
                        break
            assert closed, "ApplyProgressModal did not complete in time"
            await pilot.pause()

    asyncio.run(_run())
    custom_hash2 = hashlib.sha256(custom.read_bytes()).hexdigest()
    assert custom_hash1 == custom_hash2
    ov = isolated_env / ".config" / "dots" / "profiles" / "bertha-local.toml"
    assert ov.is_file()
    ov_text = ov.read_text(encoding="utf-8")
    assert '"dev"' in ov_text and '"geo"' in ov_text
    assert boot_log.is_file()
    assert len(boot_log.read_text(encoding="utf-8").splitlines()) == 1


def test_apply_failure_preserves_saved_overlay_and_external_hash_conflict(isolated_env, tmp_path):
    from dots_help.backend import DotsBackend
    from dots_help.tui import DotsTuiApp

    _write_active(isolated_env, "base", ROOT / "configs" / "bootstrap" / "profiles" / "base.toml")
    mock_fail = tmp_path / "mock-boot-fail.sh"
    mock_fail.write_text("#!/usr/bin/env bash\necho 'boom'\nexit 1\n", encoding="utf-8")
    mock_fail.chmod(0o755)

    backend = DotsBackend(
        root=ROOT,
        env_overrides={
            "DOTS_FORCE_OS": "linux",
            "DOTS_BOOTSTRAP_SH": str(mock_fail),
            "DOTS_PKG_MOCK_FORMULAE": "",
            "DOTS_PKG_MOCK_CASKS": "",
        },
    )

    async def _run() -> None:
        app = DotsTuiApp(backend=backend, dry_run=False)
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            app.model.toggle("group:dev")
            app.action_save_apply()
            closed = False
            for _ in range(150):
                await pilot.pause(0.1)
                if len(app.screen_stack) > 1:
                    btn = app.screen.query_one("#btn-close")
                    if not btn.disabled:
                        result_text = str(app.screen.query_one("#apply-result").render())
                        assert "Desired state saved successfully" in result_text
                        assert "Machine convergence failed" in result_text
                        await pilot.click("#btn-close")
                        closed = True
                        break
            assert closed, "ApplyProgressModal did not complete in time"
            await pilot.pause()

    asyncio.run(_run())
    assert (isolated_env / ".config" / "dots" / "profiles" / "base-local.toml").is_file()

    # External hash conflict detection
    res = backend.profile_mutate(
        ["group:geo"],
        [],
        expected_hash="0" * 64,
    )
    assert not res.ok
    assert "changed on disk" in res.combined.lower()


def test_upgrade_screen_and_small_terminal_and_unsaved_quit(isolated_env):
    from dots_help.backend import DotsBackend
    from dots_help.tui import DotsTuiApp

    _write_active(isolated_env, "base", ROOT / "configs" / "bootstrap" / "profiles" / "base.toml")
    backend = DotsBackend(
        root=ROOT,
        env_overrides={
            "DOTS_PKG_MOCK_FORMULAE": "jq\nhyperfine\nglow",
            "DOTS_PKG_MOCK_CASKS": "",
            "DOTS_PKG_MOCK_OUTDATED_FORMULAE": "jq\nhyperfine\nglow",
            "DOTS_PKG_MOCK_OUTDATED_CASKS": "",
        },
    )

    async def _run() -> None:
        # Small terminal renders too-small guard without crashing
        app_sm = DotsTuiApp(backend=backend, dry_run=True)
        async with app_sm.run_test(size=(48, 12)) as pilot:
            await pilot.pause()
            assert app_sm.query_one("#too-small").styles.display == "block"
            assert app_sm.query_one("#main-tabs").styles.display == "none"

        # Upgrade tab uses --dry-run --json and distinguishes managed vs excluded/undeclared
            app = DotsTuiApp(backend=backend, dry_run=True, initial_tab="tab-upgrade")
            async with app.run_test(size=(120, 40)) as pilot:
                await pilot.pause()
                app.query_one("#upgrade-pane").ensure_loaded()
                body = ""
                for _ in range(100):
                    await pilot.pause(0.5)
                    body = str(app.query_one("#upgrade-body").render())
                    if "Managed updates" in body or "Unable to check" in body:
                        break
            assert "Managed updates" in body
            assert "jq" in body
            assert "Excluded" in body
            assert "hyperfine" in body
            assert "Undeclared" in body
            assert "glow" in body

        # Quit with unsaved changes opens UnsavedChangesModal
        app_q = DotsTuiApp(backend=backend, dry_run=True)
        async with app_q.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            app_q.model.toggle("group:dev")
            await pilot.press("q")
            await pilot.pause()
            assert len(app_q.screen_stack) > 1
            await pilot.click("#btn-discard")
            await pilot.pause()

    asyncio.run(_run())


def test_python_tui_has_no_direct_toml_writes_or_pkg_manager_calls():
    import ast

    pkg_dir = ROOT / "tools" / "dots_help" / "dots_help"
    forbidden_subprocesses = re.compile(r"\b(brew|apt-get|apt|dnf|pacman|xbps-install)\b")
    for py_file in pkg_dir.rglob("*.py"):
        text = py_file.read_text(encoding="utf-8")
        tree = ast.parse(text, filename=str(py_file))
        for node in ast.walk(tree):
            if isinstance(node, ast.Call):
                for kw in node.keywords:
                    if kw.arg == "shell" and isinstance(kw.value, ast.Constant) and kw.value.value is True:
                        raise AssertionError(f"shell=True forbidden in {py_file}")
                if isinstance(node.func, ast.Attribute) and node.func.attr in ("write_text", "write_bytes"):
                    raise AssertionError(f"direct file write {node.func.attr} forbidden in {py_file}")
                if isinstance(node.func, ast.Name) and node.func.id == "open":
                    for arg in node.args[1:2]:
                        if isinstance(arg, ast.Constant) and isinstance(arg.value, str) and "w" in arg.value:
                            raise AssertionError(f"direct open(..., 'w') forbidden in {py_file}")
            if isinstance(node, ast.Constant) and isinstance(node.value, str):
                # Ignore docstrings (Expr(Constant(str)))
                pass
        if py_file.name == "backend.py":
            code_lines = [
                ln for ln in text.splitlines()
                if not ln.strip().startswith("#") and "never" not in ln.lower()
            ]
            for ln in code_lines:
                assert not forbidden_subprocesses.search(ln), f"direct pkg mgr in {py_file}: {ln}"
        # Ensure TUI does not hard-code package installability names
        assert "tflint" not in text.lower(), f"hard-coded package name tflint in {py_file}"
        assert "opentofu" not in text.lower(), f"hard-coded package name opentofu in {py_file}"


def test_tui_package_installability_search_and_group_counts(isolated_env):
    from dots_help.backend import DotsBackend
    from dots_help.model import DesiredStateModel
    from dots_help.tui import DotsTuiApp

    _write_active(isolated_env, "base", ROOT / "configs" / "bootstrap" / "profiles" / "base.toml")
    backend = DotsBackend(
        root=ROOT,
        env_overrides={
            "DOTS_FORCE_OS": "darwin",
            "DOTS_FORCE_PKG_MGR": "brew",
            "DOTS_PKG_DISABLE_HOST_WHICH": "1",
            "DOTS_PKG_MOCK_FORMULAE": "opentofu",
            "DOTS_PKG_MOCK_CASKS": "",
        },
    )
    model = DesiredStateModel(backend)
    model.load()

    infra = model.get("group:infra")
    assert infra is not None
    assert infra.package_count == 17
    assert infra.supported_package_count == 16
    assert infra.unsupported_package_count == 1
    assert "tflint" in infra.unsupported_packages

    tl_hits = [h for h in model.search("tflint") if h.kind == "package" and h.target_id == "tflint"]
    assert tl_hits, "tflint search hit missing"
    assert tl_hits[0].installable is False
    assert "unavailable through DOTS" in tl_hits[0].subtitle
    assert "infra" in tl_hits[0].subtitle

    tofu_hits = [h for h in model.search("opentofu") if h.kind == "package" and h.target_id == "opentofu"]
    assert tofu_hits, "opentofu search hit missing"
    assert tofu_hits[0].installable is True
    assert tofu_hits[0].installed is True
    assert "Installable: yes" in tofu_hits[0].subtitle
    assert "Installed: yes" in tofu_hits[0].subtitle

    async def _run() -> None:
        app = DotsTuiApp(backend=backend, dry_run=True)
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            lv = app.query_one("#capability-list")
            rendered = "\n".join(str(lbl.render()) for lbl in lv.query("Label"))
            assert "16/17 avail" in rendered

    asyncio.run(_run())


def test_explicit_leaf_staging_does_not_enable_owner(isolated_env, monkeypatch):
    from dots_help.backend import DotsBackend
    from dots_help.model import DesiredStateModel, SelectionState

    monkeypatch.setenv("DOTS_FORCE_OS", "darwin")
    monkeypatch.setenv("DOTS_FORCE_PKG_MGR", "brew")
    monkeypatch.setenv("DOTS_FORCE_DARWIN_MAJOR", "15")
    _write_active(isolated_env, "base", ROOT / "configs" / "bootstrap" / "profiles" / "base.toml")
    model = DesiredStateModel(DotsBackend(ROOT))
    model.load("base")
    ray = model.get("package:raycast")
    assert ray is not None
    assert ray.leaf_selectable is True
    assert ray.owner == "component:mactools"
    assert ray.persisted == SelectionState.NOT_SELECTED
    ok, _msg = model.toggle("package:raycast")
    assert ok
    assert model.pending_package_adds() == ["raycast"]
    assert "component:mactools" not in model.pending_adds()
    hits = [h for h in model.search("raycast") if h.target_id == "raycast"]
    assert hits and hits[0].leaf_selectable is True
    model.discard()
    assert model.pending_package_adds() == []

    monkeypatch.setenv("DOTS_FORCE_OS", "linux")
    monkeypatch.setenv("DOTS_FORCE_PKG_MGR", "apt")
    linux_model = DesiredStateModel(DotsBackend(ROOT))
    linux_model.load("base")
    linux_ray = linux_model.get("package:raycast")
    assert linux_ray is not None
    assert linux_ray.supported is False
    ok, _msg = linux_model.toggle("package:raycast")
    assert ok is False


def test_set_desired_is_deterministic_and_refuses_invalid_leaves():
    from dots_help.model import CapabilityItem, DesiredStateModel, SelectionState
    from dots_help.backend import DotsBackend

    model = DesiredStateModel(DotsBackend(ROOT))
    pkg = CapabilityItem(
        kind="package",
        id="raycast",
        label="Raycast",
        description="",
        persisted=SelectionState.NOT_SELECTED,
        working=SelectionState.NOT_SELECTED,
        leaf_selectable=True,
        supported=True,
    )
    model._by_selector[pkg.selector] = pkg
    ok, _msg = model.set_desired("package:raycast", True)
    assert ok and pkg.working == SelectionState.LOCAL_ADD
    ok, _msg = model.set_desired("package:raycast", True)
    assert ok and pkg.working == SelectionState.LOCAL_ADD
    ok, _msg = model.set_desired("package:raycast", False)
    assert ok and pkg.working == SelectionState.NOT_SELECTED

    inherited = CapabilityItem(
        kind="package",
        id="qgis",
        label="QGIS",
        description="",
        persisted=SelectionState.INHERITED,
        working=SelectionState.INHERITED,
        leaf_selectable=True,
        supported=True,
    )
    model._by_selector[inherited.selector] = inherited
    model.set_desired("package:qgis", False)
    assert inherited.working == SelectionState.LOCAL_EXCLUDE
    model.set_desired("package:qgis", True)
    assert inherited.working == SelectionState.INHERITED

    blocked = CapabilityItem(
        kind="package",
        id="openrig-cli",
        label="OpenRig",
        description="",
        leaf_selectable=False,
        leaf_reason="requires component lifecycle",
        supported=True,
    )
    model._by_selector[blocked.selector] = blocked
    ok, msg = model.set_desired("package:openrig-cli", True)
    assert ok is False and "independently" in msg

    unsupported = CapabilityItem(
        kind="package",
        id="raycast-linux",
        label="Raycast",
        description="",
        supported=False,
        unsupported_reason="requires macOS",
        leaf_selectable=True,
    )
    model._by_selector[unsupported.selector] = unsupported
    ok, msg = model.set_desired(unsupported.selector, True)
    assert ok is False and "unavailable" in msg.lower()


def test_catalog_view_filter_and_unsupported_default():
    from dots_help.model import CapabilityItem, SelectionState
    from dots_help.screens.manage import item_matches_view

    pkg = CapabilityItem(kind="package", id="raycast", label="Raycast", description="", supported=True)
    group = CapabilityItem(kind="group", id="dev", label="dev", description="", supported=True)
    comp = CapabilityItem(kind="component", id="mactools", label="macOS tools", description="", supported=True)
    bundle = CapabilityItem(kind="supergroup", id="ai", label="AI", description="", supported=True)
    hidden = CapabilityItem(
        kind="package",
        id="hidden",
        label="Hidden",
        description="",
        supported=False,
        unsupported_reason="requires macOS",
    )
    selected = CapabilityItem(
        kind="group",
        id="geo",
        label="geo",
        description="",
        supported=True,
        persisted=SelectionState.NOT_SELECTED,
        working=SelectionState.LOCAL_ADD,
    )
    assert item_matches_view(pkg, "individual", show_unsupported=False)
    assert not item_matches_view(group, "individual", show_unsupported=False)
    assert item_matches_view(group, "groups", show_unsupported=False)
    assert item_matches_view(comp, "components", show_unsupported=False)
    assert item_matches_view(bundle, "bundles", show_unsupported=False)
    assert item_matches_view(selected, "selected", show_unsupported=False)
    assert item_matches_view(selected, "changes", show_unsupported=False)
    assert not item_matches_view(pkg, "changes", show_unsupported=False)
    assert not item_matches_view(hidden, "all", show_unsupported=False)
    assert item_matches_view(hidden, "all", show_unsupported=True)


def test_search_add_package_stages_without_second_toggle(isolated_env, monkeypatch):
    import asyncio

    from dots_help.backend import DotsBackend
    from dots_help.model import SelectionState
    from dots_help.tui import DotsTuiApp

    monkeypatch.setenv("DOTS_FORCE_OS", "darwin")
    monkeypatch.setenv("DOTS_FORCE_DARWIN_MAJOR", "15")
    monkeypatch.setenv("DOTS_FORCE_PKG_MGR", "brew")
    _write_active(isolated_env, "base", ROOT / "configs" / "bootstrap" / "profiles" / "base.toml")
    backend = DotsBackend(root=ROOT, env_overrides={"DOTS_FORCE_OS": "darwin", "DOTS_FORCE_DARWIN_MAJOR": "15", "DOTS_FORCE_PKG_MGR": "brew"})

    async def _run() -> None:
        app = DotsTuiApp(backend=backend, dry_run=True)
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            await pilot.click("#btn-add-software")
            await pilot.pause()
            for ch in "raycast":
                await pilot.press(ch)
            await pilot.pause()
            await pilot.press("enter")
            await pilot.pause()
            await pilot.click("#btn-add-leaf")
            await pilot.pause()
            item = app.model.get("package:raycast")
            assert item is not None
            assert item.working == SelectionState.LOCAL_ADD
            assert "+package:raycast" in app.model.pending_summary()
            assert "component:mactools" not in app.model.pending_adds()

            app.model.discard()
            await pilot.click("#btn-add-software")
            await pilot.pause()
            for ch in "raycast":
                await pilot.press(ch)
            await pilot.pause()
            await pilot.press("enter")
            await pilot.pause()
            await pilot.click("#btn-owner")
            await pilot.pause()
            assert app.model.get("package:raycast").working == SelectionState.NOT_SELECTED
            owner = app.model.get("component:mactools")
            assert owner is not None and owner.working.is_desired

    asyncio.run(_run())


def test_lifecycle_search_has_no_package_only_action(isolated_env):
    from dots_help.model import SearchHit
    from dots_help.screens.modals import LeafActionModal

    _write_active(isolated_env, "base", ROOT / "configs" / "bootstrap" / "profiles" / "base.toml")

    hit = SearchHit(
        title="OpenRig",
        subtitle="",
        kind="package",
        target_id="openrig-cli",
        owner_selector="component:openrig",
        leaf_selectable=False,
        leaf_reason="requires component lifecycle",
        installable=True,
    )
    from dots_help.tui import DotsTuiApp
    from dots_help.backend import DotsBackend

    app = DotsTuiApp(backend=DotsBackend(ROOT), dry_run=True)

    async def _run() -> None:
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            app.push_screen(LeafActionModal(hit, None))
            await pilot.pause()
            assert list(app.screen.query("#btn-add-leaf")) == []
            assert list(app.screen.query("#btn-owner"))
            app.pop_screen()
            await pilot.pause()
            local_hit = SearchHit(
                title="Raycast",
                subtitle="",
                kind="package",
                target_id="raycast",
                owner_selector="component:mactools",
                leaf_selectable=True,
                installable=True,
            )
            from dots_help.model import CapabilityItem, SelectionState

            local_item = CapabilityItem(
                kind="package",
                id="raycast",
                label="Raycast",
                description="",
                persisted=SelectionState.LOCAL_ADD,
                working=SelectionState.LOCAL_ADD,
                supported=True,
                leaf_selectable=True,
            )
            app.push_screen(LeafActionModal(local_hit, local_item))
            await pilot.pause()
            assert list(app.screen.query("#btn-add-leaf")) == []
            assert list(app.screen.query("#btn-remove-leaf"))

    asyncio.run(_run())


def test_edit_non_active_profile_save_preserves_marker_and_follows_overlay(isolated_env, tmp_path):
    import asyncio

    from dots_help.backend import DotsBackend
    from dots_help.model import SelectionState
    from dots_help.tui import DotsTuiApp

    home = ROOT / "configs" / "bootstrap" / "profiles" / "home.toml"
    work = ROOT / "configs" / "bootstrap" / "profiles" / "work.toml"
    work_hash = hashlib.sha256(work.read_bytes()).hexdigest()
    _write_active(isolated_env, "home", home)
    marker_before = (isolated_env / ".config" / "dots" / "active-profile").read_text(encoding="utf-8")
    backend = DotsBackend(
        root=ROOT,
        env_overrides={"DOTS_FORCE_OS": "darwin", "DOTS_FORCE_DARWIN_MAJOR": "15", "DOTS_FORCE_PKG_MGR": "brew"},
    )

    async def _run() -> None:
        app = DotsTuiApp(backend=backend, dry_run=False, profile=str(work))
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            bar = str(app.query_one("#software-profile-bar").render())
            assert "work" in bar
            assert "home" in bar
            assert app.model.active is False
            assert app.query_one("#software-pane").show_unsupported is False
            app.model.set_desired("package:raycast", True)
            app.action_save_only()
            await pilot.pause()
            assert app.model.profile_file.endswith("work-local.toml")
            ray = app.model.get("package:raycast")
            assert ray is not None and ray.working == SelectionState.LOCAL_ADD
            assert app.model.active is False

    asyncio.run(_run())
    assert hashlib.sha256(work.read_bytes()).hexdigest() == work_hash
    overlay = isolated_env / ".config" / "dots" / "profiles" / "work-local.toml"
    assert overlay.is_file()
    assert "raycast" in overlay.read_text(encoding="utf-8")
    marker_after = (isolated_env / ".config" / "dots" / "active-profile").read_text(encoding="utf-8")
    assert marker_after == marker_before
    assert "home.toml" in marker_after


def test_package_only_pending_summary_is_not_none():
    from dots_help.backend import DotsBackend
    from dots_help.model import CapabilityItem, DesiredStateModel, SelectionState

    model = DesiredStateModel(DotsBackend(ROOT))
    model.explicit_packages.append(
        CapabilityItem(
            kind="package",
            id="raycast",
            label="Raycast",
            description="",
            persisted=SelectionState.NOT_SELECTED,
            working=SelectionState.LOCAL_ADD,
        )
    )
    assert model.pending_summary() == "+package:raycast"
    assert "none" not in model.pending_bar_text()
    assert "+package:raycast" in model.pending_bar_text()

    model.explicit_packages.clear()
    model.explicit_packages.append(
        CapabilityItem(
            kind="package",
            id="qgis",
            label="QGIS",
            description="",
            persisted=SelectionState.LOCAL_ADD,
            working=SelectionState.NOT_SELECTED,
        )
    )
    assert model.pending_summary() == "-package:qgis"


def test_profile_details_render_package_deltas():
    from dots_help.screens.profile import format_profile_details

    text = format_profile_details(
        {
            "profile": "work-local",
            "profile_kind": "overlay",
            "profile_file": "/tmp/work-local.toml",
            "active": False,
            "extends": "work",
            "source_chain": [{"name": "work", "kind": "builtin", "file": "/tmp/work.toml"}],
            "local_additions": {"groups": ["geo"], "components": [], "supergroups": [], "packages": ["raycast"]},
            "local_removals": {"groups": [], "components": [], "supergroups": [], "packages": ["qgis"]},
            "runtime": {},
        },
        editing_file="/tmp/work-local.toml",
    )
    assert "+ package:raycast" in text
    assert "- package:qgis" in text
    assert "+ group:geo" in text
    assert "Editing: yes" in text
    assert "Active:  no" in text


def test_view_filters_package_details_and_unavailable_toggle(isolated_env, monkeypatch):
    from dots_help.backend import DotsBackend
    from dots_help.tui import DotsTuiApp

    monkeypatch.setenv("DOTS_FORCE_OS", "darwin")
    monkeypatch.setenv("DOTS_FORCE_DARWIN_MAJOR", "15")
    monkeypatch.setenv("DOTS_FORCE_PKG_MGR", "brew")
    _write_active(isolated_env, "home", ROOT / "configs" / "bootstrap" / "profiles" / "home.toml")
    backend = DotsBackend(
        root=ROOT,
        env_overrides={
            "DOTS_FORCE_OS": "darwin",
            "DOTS_FORCE_DARWIN_MAJOR": "15",
            "DOTS_FORCE_PKG_MGR": "brew",
        },
    )

    def _labels(app) -> str:
        lv = app.query_one("#capability-list")
        return "\n".join(str(lbl.render()) for lbl in lv.query("Label"))

    async def _run() -> None:
        app = DotsTuiApp(backend=backend, dry_run=True)
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            pane = app.query_one("#software-pane")
            assert pane.show_unsupported is False
            before = _labels(app)
            await pilot.click("#btn-toggle-unsup")
            await pilot.pause()
            after = _labels(app)
            assert pane.show_unsupported is True
            assert "unavailable" in after or after != before
            await pilot.click("#btn-view")
            await pilot.pause()
            individual = _labels(app)
            assert "Individual Software" in individual
            assert "Package Groups" not in individual
            assert "package:" not in individual or "□" in individual
            await pilot.click("#btn-view")
            await pilot.pause()
            groups = _labels(app)
            assert "Package Groups" in groups
            assert "Individual Software" not in groups
            pane.focus_selector("package:raycast")
            await pilot.pause()
            details = str(app.query_one("#details-body").render())
            assert "package:raycast" in details
            assert "Owner:" in details
            assert "Install:" in details
            assert "does not uninstall" in details

    asyncio.run(_run())


def test_edit_selected_and_unsaved_target_change(isolated_env):
    from dots_help.backend import DotsBackend
    from dots_help.tui import DotsTuiApp

    home = ROOT / "configs" / "bootstrap" / "profiles" / "home.toml"
    work = ROOT / "configs" / "bootstrap" / "profiles" / "work.toml"
    _write_active(isolated_env, "home", home)
    marker = (isolated_env / ".config" / "dots" / "active-profile").read_text(encoding="utf-8")
    backend = DotsBackend(
        root=ROOT,
        env_overrides={"DOTS_FORCE_OS": "darwin", "DOTS_FORCE_DARWIN_MAJOR": "15", "DOTS_FORCE_PKG_MGR": "brew"},
    )

    async def _run() -> None:
        app = DotsTuiApp(backend=backend, dry_run=True)
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            app.switch_tab("tab-profile")
            await pilot.pause()
            catalog = app.query_one("#profile-catalog")
            rendered = "\n".join(str(lbl.render()) for lbl in catalog.query("Label"))
            assert "ACTIVE" in rendered
            assert "EDITING" in rendered
            pane = app.query_one("#profile-pane")
            work_idx = next(i for i, p in enumerate(pane._profiles) if p.get("name") == "work")
            catalog.index = work_idx
            await pilot.pause()
            await pilot.click("#btn-edit-selected")
            await pilot.pause()
            assert "work" in app.model.profile_file
            assert app.model.active is False
            app.model.set_desired("package:raycast", True)
            app.request_edit_profile(str(home))
            await pilot.pause()
            assert "Unsaved" in str(app.screen.render()) or list(app.screen.query("#btn-cancel"))
            await pilot.click("#btn-cancel")
            await pilot.pause()
            assert app.model.has_unsaved_changes
            assert "work" in app.model.profile_file
            app.request_edit_profile(str(home))
            await pilot.pause()
            await pilot.click("#btn-discard-target")
            await pilot.pause()
            assert not app.model.has_unsaved_changes
            assert "home" in app.model.profile_name

    asyncio.run(_run())
    assert (isolated_env / ".config" / "dots" / "active-profile").read_text(encoding="utf-8") == marker


def test_save_activate_apply_bootstraps_once(isolated_env, tmp_path):
    from dots_help.backend import DotsBackend
    from dots_help.tui import DotsTuiApp

    home = ROOT / "configs" / "bootstrap" / "profiles" / "home.toml"
    work = ROOT / "configs" / "bootstrap" / "profiles" / "work.toml"
    work_hash = hashlib.sha256(work.read_bytes()).hexdigest()
    _write_active(isolated_env, "home", home)
    boot_log = tmp_path / "boot-activate.log"
    mock_boot = tmp_path / "mock-boot-activate.sh"
    mock_boot.write_text(
        f'#!/usr/bin/env bash\necho "apply $*" >> "{boot_log}"\nexit 0\n',
        encoding="utf-8",
    )
    mock_boot.chmod(0o755)
    backend = DotsBackend(
        root=ROOT,
        env_overrides={
            "DOTS_FORCE_OS": "darwin",
            "DOTS_FORCE_DARWIN_MAJOR": "15",
            "DOTS_FORCE_PKG_MGR": "brew",
            "DOTS_BOOTSTRAP_SH": str(mock_boot),
            "DOTS_PKG_MOCK_FORMULAE": "bash\njq",
            "DOTS_PKG_MOCK_CASKS": "raycast",
        },
    )

    async def _run() -> None:
        app = DotsTuiApp(backend=backend, dry_run=False, profile=str(work))
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            assert app.model.active is False
            app.model.set_desired("package:raycast", True)
            app.action_save_apply()
            await pilot.pause()
            await pilot.click("#btn-yes")
            closed = False
            for _ in range(150):
                await pilot.pause(0.1)
                if len(app.screen_stack) > 1 and list(app.screen.query("#btn-close")):
                    btn = app.screen.query_one("#btn-close")
                    if not btn.disabled:
                        await pilot.click("#btn-close")
                        closed = True
                        break
            assert closed, "Apply progress did not finish"

    asyncio.run(_run())
    assert hashlib.sha256(work.read_bytes()).hexdigest() == work_hash
    assert boot_log.is_file()
    assert len(boot_log.read_text(encoding="utf-8").splitlines()) == 1
    marker = (isolated_env / ".config" / "dots" / "active-profile").read_text(encoding="utf-8")
    assert "work-local.toml" in marker


def test_agent_capabilities_tab_stages_without_writing(isolated_env):
    from dots_help.backend import DotsBackend
    from dots_help.tui import DotsTuiApp

    backend = DotsBackend(root=ROOT)

    async def _run() -> None:
        app = DotsTuiApp(backend=backend, dry_run=True, initial_tab="tab-capabilities")
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            summary = str(app.query_one("#cap-summary").render())
            assert "Agent Capabilities" in summary
            assert "Skills" in summary
            assert "MCP" in summary
            await pilot.click("#cap-view-skills")
            await pilot.pause()
            detail = str(app.query_one("#cap-detail").render())
            assert "systematic-debugging" in detail
            await pilot.click("#cap-view-mcp")
            await pilot.pause()
            detail = str(app.query_one("#cap-detail").render())
            assert "remote_write=" in detail
            assert "dots-model-scout" in detail
            await pilot.click("#cap-view-problems")
            await pilot.pause()
            await pilot.click("#cap-view-updates")
            await pilot.pause()
            app.query_one("#cap-id").value = "hf-cli"
            await pilot.click("#cap-enable")
            await pilot.pause()
            staged = str(app.query_one("#cap-detail").render())
            assert "add skill:hf-cli" in staged
            app.query_one("#cap-id").value = "drawthings"
            await pilot.click("#cap-view-mcp")
            await pilot.click("#cap-enable")
            await pilot.pause()
            await pilot.click("#cap-preview")
            await pilot.pause()
            preview = str(app.query_one("#cap-detail").render())
            assert "hf-cli" in preview
            assert "drawthings" in preview
            assert "Warnings" in preview
            await pilot.click("#cap-cancel")
            await pilot.pause()
            cleared = str(app.query_one("#cap-detail").render())
            assert "Staged" not in cleared

    asyncio.run(_run())
    overlay = isolated_env / ".config" / "dots" / "profiles"
    assert not any(overlay.glob("*.toml"))

