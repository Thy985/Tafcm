#!/usr/bin/env python3
"""Canonical Ledger 的不变量测试（P0-2）。

这里测的不是"能不能写进去"，而是**该被拦下的事是否真被拦下**：
自证、身份申报、超账本上限的巨行、损坏账本上续写、注册表与账本漂移。
"""

from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

import ledger  # noqa: E402
from ledger import LedgerError, append, read_events  # noqa: E402


def hyp_event(run_id="run-scout-1", actor="scout", **over) -> dict:
    event = {
        "type": "hypothesis_added",
        "actor": actor,
        "run_id": run_id,
        "budget_bucket": "maintenance",
        "hypothesis": {
            "dimension": "performance",
            "area": "flutter_app/lib/core/services",
            "title": "autosave 随文档体积恶化",
            "statement": "每次改动都全量 serializeDocument()",
            "invariant": "保存代价应随块数线性而非文档字节数平方",
            "invariant_source": {"kind": "passing_test",
                                 "ref_path": "flutter_app/test/performance/perf_ratchet_test.dart",
                                 "ref_commit": "5a53be1"},
            "falsifier": "1KB→1MB 文档下 serialize 次数保持常数",
            "evidence_tier": "L0",
            "severity": "medium",
            "category": "performance",
            "evidence_files": ["flutter_app/lib/core/services/document_service.dart"],
            "lifecycle_stage": "candidate",
        },
    }
    event.update(over)
    if "hypothesis" in over:
        event["hypothesis"] = over["hypothesis"]
    return event


def gate_row(**over) -> dict:
    event = {
        "type": "gate_no_work",
        "actor": "scheduler",
        "run_id": "run-gate-1",
        "budget_bucket": "maintenance",
        "gate": {"channel": "none", "reasons": ["no_work"], "dimension": None},
    }
    event.update(over)
    return event


class TempLedgerCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.ledger_path = Path(self._tmp.name) / "ledger.ndjson"
        self.addCleanup(self._tmp.cleanup)

    def append_quietly(self, event):
        with redirect_stdout(io.StringIO()):
            return append(self.ledger_path, event)

    def registry(self, rows) -> Path:
        path = self.ledger_path.parent / "FINDINGS.md"
        header = ("| fingerprint | latest_id | category | evidence | status | issue | "
                  "first_seen | last_seen |\n|---|---|---|---|---|---|---|---|\n")
        body = "".join("| {} | {} | {} | {} | {} | {} | {} | {} |\n".format(*r) for r in rows)
        path.write_text(header + body, encoding="utf-8")
        return path


class AppendBasicsTest(TempLedgerCase):
    def test_gate_row_appends(self):
        prepared = self.append_quietly(gate_row())
        self.assertRegex(prepared["event_id"], r"^EV-[0-9a-f]{16}$")
        self.assertEqual(len(read_events(self.ledger_path)), 1)

    def test_hypothesis_gets_script_assigned_id(self):
        first = self.append_quietly(hyp_event())
        self.assertEqual(first["hypothesis_id"], "HYP-001")
        other = hyp_event(run_id="run-scout-2",
                          hypothesis={**hyp_event()["hypothesis"],
                                      "evidence_files": ["flutter_app/lib/other.dart"]})
        second = self.append_quietly(other)
        self.assertEqual(second["hypothesis_id"], "HYP-002")

    def test_created_by_run_is_recorded_for_later_separation_check(self):
        prepared = self.append_quietly(hyp_event(run_id="run-42"))
        self.assertEqual(prepared["hypothesis"]["created_by_run"], "run-42")


class IdentityTest(TempLedgerCase):
    def test_fingerprint_is_computed_not_accepted(self):
        with self.assertRaises(LedgerError) as ctx:
            self.append_quietly(hyp_event(fingerprint="deadbeefdeadbeef"))
        self.assertIn("身份不接受申报", str(ctx.exception))

    def test_importer_exception_is_scoped_to_import_runs(self):
        """借 importer 身份申报 fingerprint 必须被拒——例外只对 import-* 运行开放。"""
        smuggled = hyp_event(actor="importer", run_id="run-scout-1",
                             fingerprint="deadbeefdeadbeef")
        with self.assertRaises(LedgerError) as ctx:
            self.append_quietly(smuggled)
        self.assertIn("importer 例外仅适用于", str(ctx.exception))

    def test_identity_reuses_fingerprint_py_recipe(self):
        """账本与 FINDINGS.md 必须是同一套身份，否则 P0-2 自己就造了第二个真相。"""
        import fingerprint as fp

        prepared = self.append_quietly(hyp_event())
        expected = fp.fingerprint(
            "performance",
            ["flutter_app/lib/core/services/document_service.dart"],
            fp.normalize_summary("autosave 随文档体积恶化"),
        )
        self.assertEqual(prepared["fingerprint"], expected)

    def test_duplicate_fingerprint_links_instead_of_new_id(self):
        first = self.append_quietly(hyp_event())
        again = self.append_quietly(hyp_event(run_id="run-scout-9"))
        self.assertEqual(again["hypothesis_id"], first["hypothesis_id"])
        self.assertEqual(again["duplicate_of"], first["hypothesis_id"])
        self.assertEqual(len([e for e in read_events(self.ledger_path)
                              if e.get("type") == "hypothesis_added"]), 2)


class SelfProofBarrierTest(TempLedgerCase):
    """提出假设的人不得批准自己的假设——这是整份设计唯一硬约束 LLM 的地方。"""

    def setUp(self):
        super().setUp()
        self.created = self.append_quietly(hyp_event(run_id="run-7"))

    def promote(self, actor, run_id, decision="verified"):
        return {
            "type": "verdict_recorded",
            "actor": actor,
            "run_id": run_id,
            "budget_bucket": "maintenance",
            "hypothesis_id": self.created["hypothesis_id"],
            "verdict": {"decision": decision, "publisher_action": "create_issue",
                        "checks": [{"name": "schema_valid", "status": "pass"}]},
        }

    def test_scout_cannot_promote(self):
        with self.assertRaises(LedgerError):
            self.append_quietly(self.promote("scout", "run-7"))

    def test_investigator_cannot_promote(self):
        with self.assertRaises(LedgerError):
            self.append_quietly(self.promote("investigator", "run-8"))

    def test_same_run_confirmation_rejected_even_for_verifier(self):
        with self.assertRaises(LedgerError) as ctx:
            self.append_quietly(self.promote("verifier", "run-7"))
        self.assertIn("same_run_confirmation", str(ctx.exception))

    def test_cross_run_verifier_accepted(self):
        prepared = self.append_quietly(self.promote("verifier", "run-99"))
        self.assertEqual(prepared["verdict"]["decision"], "verified")

    def test_reject_verdict_from_wrong_actor_also_blocked(self):
        with self.assertRaises(LedgerError):
            self.append_quietly(self.promote("scout", "run-99", decision="reject"))


class LedgerIntegrityTest(TempLedgerCase):
    def test_oversized_record_rejected(self):
        event = hyp_event()
        event["hypothesis"]["statement"] = "x" * 60_000
        with self.assertRaises(LedgerError) as ctx:
            self.append_quietly(event)
        self.assertIn("超上限", str(ctx.exception))

    def test_corrupt_line_blocks_further_writes(self):
        self.append_quietly(gate_row())
        with open(self.ledger_path, "a", encoding="utf-8") as fh:
            fh.write("{not json}\n")
        with self.assertRaises(LedgerError) as ctx:
            self.append_quietly(gate_row(run_id="run-gate-2"))
        self.assertIn("损坏", str(ctx.exception))

    def test_append_only_never_rewrites_history(self):
        self.append_quietly(gate_row())
        before = self.ledger_path.read_text(encoding="utf-8")
        self.append_quietly(hyp_event())
        after = self.ledger_path.read_text(encoding="utf-8")
        self.assertTrue(after.startswith(before), "账本必须严格追加，旧行一字不改")

    def test_contract_rejects_unknown_actor(self):
        with self.assertRaises(LedgerError) as ctx:
            self.append_quietly(gate_row(actor="model-said-so"))
        self.assertIn("契约不符", str(ctx.exception))


class ProjectionTest(TempLedgerCase):
    def test_state_subcommand_feeds_gate_real_staleness(self):
        """§3.9 的"已知未接"：调度器的陈旧度必须来自账本，不是 fixture。"""
        self.append_quietly(hyp_event())
        self.append_quietly(gate_row(budget_bucket="exploration"))
        out = self.ledger_path.parent / "state.json"
        args = type("A", (), {"ledger": str(self.ledger_path), "out": str(out),
                              "date": "2026-10-20"})()
        with redirect_stdout(io.StringIO()):
            self.assertEqual(ledger.cmd_state(args), 0)
        state = json.loads(out.read_text(encoding="utf-8"))
        self.assertIn("performance", state["dimension_state"])
        self.assertEqual(state["dimension_state"]["performance"]["open_candidates"], 1)
        self.assertEqual(state["frontier_open_candidates"], 1)
        self.assertIsInstance(state["days_since_last_exploration"], int)

    def test_project_writes_md_and_metrics(self):
        self.append_quietly(gate_row())
        self.append_quietly(hyp_event())
        md = self.ledger_path.parent / "LEDGER.md"
        metrics = self.ledger_path.parent / "metrics.json"
        args = type("A", (), {"ledger": str(self.ledger_path), "out_md": str(md),
                              "out_metrics": str(metrics)})()
        with redirect_stdout(io.StringIO()):
            self.assertEqual(ledger.cmd_project(args), 0)
        text = md.read_text(encoding="utf-8")
        self.assertIn("自动生成，请勿手改", text)
        self.assertIn("HYP-001", text)
        data = json.loads(metrics.read_text(encoding="utf-8"))
        self.assertEqual(data["llm_activations"], 1)
        self.assertEqual(data["gate_no_work"], 1)
        self.assertEqual(data["by_bucket"]["maintenance"], 2)


class AppendGateTest(TempLedgerCase):
    def gate_json(self, payload) -> Path:
        path = Path(self._tmp.name) / "gate-result.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def base(self, eligible, reason=None, channel_reasons=()):
        return {
            "schema_version": "1.0", "generated_at": "2026-10-03T00:00:00+00:00",
            "run_date": "2026-10-03", "eligible": eligible,
            "maintenance": {"work_present": "changed_code" in channel_reasons,
                            "reasons": list(channel_reasons), "signals": {}},
            "exploration": {"due": "scheduled_slot" in channel_reasons,
                            "reasons": [r for r in channel_reasons if r == "scheduled_slot"],
                            "signals": {}},
            "not_eligible_reason": reason,
            "dimension": ({"assigned": "performance", "workset": ["a"],
                           "candidates": [], "score_components": {}} if eligible else None),
            "budget": {"maintenance": {"spent_today": 0, "cap_today": 1, "remaining": 1,
                                       "unit": "llm_cost_estimate", "exhausted": False},
                       "exploration": {"spent_today": 0, "cap_today": 1, "remaining": 1,
                                       "unit": "llm_cost_estimate", "exhausted": False}},
            "noop_record": None if eligible else {"date": "2026-10-03", "reason": reason,
                                                  "duration_s": None, "llm_activated": False},
        }

    def run_gate(self, payload, run_id="run-gate-1", missing_reason=None, path=None):
        args = type("A", (), {"ledger": str(self.ledger_path), "dry_run": False,
                              "gate_result": str(path or self.gate_json(payload)),
                              "run_id": run_id, "duration_s": None, "llm_cost": None,
                              "missing_reason": missing_reason})()
        with redirect_stdout(io.StringIO()):
            ledger.cmd_append_gate(args)
        return read_events(self.ledger_path)[-1]

    def test_missing_gate_result_still_leaves_a_row(self):
        """影子阶段闸门自己挂了也必须留痕——账本要能回答"昨晚发生了什么"。"""
        event = self.run_gate(None, path=Path(self._tmp.name) / "nope.json",
                              missing_reason="gate_step_failed")
        self.assertEqual(event["type"], "gate_skipped_run")
        self.assertEqual(event["gate"]["reasons"], ["gate_step_failed"])

    def test_missing_gate_without_reason_is_an_error(self):
        with self.assertRaises(LedgerError):
            self.run_gate(None, path=Path(self._tmp.name) / "nope.json")

    def test_eligible_run_records_gate_row(self):
        event = self.run_gate(self.base(True, channel_reasons=("changed_code",)))
        self.assertEqual(event["type"], "gate_eligible")
        self.assertEqual(event["budget_bucket"], "maintenance")
        self.assertEqual(event["gate"]["dimension"], "performance")

    def test_no_work_and_budget_skip_are_different_types(self):
        no_work = self.run_gate(self.base(False, reason="no_work"), "run-a")
        skipped = self.run_gate(self.base(False, reason="maintenance_budget_exhausted",
                                          channel_reasons=("changed_code",)), "run-b")
        self.assertEqual(no_work["type"], "gate_no_work")
        self.assertEqual(skipped["type"], "gate_skipped_run")
        self.assertEqual(skipped["budget_bucket"], "maintenance",
                         "预算挡下的通道必须记在原账上，否则看不出该加预算还是该减活动")

    def test_skip_rate_denominator_is_evaluations_not_events(self):
        for i, payload in enumerate([
            self.base(False, reason="no_work"),
            self.base(False, reason="no_work"),
            self.base(True, channel_reasons=("changed_code",)),
        ]):
            self.run_gate(payload, run_id=f"run-{i}")
        self.append_quietly(hyp_event())  # 一条非 gate 事件，验证它不进分母
        md = Path(self._tmp.name) / "LEDGER.md"
        metrics = Path(self._tmp.name) / "metrics.json"
        args = type("A", (), {"ledger": str(self.ledger_path), "out_md": str(md),
                              "out_metrics": str(metrics)})()
        with redirect_stdout(io.StringIO()):
            ledger.cmd_project(args)
        data = json.loads(metrics.read_text(encoding="utf-8"))
        self.assertEqual(data["gate_evaluations"], 3)
        self.assertAlmostEqual(data["gate_skip_rate"], round(2 / 3, 4))


class ImportAuditTest(TempLedgerCase):
    AUDIT = """# Maintainer Audit 2026-10-01

## New Findings

### F-2026-10-01-01 — 导出路径仍全量序列化

Category: tech-debt
Severity: P1
Confidence: High
Status: NEW
Summary: PR #298 修复 #249 时遗漏 editor_export_actions.dart:77，导出路径仍全量序列化
Evidence: `flutter_app/lib/presentation/editor/editor_export_actions.dart:77`
Impact: 大文档导出代价高
Recommendation: Watch
Related Issue: #249

## Existing Issue Updates

nothing here
"""

    def audit_file(self, text=None) -> Path:
        path = Path(self._tmp.name) / "2026-10-01-maintainer-audit.md"
        path.write_text(text or self.AUDIT, encoding="utf-8")
        return path

    def run_import(self, audit, dry=False):
        args = type("A", (), {"ledger": str(self.ledger_path), "audit": str(audit),
                              "dry_run": dry})()
        with redirect_stdout(io.StringIO()) as out:
            code = ledger.cmd_import_audit(args)
        return code, out.getvalue()

    def test_audit_finding_lands_as_L1_with_severity_cap_visible(self):
        code, _ = self.run_import(self.audit_file())
        self.assertEqual(code, 0)
        event = read_events(self.ledger_path)[0]
        hyp = event["hypothesis"]
        self.assertEqual(event["type"], "hypothesis_added")
        self.assertEqual(event["actor"], "scout")
        self.assertEqual(hyp["evidence_tier"], "L1",
                         "散文审计无实验/对照/确定性重跑，按 §3.2 到不了 L2")
        self.assertEqual(hyp["severity"], "medium")
        self.assertEqual(hyp["severity_declared"], "P1", "降级必须留痕")

    def test_identity_matches_findings_registry(self):
        """账本与 FINDINGS.md 必须是同一个身份，否则 P0-2 反而造出第二个真相。"""
        import fingerprint as fp

        findings = fp.extract_findings(self.AUDIT)
        self.run_import(self.audit_file())
        event = read_events(self.ledger_path)[0]
        self.assertEqual(event["fingerprint"], findings[0]["fingerprint"])

    def test_invariant_source_self_authored_caps_the_tier(self):
        self.run_import(self.audit_file())
        hyp = read_events(self.ledger_path)[0]["hypothesis"]
        self.assertEqual(hyp["invariant_source"]["kind"], "self_authored")

    def test_second_import_links_duplicate_not_new_hypothesis(self):
        self.run_import(self.audit_file())
        first = read_events(self.ledger_path)[0]["hypothesis_id"]
        self.run_import(self.audit_file())
        events = read_events(self.ledger_path)
        latest = events[-1]
        self.assertEqual(latest["hypothesis_id"], first)
        self.assertEqual(latest.get("duplicate_of"), first,
                         "同身份重复导入不得开出新假设")

    def test_no_findings_audit_is_a_clean_no_op(self):
        path = self.audit_file("# Audit\n\n## New Findings\n\nNo significant findings.\n")
        code, output = self.run_import(path)
        self.assertEqual(code, 0)
        self.assertIn("无 Finding", output)
        self.assertEqual(read_events(self.ledger_path), [])

    def test_dry_run_writes_nothing(self):
        code, output = self.run_import(self.audit_file(), dry=True)
        self.assertEqual(code, 0)
        self.assertFalse(self.ledger_path.exists())


class ImportAndReconcileTest(TempLedgerCase):
    def test_import_then_reconcile_is_consistent(self):
        rows = [("0" * 16, "F-2026-09-01-01", "bug", "a.dart", "UNCHANGED", "#216",
                 "2026-09-01", "2026-09-01")]
        registry = self.registry(rows)
        args = type("A", (), {"ledger": str(self.ledger_path), "registry": str(registry),
                              "date": "2026-10-03", "dry_run": False})()
        with redirect_stdout(io.StringIO()):
            self.assertEqual(ledger.cmd_import_findings(args), 0)
        recon = type("A", (), {"ledger": str(self.ledger_path), "registry": str(registry)})()
        with redirect_stdout(io.StringIO()):
            self.assertEqual(ledger.cmd_reconcile(recon), 0)

    def test_import_is_idempotent(self):
        registry = self.registry([("1" * 16, "F-1", "bug", "a.dart", "UNCHANGED", "N/A",
                                   "2026-09-01", "2026-09-01")])
        args = type("A", (), {"ledger": str(self.ledger_path), "registry": str(registry),
                              "date": "2026-10-03", "dry_run": False})()
        with redirect_stdout(io.StringIO()):
            ledger.cmd_import_findings(args)
            first = len(read_events(self.ledger_path))
            ledger.cmd_import_findings(args)
            second = len(read_events(self.ledger_path))
        self.assertEqual(first, second, "导入两次就多一份状态 = 账本不再是唯一真相")

    def test_backfill_does_not_reset_staleness(self):
        """回填不得清零探测节律：陈旧度来自 last_observed，不是事件写入时间。

        这条是真实数据逼出来的——首版 state 用 updated_ts，导入 31 条历史后
        所有维度都变成"今天刚查过"，探索通道会安静 21 天。
        """
        registry = self.registry([("a" * 16, "F-2026-09-01-01", "performance", "p.dart",
                                   "UNCHANGED", "N/A", "2026-09-01", "2026-09-01")])
        imp = type("A", (), {"ledger": str(self.ledger_path), "registry": str(registry),
                             "date": "2026-10-03", "dry_run": False})()
        with redirect_stdout(io.StringIO()):
            ledger.cmd_import_findings(imp)
        out = self.ledger_path.parent / "state.json"
        st = type("A", (), {"ledger": str(self.ledger_path), "out": str(out),
                            "date": "2026-10-03"})()
        with redirect_stdout(io.StringIO()):
            ledger.cmd_state(st)
        state = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(state["dimension_state"]["performance"]["last_probed"], "2026-09-01")

    def test_reconcile_detects_drift(self):
        self.append_quietly(hyp_event())
        registry = self.registry([("f" * 16, "F-X", "bug", "z.dart", "NEW", "N/A",
                                   "2026-09-09", "2026-09-09")])
        recon = type("A", (), {"ledger": str(self.ledger_path), "registry": str(registry)})()
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()) as err:
            code = ledger.cmd_reconcile(recon)
        self.assertEqual(code, 1)
        self.assertIn("不在账本里", err.getvalue())


class ScriptOwnershipTest(TempLedgerCase):
    """申报制就是 #289 的成因：能被上游填的身份字段，上游就会填出一个自洽的假身份。

    这条是参数化的—— commit message 里那句"身份由脚本算"只有在每个字段都撞过墙
    之后才成立。
    """

    def test_declared_identity_fields_are_rejected(self):
        cases = [
            ("event_id", {"event_id": "EV-ffffffffffffffff"}, "event_id 由脚本拥有"),
            ("ts", {"ts": "2020-01-01T00:00:00+00:00"}, "ts 由脚本拥有"),
            ("hypothesis_id", {"hypothesis_id": "HYP-001"}, "hypothesis_id 由脚本分配"),
            ("created_by_run", {"hypothesis": {**hyp_event()["hypothesis"],
                                               "created_by_run": "not-my-run"}},
             "created_by_run 由脚本"),
        ]
        for name, extra, needle in cases:
            with self.subTest(field=name), self.assertRaises(LedgerError) as ctx:
                self.append_quietly(hyp_event(**extra))
            self.assertIn(needle, str(ctx.exception))

    def test_verdict_for_unknown_hypothesis_is_rejected(self):
        """拼错一个 hypothesis_id 就给不存在的假设签了字：metrics.verified 会凭空涨。"""
        with self.assertRaises(LedgerError) as ctx:
            self.append_quietly({"type": "verdict_recorded", "actor": "verifier",
                                 "run_id": "run-v-1", "budget_bucket": "meta",
                                 "hypothesis_id": "HYP-999",
                                 "verdict": {"decision": "verified", "rationale": "x"}})
        self.assertIn("未知假设", str(ctx.exception))

    def test_importer_cannot_certify(self):
        """importer 是装载器不是判定者：给它签字权 = 自证阻断整条对导入通道失效。"""
        self.append_quietly(hyp_event(run_id="run-1"))
        for etype in ("tier_promoted", "verdict_recorded"):
            payload = {"type": etype, "actor": "importer", "run_id": "import-2026-10-03",
                       "budget_bucket": "meta", "hypothesis_id": "HYP-001"}
            if etype == "verdict_recorded":
                payload["verdict"] = {"decision": "verified", "rationale": "x"}
            else:
                payload["hypothesis"] = {"evidence_tier": "L2"}
            with self.subTest(type=etype), self.assertRaises(LedgerError) as ctx:
                self.append_quietly(payload)
            self.assertIn("无权写", str(ctx.exception))

    def test_self_authored_l2_is_blocked_at_write_step(self):
        """契约把这条叫"机械阻断点"，那它就不能只存在于契约文字里。"""
        with self.assertRaises(LedgerError) as ctx:
            self.append_quietly(hyp_event(hypothesis={
                **hyp_event()["hypothesis"], "evidence_tier": "L2",
                "invariant_source": {"kind": "self_authored"}}))
        self.assertIn("self_authored", str(ctx.exception))

    def test_retired_hypothesis_recurrence_gets_its_own_id(self):
        """闭合只"不再覆盖"是不够的：复发必须能被当成新候选，而不是挂在退役假设上。"""
        first = self.append_quietly(hyp_event())
        self.append_quietly({"type": "retired", "actor": "verifier", "run_id": "run-v",
                             "budget_bucket": "meta", "hypothesis_id": first["hypothesis_id"]})
        again = self.append_quietly(hyp_event(run_id="run-2"))
        self.assertNotEqual(again["hypothesis_id"], first["hypothesis_id"])
        self.assertIsNone(again.get("duplicate_of"))

    def test_content_addressed_event_id_is_replayable(self):
        """同一内容重跑夜间管道不该在账本里堆两份；event_id 也必须能被人重算核对。"""
        event = gate_row(run_id="run-gate-x")
        first = self.append_quietly(event)
        with redirect_stdout(io.StringIO()) as out:
            second = append(self.ledger_path, event)
        self.assertIn("[SKIP]", out.getvalue())
        self.assertEqual(len(read_events(self.ledger_path)), 1)
        self.assertEqual(first["event_id"], second["event_id"])

    def test_null_hypothesis_payload_does_not_brick_readers(self):
        """`hypothesis: null` 是契约允许的取值；读路径按 dict 假设它，账本就没法投影了。"""
        self.append_quietly(hyp_event())
        with open(self.ledger_path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"schema_version": "1.0", "event_id": "EV-00000000000000ab",
                                 "ts": "2026-10-03T00:00:00+00:00", "type": "hypothesis_updated",
                                 "actor": "scout", "run_id": "run-1", "budget_bucket": "meta",
                                 "hypothesis_id": "HYP-001", "hypothesis": None},
                                sort_keys=True) + "\n")
        out = self.ledger_path.parent / "state.json"
        st = type("A", (), {"ledger": str(self.ledger_path), "out": str(out),
                            "date": "2026-10-20", "allow_missing": False})()
        with redirect_stdout(io.StringIO()):
            self.assertEqual(ledger.cmd_state(st), 0)
        md = self.ledger_path.parent / "L.md"
        metrics = self.ledger_path.parent / "m.json"
        pr = type("A", (), {"ledger": str(self.ledger_path), "out_md": str(md),
                            "out_metrics": str(metrics), "check": False})()
        with redirect_stdout(io.StringIO()):
            self.assertEqual(ledger.cmd_project(pr), 0)

    def test_state_refuses_missing_ledger(self):
        """空账本与读不到账本是两件事：后者意味着文件被移走，不能当普通夜晚继续跑。"""
        out = Path(self._tmp.name) / "state.json"
        st = type("A", (), {"ledger": str(Path(self._tmp.name) / "nope.ndjson"),
                            "out": str(out), "date": "2026-10-20", "allow_missing": False})()
        with self.assertRaises(LedgerError) as ctx:
            ledger.cmd_state(st)
        self.assertIn("账本不存在", str(ctx.exception))

    def test_projection_is_reproducible_and_checkable(self):
        """投影里带生成时间 = 每晚都把没变的账本改脏，CI 也没法判"投影与账本一致"。"""
        self.append_quietly(hyp_event())
        md = self.ledger_path.parent / "LEDGER.md"
        metrics = self.ledger_path.parent / "m.json"
        args = type("A", (), {"ledger": str(self.ledger_path), "out_md": str(md),
                              "out_metrics": str(metrics), "check": False})()
        with redirect_stdout(io.StringIO()):
            ledger.cmd_project(args)
        first = md.read_text(encoding="utf-8")
        with redirect_stdout(io.StringIO()):
            ledger.cmd_project(args)
        self.assertEqual(first, md.read_text(encoding="utf-8"))
        check = type("A", (), {"ledger": str(self.ledger_path), "out_md": str(md),
                               "out_metrics": str(metrics), "check": True})()
        with redirect_stdout(io.StringIO()):
            self.assertEqual(ledger.cmd_project(check), 0)
        md.write_text("手写投影\n", encoding="utf-8")
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(ledger.cmd_project(check), 1, "投影被手改必须被 --check 抓到")

    def test_crashed_gate_nights_do_not_count_as_skips(self):
        """§3.6 的分母纪律：闸门自己崩掉的夜晚连一次有效评估都没做成。"""
        self.append_quietly(gate_row(type="gate_skipped_run", budget_bucket="meta",
                                     gate={"channel": "none",
                                           "reasons": ["maintenance_budget_exhausted"],
                                           "dimension": None}))
        self.append_quietly(gate_row(type="gate_skipped_run", budget_bucket="meta",
                                     gate={"channel": "none", "reasons": ["gate_step_failed"],
                                           "dimension": None}))
        md = self.ledger_path.parent / "LEDGER.md"
        metrics = self.ledger_path.parent / "m.json"
        args = type("A", (), {"ledger": str(self.ledger_path), "out_md": str(md),
                              "out_metrics": str(metrics), "check": False})()
        with redirect_stdout(io.StringIO()):
            ledger.cmd_project(args)
        data = json.loads(metrics.read_text(encoding="utf-8"))
        self.assertEqual(data["gate_unavailable"], 1)
        self.assertEqual(data["gate_skip_rate"], 1.0,
                         "分母必须剔掉不可用夜晚，否则坏闸门看起来很有用")

    def test_registry_label_collision_is_surfaced_not_merged(self):
        """同一个注册表标签挂两个身份 = 注册表自己漂了；账本如实记录，不替它合并。"""
        registry = self.registry([
            ("aaaaaaaaaaaaaaaa", "F-2026-09-10-01", "test-gap", "a_test.dart", "NEW",
             "#265", "2026-09-10", "2026-09-10"),
            ("bbbbbbbbbbbbbbbb", "F-2026-09-10-01", "architecture", "b.dart", "NEW",
             "N/A", "2026-09-10", "2026-09-10"),
        ])
        args = type("A", (), {"ledger": str(self.ledger_path), "registry": str(registry),
                              "date": "2026-10-03", "dry_run": False})()
        with redirect_stdout(io.StringIO()):
            self.assertEqual(ledger.cmd_import_findings(args), 0)
        md = self.ledger_path.parent / "LEDGER.md"
        metrics = self.ledger_path.parent / "m.json"
        pr = type("A", (), {"ledger": str(self.ledger_path), "out_md": str(md),
                            "out_metrics": str(metrics), "check": False})()
        with redirect_stdout(io.StringIO()):
            ledger.cmd_project(pr)
        data = json.loads(metrics.read_text(encoding="utf-8"))
        self.assertEqual(data["registry_label_collisions"], 1)
        self.assertEqual(data["identity_source"], {"registry_declared": 2})
        self.assertIn("身份来源告警", md.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
