"""FFX Verification Orchestrator 单元测试（Review R5：harness 需 Python 测试）。

覆盖：
- Evidence / EvidenceGraph 基础行为
- MarkdownAdapter.evaluate：pass/warn/fail/inconclusive 分支 +
  R3（unknown_max/blocking_unknown）+ R4（serialize check）
- orchestrator._diff_coverage（before/after 对比）
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from cli_anything.ffx.harness import orchestrator
from cli_anything.ffx.harness.adapters.markdown import MarkdownAdapter
from cli_anything.ffx.harness.contract import ContractError
from cli_anything.ffx.harness.evidence import Evidence, EvidenceGraph

CONTRACT_PATH = Path(__file__).resolve().parents[5] / "contracts" / "markdown_parser.json"


def _load_contract() -> dict:
    return json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))


def _mk_adapter(metrics: dict | None = None) -> MarkdownAdapter:
    a = MarkdownAdapter(_load_contract())
    a._metrics = metrics or {
        "files": 3,
        "parse_ok": 3,
        "roundtrip_converged": 3,
        "roundtrip_convergence": 1.0,
        "line_errors": 0,
    }
    return a


# ── Evidence / EvidenceGraph ─────────────────────────────────────────

class TestEvidenceGraph:
    def test_add_and_all(self) -> None:
        g = EvidenceGraph()
        g.add(Evidence("discover", "ffx", 0, "ok"))
        g.add(Evidence("execute", "dart-runner", 0, "done", detail={"files": 2}))
        assert len(g.all()) == 2
        assert g.to_list()[0]["stage"] == "discover"

    def test_latest_returns_most_recent(self) -> None:
        g = EvidenceGraph()
        g.add(Evidence("a", "ffx", 0, "first"))
        g.add(Evidence("b", "ffx", 1, "second"))
        latest = g.latest("b")
        assert latest is not None
        assert latest.summary == "second"

    def test_latest_missing_stage_returns_none(self) -> None:
        g = EvidenceGraph()
        g.add(Evidence("a", "ffx", 0, "x"))
        assert g.latest("missing") is None


# ── MarkdownAdapter.evaluate ─────────────────────────────────────────

class TestMarkdownEvaluate:
    def test_all_checks_pass_but_s0_warns(self) -> None:
        a = _mk_adapter()
        r = a.evaluate(None)
        # s0_unsupported 非空 → warn（R3：非阻断 unknown）
        assert r["status"] in ("pass", "warn")
        checks = r["coverage"]["checks"]
        # R4：required_checks 4 项全部存在
        assert set(checks) == {"parse", "serialize", "roundtrip", "no_parse_error"}

    def test_serialize_missing_fails(self) -> None:
        # R4：roundtrip_converged=0 → serialize 代理失败 → fail
        a = _mk_adapter()
        a._metrics["roundtrip_converged"] = 0
        r = a.evaluate(None)
        assert r["status"] == "fail"
        assert "serialize" in r["coverage"]["checks"]

    def test_parse_fail_fails(self) -> None:
        a = _mk_adapter()
        a._metrics["parse_ok"] = 2  # files=3，2/3 成功
        r = a.evaluate(None)
        assert r["status"] == "fail"
        assert "parse" in r["coverage"]["checks"]

    def test_inconclusive_when_no_metrics(self) -> None:
        a = MarkdownAdapter(_load_contract())
        r = a.evaluate(None)
        assert r["status"] == "inconclusive"

    def test_unknown_overflow_fails(self) -> None:
        # R3：契约 unknown_max=3，s0_unsupported 有 3 项（不溢出→warn）
        a = _mk_adapter()
        r = a.evaluate(None)
        assert r["status"] != "fail" or "unknown overflow" in r["next_actions"]
        # 强制溢出场景：构造契约 unknown_max=1 + 2 个 s0
        contract = _load_contract()
        contract["completion_policy"]["unknown_max"] = 1
        contract["s0_unsupported"] = ["a", "b"]
        a2 = MarkdownAdapter(contract)
        a2._metrics = a._metrics
        r2 = a2.evaluate(None)
        assert r2["status"] == "fail"
        assert any("overflow" in x for x in r2["next_actions"])

    def test_blocking_unknown_fails(self) -> None:
        # R3：blocking_unknown 命中 s0 → fail
        contract = _load_contract()
        contract["completion_policy"]["blocking_unknown"] = ["autolink"]
        a = MarkdownAdapter(contract)
        a._metrics = {
            "files": 3, "parse_ok": 3, "roundtrip_converged": 3,
            "roundtrip_convergence": 1.0, "line_errors": 0,
        }
        r = a.evaluate(None)
        assert r["status"] == "fail"
        assert any("blocking" in x for x in r["next_actions"])


# ── orchestrator._diff_coverage ──────────────────────────────────────

class TestDiffCoverage:
    def test_same_values_no_delta(self) -> None:
        before = {"parse_ok": 3, "conv": 1.0}
        after = {"parse_ok": 3, "conv": 1.0}
        diffs = orchestrator._diff_coverage(before, after)
        assert diffs == []

    def test_changed_value_reports_delta(self) -> None:
        before = {"parse_ok": 1}
        after = {"parse_ok": 3}
        diffs = orchestrator._diff_coverage(before, after)
        assert len(diffs) == 1
        assert diffs[0]["metric"] == "parse_ok"
        assert diffs[0]["before"] == 1
        assert diffs[0]["after"] == 3

    def test_new_key_reports_added(self) -> None:
        diffs = orchestrator._diff_coverage({"a": 1}, {"a": 1, "b": 2})
        assert any(d["metric"] == "b" for d in diffs)


# ── orchestrator._load_adapter ───────────────────────────────────────

class TestLoadAdapter:
    def test_markdown_adapter_loads(self) -> None:
        adapter = orchestrator._load_adapter("markdown")
        assert adapter.id == "markdown"

    def test_unknown_capability_raises(self) -> None:
        with pytest.raises(ContractError):
            orchestrator._load_adapter("no_such_capability")
