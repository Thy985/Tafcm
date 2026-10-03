#!/usr/bin/env python3
"""双路 Eligibility Gate 的不变量测试（纯 stdlib unittest，零网络）。

守的是什么：
1. `eligible = maintenance_work OR exploration_due` —— 两条通道各自独立成立；
   把探索通道砍掉（旧版单一 has-work 闸的行为）会让这些用例变红。
2. 领域与 Top-N 由确定性打分决定，同输入必同输出（LLM 不参与选领域）。
3. 输出必须过 gate-result.schema.json；顶层 additionalProperties=false
   —— 夹带任何模型产字段都要被抓到。
4. NO_WORK 是显式机读终态（含 llm_activated=false），不是"没跑就算过去"。
5. 预算耗尽单独成态，且与"无活"可区分。
6. 写前 KB 硬顶生效（#289 账本自毁的防线之一）。
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

import eligibility_gate as gate  # noqa: E402
from contract_minicheck import load_schema, validate  # noqa: E402

SCHEMA_PATH = SCRIPTS.parent.parent / "schemas" / "gate-result.schema.json"

WEDNESDAY = date(2026, 10, 7)     # 探索槽位日
MONDAY = date(2026, 10, 5)        # 非槽位日


def quiet(**overrides) -> dict:
    """没有任何活的基线信号。"""
    base = {
        "commits_since_last_audit": [],
        "untriaged_issue_count": 0,
        "failed_check_count": 0,
        "frontier_entries": [],
        "days_since_last_exploration": 3,
        "last_exploration_date": "2026-10-02",
        "dimension_state": {},
        "churn": {},
        "budget": {},
    }
    base.update(overrides)
    return base


def evaluate(signals, when):
    result, extras = gate.evaluate(signals, when)
    return result, extras


def assert_contract(self, result):
    errors = validate(result, *([load_schema(SCHEMA_PATH)] * 2))
    self.assertEqual(errors, [], f"契约不符: {errors}")


class DualChannelTest(unittest.TestCase):
    def test_output_always_conforms_to_contract(self):
        for signals, when in (
            (quiet(), MONDAY),
            (quiet(commits_since_last_audit=[{"sha": "a", "paths": ["flutter_app/lib/core/parser/x.dart"]}]), MONDAY),
            (quiet(days_since_last_exploration=30, last_exploration_date="2026-09-05"), MONDAY),
        ):
            result, _ = evaluate(signals, when)
            assert_contract(self, result)

    def test_no_work_is_explicit_and_zero_token(self):
        result, extras = evaluate(quiet(), MONDAY)
        self.assertFalse(result["eligible"])
        self.assertEqual(extras["channel"], "none")
        self.assertEqual(result["not_eligible_reason"], "no_work")
        self.assertIsNone(result["dimension"], "无活时不得分配领域（不得凭空起 run）")
        noop = result["noop_record"]
        self.assertIsNotNone(noop)
        self.assertFalse(noop["llm_activated"])
        self.assertEqual(noop["date"], MONDAY.isoformat())

    def test_maintenance_alone_activates(self):
        signals = quiet(commits_since_last_audit=[
            {"sha": "abc", "paths": ["flutter_app/lib/domain/services/export_service.dart"]}])
        result, extras = evaluate(signals, MONDAY)
        self.assertTrue(result["eligible"])
        self.assertEqual(extras["channel"], "maintenance")
        self.assertIn("changed_code", result["maintenance"]["reasons"])
        self.assertFalse(result["exploration"]["due"])

    def test_exploration_alone_activates_even_without_any_change(self):
        """关键回归：单一 has-work 闸会在这里把探索通道一起杀掉。"""
        signals = quiet(days_since_last_exploration=30, last_exploration_date="2026-09-05")
        result, extras = evaluate(signals, MONDAY)
        self.assertFalse(result["maintenance"]["work_present"])
        self.assertTrue(result["eligible"], "探索到期即应放行，与仓库有无变更无关")
        self.assertEqual(extras["channel"], "exploration")
        self.assertIn("scheduled_slot", result["exploration"]["reasons"])

    def test_weekly_slot_when_ledger_absent(self):
        """账本尚未建立（无 last_exploration_date）时：只在槽位日兜底探索，不得天天探索。"""
        signals = quiet(days_since_last_exploration=None, last_exploration_date=None)
        wed, _ = evaluate(signals, WEDNESDAY)
        mon, _ = evaluate(signals, MONDAY)
        self.assertTrue(wed["eligible"])
        self.assertFalse(mon["eligible"], "缺账本时非槽位日不得放行探索（否则等于回到每日全扫）")

    def test_structural_churn_triggers_exploration(self):
        churn = {"flutter_app/lib/presentation/editor_page.dart": 900}
        result, _ = evaluate(quiet(churn=churn), MONDAY)
        self.assertTrue(result["eligible"])
        self.assertIn("structural_churn", result["exploration"]["reasons"])


class DeterminismTest(unittest.TestCase):
    def test_same_inputs_same_dimension(self):
        signals = quiet(days_since_last_exploration=40, last_exploration_date="2026-08-25")
        first, _ = evaluate(signals, MONDAY)
        second, _ = evaluate(signals, MONDAY)
        self.assertEqual(first["dimension"]["assigned"], second["dimension"]["assigned"])
        self.assertEqual(first["dimension"]["score_components"],
                         second["dimension"]["score_components"])

    def test_dimension_follows_changed_paths(self):
        signals = quiet(commits_since_last_audit=[
            {"sha": "a", "paths": ["flutter_app/lib/presentation/widgets/toc_panel.dart"]}])
        result, _ = evaluate(signals, MONDAY)
        self.assertEqual(result["dimension"]["assigned"], "ux_state",
                         "变更在 presentation/ 却派了别的维度 = 领域不是确定性映射")

    def test_evidence_cost_is_divisor_not_multiplier(self):
        """成本高的维度不得因为贵而排前面；同条件下便宜维度应胜出。"""
        cheap = gate.DIMENSION_EVIDENCE_COST["architecture_data_flow"]
        pricey = gate.DIMENSION_EVIDENCE_COST["export"]
        self.assertLess(cheap, pricey)
        churn = {"flutter_app/lib/core/parser/x.dart": 100,
                 "flutter_app/lib/domain/services/exporter/y.dart": 100}
        signals = quiet(commits_since_last_audit=[{"sha": "a", "paths": list(churn)}],
                        churn=churn)
        result, _ = evaluate(signals, MONDAY)
        components = result["dimension"]["score_components"]
        self.assertAlmostEqual(
            components["score"],
            round(components["risk"] * (1 + components["churn"] / 1000) *
                  (1 + components["staleness_days"] / 30) *
                  components["activation_weight"] *
                  max(components["expected_value"], 0.05) / components["evidence_cost"], 6),
            places=6)

    def test_workset_is_bounded(self):
        churn = {f"flutter_app/lib/core/f{i}.dart": 10 for i in range(60)}
        signals = quiet(commits_since_last_audit=[{"sha": "a", "paths": list(churn)}],
                        churn=churn)
        result, _ = evaluate(signals, MONDAY)
        self.assertLessEqual(len(result["dimension"]["workset"]), 25,
                             "工作集无上限 = 预算失控的入口")


class BudgetTest(unittest.TestCase):
    def test_maintenance_budget_exhausted_blocks(self):
        signals = quiet(
            commits_since_last_audit=[{"sha": "a", "paths": ["flutter_app/lib/x.dart"]}],
            budget={"maintenance": {"spent_today": gate.MAINTENANCE_CAP_TODAY}})
        result, _ = evaluate(signals, MONDAY)
        self.assertTrue(result["maintenance"]["work_present"])
        self.assertFalse(result["eligible"])
        self.assertEqual(result["not_eligible_reason"], "maintenance_budget_exhausted")

    def test_exploration_budget_exhausted_blocks_exploration_only(self):
        signals = quiet(days_since_last_exploration=30, last_exploration_date="2026-09-05",
                        budget={"exploration": {"spent_today": gate.EXPLORATION_CAP_TODAY}})
        result, _ = evaluate(signals, MONDAY)
        self.assertFalse(result["eligible"])
        self.assertEqual(result["not_eligible_reason"], "exploration_budget_exhausted")

    def test_exhaustion_is_distinguishable_from_no_work(self):
        """预算耗尽与无活必须可区分，否则空转率指标会说谎。"""
        changed = [{"sha": "a", "paths": ["flutter_app/lib/x.dart"]}]
        no_work, _ = evaluate(quiet(), MONDAY)
        exhausted, _ = evaluate(
            quiet(commits_since_last_audit=changed,
                  budget={"maintenance": {"spent_today": gate.MAINTENANCE_CAP_TODAY}}),
            MONDAY)
        self.assertEqual(no_work["not_eligible_reason"], "no_work")
        self.assertEqual(exhausted["not_eligible_reason"], "maintenance_budget_exhausted")
        self.assertTrue(exhausted["maintenance"]["work_present"],
                        "有活但被预算挡下 ≠ 无活；混淆这两态就永远看不见该加还是该减预算")


    def test_both_channels_exhausted_blocks(self):
        """两本账各自耗尽时必须停下——旧写法在这里会算出 eligible=true。"""
        signals = quiet(
            commits_since_last_audit=[{"sha": "a", "paths": ["flutter_app/lib/x.dart"]}],
            days_since_last_exploration=30, last_exploration_date="2026-09-05",
            budget={"maintenance": {"spent_today": gate.MAINTENANCE_CAP_TODAY},
                    "exploration": {"spent_today": gate.EXPLORATION_CAP_TODAY}})
        result, _ = evaluate(signals, MONDAY)
        self.assertTrue(result["maintenance"]["work_present"])
        self.assertTrue(result["exploration"]["due"])
        self.assertFalse(result["eligible"], "预算上限形同虚设")
        self.assertEqual(result["not_eligible_reason"], "both_budgets_exhausted")


class LedgerShapeTest(unittest.TestCase):
    """账本形状的输入必须走得通——P0-2 一接上真实 candidate_ids 就会走这条路。"""

    def _signals(self, candidate_ids):
        return quiet(
            commits_since_last_audit=[
                {"sha": "a", "paths": ["flutter_app/lib/core/parser/markdown_parser.dart"]}],
            dimension_state={"correctness_test_gap": {"candidate_ids": candidate_ids}})

    def test_full_hyp_ids_pass_through(self):
        result, _ = evaluate(self._signals(["HYP-007", "HYP-012"]), MONDAY)
        self.assertEqual(result["dimension"]["candidates"], ["HYP-007", "HYP-012"],
                         "账本写的是完整 id（与 ledger-event.hypothesis_id 同形），"
                         "不是能 int() 的序号")

    def test_bare_integers_are_normalized(self):
        result, _ = evaluate(self._signals([7, "7"]), MONDAY)
        self.assertEqual(result["dimension"]["candidates"], ["HYP-007"])

    def test_malformed_candidate_is_rejected_not_silently_fixed(self):
        result, extras = evaluate(self._signals(["hyp-seven"]), MONDAY)
        self.assertEqual(result["dimension"]["candidates"], ["hyp-seven"])
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "gate-result.json"
            problems = gate.emit(result, extras, out, SCHEMA_PATH, 16.0, None, None)
            self.assertTrue(problems, "非法候选 id 必须被写前契约校验拦下")
            self.assertFalse(out.exists())


class ChurnPrefixTest(unittest.TestCase):
    def test_test_dir_churn_counts_as_structural(self):
        """flutter_app/test/ 下的抖动不该被漏掉。"""
        churn = {f"flutter_app/test/unit/f{i}.dart": 100 for i in range(10)}
        result, _ = evaluate(quiet(churn=churn), MONDAY)
        self.assertIn("structural_churn", result["exploration"]["reasons"])

    def test_ci_dir_churn_is_not_structural(self):
        """.github/ 是 infra_ci 的 workset，但 CI 配置改动不构成代码结构抖动。"""
        result, _ = evaluate(quiet(churn={".github/workflows/ci.yml": 5000}), MONDAY)
        self.assertNotIn("structural_churn", result["exploration"]["reasons"])


class FrontierParsingTest(unittest.TestCase):
    SAMPLE = (
        "# Tafcm Audit Frontier\n\n"
        "## 活跃队列（active / deepening / blocked）\n\n"
        "### FR-001 — smoke 管道\n"
        "- id: FR-001\n"
        "- next_action: type: targeted-test / target: "
        "flutter_app/integration_test/phase35_home_smoke_test.dart（已通）→ 扩展至 editor_screen\n\n"
        "### FR-002 — 无 target 的条目\n- id: FR-002\n- open_question: 待补\n\n"
        "## 冷却区（cooling）\n\n"
        "### FR-003 — 冷却条目\n- next_action: type: code-read / target: tools/adi/adi.dart\n\n"
        "## 归档区（retired）\n\n### FR-004 — 归档\n- id: FR-004\n"
    )

    def _write(self, tmp: Path, text: str = SAMPLE) -> Path:
        path = tmp / "FRONTIER.md"
        path.write_text(text, encoding="utf-8")
        return path

    def test_parses_only_active_region_with_targets(self):
        with tempfile.TemporaryDirectory() as tmp:
            entries = gate._frontier_open_entries(self._write(Path(tmp)))
            self.assertEqual([e["id"] for e in entries], ["FR-001", "FR-002"],
                             "冷却区与归档区的条目不得算进活跃区")
            self.assertEqual(entries[0]["target"],
                             "flutter_app/integration_test/phase35_home_smoke_test.dart",
                             "target 必须停在路径边界，不能把中文说明一起吞进来")
            self.assertIsNone(entries[1]["target"])

    def test_missing_marker_raises_instead_of_overcounting(self):
        """标记被改名时，旧写法会把 cooling/retired 全算进活跃区，信号静默虚高。"""
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(Path(tmp), self.SAMPLE.replace("## 冷却区", "## 冷却队列"))
            with self.assertRaises(gate.GateError):
                gate._frontier_open_entries(path)


class FrontierChangeSemanticsTest(unittest.TestCase):
    """契约要的是"target 又出现在近期 diff 里"，不是"存在未闭合 Entry"。

    后者会让一条长期 blocked 的 FR（仓库现状就是 FR-001）把 maintenance 通道夜夜打开，
    影子期"哪些夜晚本可跳过"的读数因此系统性偏高。
    """

    FR = [{"id": "FR-001",
           "target": "flutter_app/integration_test/phase35_home_smoke_test.dart"}]

    def _reasons(self, changed_paths, entries):
        result, _ = evaluate(quiet(
            commits_since_last_audit=[{"sha": "a", "paths": changed_paths}] if changed_paths else [],
            frontier_entries=entries), MONDAY)
        return result["maintenance"]["reasons"]

    def test_unrelated_diff_does_not_open_the_channel(self):
        reasons = self._reasons(["flutter_app/lib/core/parser/markdown_parser.dart"], self.FR)
        self.assertIn("changed_code", reasons)
        self.assertNotIn("frontier_change", reasons)

    def test_target_file_changed_opens_it(self):
        reasons = self._reasons(
            ["flutter_app/integration_test/phase35_home_smoke_test.dart"], self.FR)
        self.assertIn("frontier_change", reasons)

    def test_sibling_file_in_target_dir_opens_it(self):
        reasons = self._reasons(
            ["flutter_app/integration_test/editor_test.dart"], self.FR)
        self.assertIn("frontier_change", reasons)

    def test_open_entries_alone_never_make_work_present(self):
        """活跃区有条目但今晚零变更：maintenance 必须判无活。"""
        result, _ = evaluate(quiet(frontier_entries=self.FR), MONDAY)
        self.assertFalse(result["maintenance"]["work_present"])
        self.assertEqual(result["maintenance"]["signals"]["open_candidate_count"], 1,
                         "Entry 数仍作为读数保留，只是不再单独构成触发条件")


class ExplorationGapFallbackTest(unittest.TestCase):
    """账本只提供日期、不提供天数时，槽位判定不得被静默关掉。"""

    def test_gap_derived_from_last_exploration_date(self):
        result, _ = evaluate(quiet(days_since_last_exploration=None,
                                   last_exploration_date="2026-09-01"), MONDAY)
        self.assertIn("scheduled_slot", result["exploration"]["reasons"])
        self.assertEqual(result["exploration"]["signals"]["days_since_last_exploration"], 34)

    def test_recent_date_still_blocks_the_slot(self):
        result, _ = evaluate(quiet(days_since_last_exploration=None,
                                   last_exploration_date="2026-10-02"), MONDAY)
        self.assertNotIn("scheduled_slot", result["exploration"]["reasons"])

    def test_unparseable_date_fails_loudly(self):
        """静默当"没数据"处理会让有账本比没账本更保守，且没人知道。"""
        with self.assertRaises(gate.GateError):
            evaluate(quiet(days_since_last_exploration=None,
                           last_exploration_date="上周三"), MONDAY)

    def test_cli_reports_unparseable_date_as_exit_1(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp) / "s.json"
            fixture.write_text(json.dumps(quiet(days_since_last_exploration=None,
                                                last_exploration_date="上周三")),
                               encoding="utf-8")
            code = gate.main(["--fixture", str(fixture), "--date", MONDAY.isoformat(),
                              "--output", str(Path(tmp) / "out.json")])
            self.assertEqual(code, 1, "判定阶段的 GateError 必须走响亮失败，不能裸 traceback")


class GuardEffectivenessTest(unittest.TestCase):
    """守门必须能变红：证明契约校验不是恒真通过。"""

    def test_smuggled_llm_field_is_rejected(self):
        result, _ = evaluate(quiet(), MONDAY)
        result["confidence_from_model"] = 0.9  # 模拟把模型输出夹带进 gate
        schema = load_schema(SCHEMA_PATH)
        errors = validate(result, schema, schema)
        self.assertTrue(any("additionalProperties" in e for e in errors),
                        f"夹带字段未被拒绝: {errors}")

    def test_missing_required_field_is_rejected(self):
        result, _ = evaluate(quiet(), MONDAY)
        del result["exploration"]
        schema = load_schema(SCHEMA_PATH)
        self.assertTrue(validate(result, schema, schema))

    def test_bad_enum_is_rejected(self):
        result, _ = evaluate(quiet(
            commits_since_last_audit=[{"sha": "a", "paths": ["x"]}]), MONDAY)
        result["dimension"]["assigned"] = "whatever_the_model_said"
        schema = load_schema(SCHEMA_PATH)
        self.assertTrue(validate(result, schema, schema))

    def test_kb_cap_blocks_write(self):
        result, extras = evaluate(quiet(), MONDAY)
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "gate-result.json"
            problems = gate.emit(result, extras, out, SCHEMA_PATH, 0.001, None, None)
            self.assertTrue(problems and "记录超限" in problems[0])
            self.assertFalse(out.exists(), "超限不得落盘")

    def test_emit_writes_file_and_outputs(self):
        result, extras = evaluate(quiet(), MONDAY)
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "nested" / "gate-result.json"
            gh_out = Path(tmp) / "gh_output"
            gh_out.write_text("", encoding="utf-8")
            summary = Path(tmp) / "summary.md"
            problems = gate.emit(result, extras, out, SCHEMA_PATH, 16.0, summary, gh_out)
            self.assertEqual(problems, [])
            written = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(written["run_date"], MONDAY.isoformat())
            self.assertIn("eligible=false", gh_out.read_text(encoding="utf-8"))
            self.assertIn("NO_WORK", summary.read_text(encoding="utf-8"))


class CliTest(unittest.TestCase):
    def test_fixture_mode_end_to_end(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp) / "signals.json"
            signals = quiet(
                commits_since_last_audit=[
                    {"sha": "a", "paths": ["flutter_app/lib/core/parser/markdown_parser.dart"]}],
                dimension_state={"correctness_test_gap": {"last_probed": "2026-08-01"}})
            fixture.write_text(json.dumps(signals), encoding="utf-8")
            out = Path(tmp) / "gate.json"
            code = gate.main(["--fixture", str(fixture), "--date", MONDAY.isoformat(),
                              "--output", str(out)])
            self.assertEqual(code, 0)
            self.assertTrue(out.is_file())

    def test_ledger_state_closes_the_staleness_loop(self):
        """账本 → 陈旧度 → 领域分配 → 激活。没有 --state-file 时这条闭环不存在。

        用 fixture 提供"无任何变更"的信号，让账本负责陈旧度：既 hermetic
        （不跑真实 git/gh 探针），又正好验证账本值只填空、不覆盖探针值。
        """
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "ledger-state.json"
            state.write_text(json.dumps({
                "dimension_state": {"export": {"last_probed": "2026-08-01",
                                               "open_candidates": 1, "candidate_ids": [7],
                                               "open_severity": "high"}},
                "days_since_last_exploration": None,
                "last_exploration_date": None,
            }), encoding="utf-8")
            empty = Path(tmp) / "signals.json"
            empty.write_text(json.dumps(quiet()), encoding="utf-8")
            out = Path(tmp) / "gate.json"
            code = gate.main(["--date", MONDAY.isoformat(), "--fixture", str(empty),
                              "--state-file", str(state), "--output", str(out)])
            self.assertEqual(code, 0)
            result = json.loads(out.read_text(encoding="utf-8"))
            self.assertTrue(result["eligible"], "export 已 65 天未探测，非槽位日也该放行")
            self.assertIn("frontier_stale", result["exploration"]["reasons"])
            self.assertEqual(result["dimension"]["assigned"], "export")
            self.assertEqual(result["dimension"]["candidates"], ["HYP-007"])

    def test_missing_fixture_fails_loudly(self):
        code = gate.main(["--fixture", "/nope/missing.json", "--date", MONDAY.isoformat()])
        self.assertEqual(code, 1, "gate 自身出错必须响，不得静默降级成 NO_WORK")


if __name__ == "__main__":
    unittest.main(verbosity=2)
