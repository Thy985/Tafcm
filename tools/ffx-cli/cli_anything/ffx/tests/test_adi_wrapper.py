"""Unit tests for the ADI wrapper (issue #325).

adi.dart resolves its store as Directory.current/.adi, so the wrapper must
run it with cwd = project root — not tools/adi — to read the same <root>/.adi
as the App, `dart run tools/adi/adi.dart` and the MCP server. doctor() must
surface both historical .adi locations (with exists markers) so divergent
data stores are discoverable; it never migrates data automatically.
"""
from __future__ import annotations

from pathlib import Path

import pytest

from cli_anything.ffx.core import adi_wrapper as adi_mod


@pytest.fixture()
def fake_dart(monkeypatch):
    """Make shutil.which('dart') succeed without a real Dart SDK."""
    monkeypatch.setattr(
        adi_mod.shutil, "which", lambda name: "dart-fake" if name == "dart" else None
    )


def _make_project(root: Path) -> Path:
    """Create a minimal project root with tools/adi/adi.dart (no runtime .adi)."""
    adi = root / "tools" / "adi"
    adi.mkdir(parents=True)
    (adi / "adi.dart").write_text("void main() {}\n", encoding="utf-8")
    return root


# ── _find_adi_cwd: cwd must be the project root ───────────────────────

class TestFindAdiCwd:
    def test_cwd_is_project_root_not_tools_adi(self, fake_dart, tmp_path):
        root = _make_project(tmp_path)
        cmd, cwd = adi_mod._find_adi_cwd(str(root))
        assert Path(cwd) == root
        assert cmd[-1] == str(root / "tools" / "adi" / "adi.dart")

    def test_cwd_yields_same_adi_store_as_other_consumers(self, fake_dart, tmp_path):
        """Behavioral contract: Directory.current/.adi must be <root>/.adi."""
        root = _make_project(tmp_path)
        _, cwd = adi_mod._find_adi_cwd(str(root))
        assert Path(cwd) / ".adi" == root / ".adi"
        # Regression guard for issue #325: cwd must not point into tools/adi.
        assert Path(cwd).match("tools/adi") is False

    def test_explicit_root_preferred_over_other_candidates(self, fake_dart, tmp_path):
        root = _make_project(tmp_path)
        _, cwd = adi_mod._find_adi_cwd(str(root))
        assert Path(cwd) == root.resolve()


# ── _storage_candidates: both historical .adi locations ───────────────

class TestStorageCandidates:
    def test_both_stores_exist(self, tmp_path):
        (tmp_path / ".adi").mkdir()
        (tmp_path / "tools" / "adi" / ".adi").mkdir(parents=True)
        sc = adi_mod._storage_candidates(str(tmp_path))
        by_label = {c["label"]: c for c in sc["candidates"]}
        assert by_label["project_root"]["path"] == str(tmp_path / ".adi")
        assert by_label["project_root"]["exists"] is True
        assert by_label["tools/adi (legacy)"]["path"] == str(
            tmp_path / "tools" / "adi" / ".adi"
        )
        assert by_label["tools/adi (legacy)"]["exists"] is True
        assert sc["migration_hint"] is None

    def test_only_legacy_exists_hints_migration(self, tmp_path):
        legacy = tmp_path / "tools" / "adi" / ".adi"
        legacy.mkdir(parents=True)
        sc = adi_mod._storage_candidates(str(tmp_path))
        by_label = {c["label"]: c for c in sc["candidates"]}
        assert by_label["project_root"]["exists"] is False
        assert by_label["tools/adi (legacy)"]["exists"] is True
        hint = sc["migration_hint"]
        assert hint is not None
        assert str(legacy) in hint  # points the user at the old data location
        assert "not migrated automatically" in hint.lower()  # no auto-migration

    def test_only_primary_exists_no_hint(self, tmp_path):
        (tmp_path / ".adi").mkdir()
        sc = adi_mod._storage_candidates(str(tmp_path))
        by_label = {c["label"]: c for c in sc["candidates"]}
        assert by_label["project_root"]["exists"] is True
        assert by_label["tools/adi (legacy)"]["exists"] is False
        assert sc["migration_hint"] is None

    def test_neither_exists_no_hint(self, tmp_path):
        sc = adi_mod._storage_candidates(str(tmp_path))
        by_label = {c["label"]: c for c in sc["candidates"]}
        assert by_label["project_root"]["exists"] is False
        assert by_label["tools/adi (legacy)"]["exists"] is False
        assert sc["migration_hint"] is None


# ── doctor(): augments adi.dart output with storage candidates ────────

class TestDoctorAugmentation:
    def _patch_run(self, monkeypatch, result: dict, captured: dict):
        def fake_run(args, cwd=None):
            captured["args"] = args
            captured["cwd"] = cwd
            return dict(result)

        monkeypatch.setattr(adi_mod, "_run_adi", fake_run)

    def test_doctor_includes_both_candidate_paths(self, fake_dart, monkeypatch, tmp_path):
        root = _make_project(tmp_path)
        (root / ".adi").mkdir()
        (root / "tools" / "adi" / ".adi").mkdir(parents=True)
        captured: dict = {}
        self._patch_run(
            monkeypatch,
            {"status": "healthy", "storage": {"exists": True, "path": str(root / ".adi")}},
            captured,
        )
        result = adi_mod.doctor(cwd=str(root))
        assert result["status"] == "healthy"  # original payload preserved
        assert captured["cwd"] == str(root)  # subprocess runs from project root
        by_label = {c["label"]: c for c in result["storage_candidates"]["candidates"]}
        assert by_label["project_root"]["path"] == str(root / ".adi")
        assert by_label["project_root"]["exists"] is True
        assert by_label["tools/adi (legacy)"]["exists"] is True
        assert result["storage_candidates"]["migration_hint"] is None

    def test_doctor_flags_legacy_divergence(self, fake_dart, monkeypatch, tmp_path):
        root = _make_project(tmp_path)
        (root / "tools" / "adi" / ".adi").mkdir(parents=True)
        captured: dict = {}
        self._patch_run(
            monkeypatch,
            {"status": "broken", "storage": {"exists": False, "path": str(root / ".adi")}},
            captured,
        )
        result = adi_mod.doctor(cwd=str(root))
        assert result["status"] == "broken"
        by_label = {c["label"]: c for c in result["storage_candidates"]["candidates"]}
        assert by_label["project_root"]["exists"] is False
        assert by_label["tools/adi (legacy)"]["exists"] is True
        assert result["storage_candidates"]["migration_hint"] is not None

    def test_doctor_augments_error_result_gracefully(self, fake_dart, monkeypatch, tmp_path):
        """adi.dart failure must not drop the storage-candidates presentation."""
        root = _make_project(tmp_path)
        captured: dict = {}
        self._patch_run(
            monkeypatch,
            {"status": "error", "stderr": "boom", "exit_code": 255},
            captured,
        )
        result = adi_mod.doctor(cwd=str(root))
        assert result["status"] == "error"
        by_label = {c["label"]: c for c in result["storage_candidates"]["candidates"]}
        assert by_label["project_root"]["path"] == str(root / ".adi")
        # Fresh project: neither store exists, so no migration hint.
        assert result["storage_candidates"]["migration_hint"] is None
