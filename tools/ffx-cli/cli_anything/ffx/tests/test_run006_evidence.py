"""Run #006 evidence assertions — three no-human-intervention conditions.

Tests the Agent harness's evidence contract WITHOUT running the full loop:

    C1_agent_discovers      -> Agent only saw ffx adi observations
    C2_agent_decides_patch  -> production source modified (git diff audit)
    C3_agent_judges_success -> success judged via ADI validate, not self-report

`verify_evidence()` is a pure function: it audits an Agent-produced evidence
JSON (or any candidate evidence) and returns violations. An empty list means
the three conditions + six predicates + production patch all hold.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[5]  # math2/
sys.path.insert(0, str(PROJECT_ROOT / "tools" / "adi"))
sys.path.insert(0, str(PROJECT_ROOT / "tools" / "ffx-cli"))

from run006_agent import verify_evidence  # noqa: E402


def _valid_evidence() -> dict:
    """A minimally complete evidence doc that must pass every audit rule."""
    return {
        "run": "006",
        "status": "autonomous_agent_repair_proven",
        "conditions": {
            "C1_agent_discovers": True,
            "C2_agent_decides_patch": True,
            "C3_agent_judges_success": True,
        },
        "patch": {
            "file": "flutter_app/lib/presentation/blocks/code/code_block.dart",
            "diff_stat": " 1 file changed, 4 insertions(+), 4 deletions(-)",
        },
        "predicates": {
            "P1_before_reproduced": True,
            "P2_patch_authenticity": True,
            "P3_fresh_runtime_fixed": True,
            "P4_invariants_pass": True,
            "P5_replay_not_reproduced": True,
            "P6_capability_e2e_pass": True,
        },
    }


class TestThreeConditions:
    def test_valid_evidence_passes(self):
        assert verify_evidence(_valid_evidence()) == []

    @pytest.mark.parametrize("key", [
        "C1_agent_discovers",
        "C2_agent_decides_patch",
        "C3_agent_judges_success",
    ])
    def test_condition_false_is_violation(self, key):
        ev = _valid_evidence()
        ev["conditions"][key] = False
        violations = verify_evidence(ev)
        assert f"{key} != true" in violations

    def test_missing_condition_is_violation(self):
        ev = _valid_evidence()
        ev["conditions"] = {}
        violations = verify_evidence(ev)
        assert "C1_agent_discovers != true" in violations
        assert "C2_agent_decides_patch != true" in violations
        assert "C3_agent_judges_success != true" in violations


class TestGitDiffAudit:
    def test_patch_file_must_be_production_code(self):
        ev = _valid_evidence()
        ev["patch"]["file"] = "flutter_app/test/observability/run006_test.dart"
        violations = verify_evidence(ev)
        assert any("not production code" in v for v in violations)

    def test_missing_patch_file_is_violation(self):
        ev = _valid_evidence()
        ev["patch"] = {"diff_stat": " 1 file changed"}
        assert "patch.file missing" in verify_evidence(ev)

    def test_empty_diff_stat_is_violation(self):
        ev = _valid_evidence()
        ev["patch"]["diff_stat"] = ""
        violations = verify_evidence(ev)
        assert any("patch.diff_stat empty" in v for v in violations)


class TestPredicates:
    @pytest.mark.parametrize("key", [
        "P1_before_reproduced",
        "P2_patch_authenticity",
        "P3_fresh_runtime_fixed",
        "P4_invariants_pass",
        "P5_replay_not_reproduced",
        "P6_capability_e2e_pass",
    ])
    def test_predicate_false_is_violation(self, key):
        ev = _valid_evidence()
        ev["predicates"][key] = False
        assert f"{key} != true" in verify_evidence(ev)


class TestVerifyCli:
    def test_verify_cli_passes_valid_evidence(self, tmp_path):
        """python run006_agent.py --verify <json> exits 0 on valid evidence."""
        import json
        import subprocess
        evidence_path = tmp_path / "evidence.json"
        evidence_path.write_text(
            json.dumps(_valid_evidence()), encoding="utf-8")
        r = subprocess.run(
            [sys.executable, str(PROJECT_ROOT / "tools/adi/run006_agent.py"),
             "--verify", str(evidence_path)],
            capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        assert "verify_passed" in r.stdout

    def test_verify_cli_rejects_tampered_evidence(self, tmp_path):
        """CLI exits 1 when a condition is violated."""
        import json
        import subprocess
        ev = _valid_evidence()
        ev["conditions"]["C3_agent_judges_success"] = False
        evidence_path = tmp_path / "evidence.json"
        evidence_path.write_text(json.dumps(ev), encoding="utf-8")
        r = subprocess.run(
            [sys.executable, str(PROJECT_ROOT / "tools/adi/run006_agent.py"),
             "--verify", str(evidence_path)],
            capture_output=True, text=True)
        assert r.returncode == 1
        assert "verify_failed" in r.stdout
        assert "C3_agent_judges_success != true" in r.stdout
