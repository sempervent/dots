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
            assert "quantum-cabbage" in rendered
            assert "Fake Widget" in rendered
            assert "Fake Bundle" in rendered
            assert "Synthetic Labs" in rendered

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
            await pilot.pause()
            body = str(app.query_one("#upgrade-body").render())
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

