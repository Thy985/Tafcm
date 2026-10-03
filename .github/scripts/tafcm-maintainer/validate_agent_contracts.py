#!/usr/bin/env python3
"""仓库 Agent 控制面契约校验（Repository Agent Control Plane，见
.github/仓库Agent设计与治理.md §3.8）。

校验 .github/schemas/{ledger-event,gate-result,verdict}.schema.json 三份接口：
单文件结构约束 + 跨文件枚举一致性。跨文件一致性是本脚本的存在理由——三份契约各自
演化时 Scheduler / Scout / Investigator / Verifier 的字段语义会悄悄分叉，workflow
层看不出异常，直到账本投影写不出来。

纯 stdlib（与 cline_fallback_runner.py 同约束）。退出码 0 = 全部通过。
用法：在仓库根目录 `python3 .github/scripts/tafcm-maintainer/validate_agent_contracts.py`
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SCHEMA_DIR = REPO_ROOT / ".github" / "schemas"
REQUIRED_SCHEMAS = [
    "findings.schema.json",
    "ledger-event.schema.json",
    "gate-result.schema.json",
    "verdict.schema.json",
]

DIMENSIONS = {
    "performance",
    "correctness_test_gap",
    "architecture_data_flow",
    "persistence",
    "export",
    "ux_state",
    "infra_ci",
}

INDEPENDENCE_PROOFS = {
    "preexisting_oracle",
    "differential_test",
    "clean_checkout_reproduction",
    "deterministic_ci_rerun",
    "external_contract",
}

PUBLISHER_ACTIONS = {"create_issue", "comment_existing", "suggest_only", "drop"}

# importer 是历史导入专用角色：导入行必须与实时 Agent 事件可区分，
# 否则"这条是谁证的"在账本里说不清（P0-2 的 provenance 要求）。
ACTORS = {"scheduler", "scout", "investigator", "verifier", "publisher",
          "supervisor", "human", "importer"}

VERIFIER_CHECKS = {
    "schema_valid",
    "fingerprint_dedupe_clear",
    "falsifier_present",
    "invariant_provenance",
    "differential_arms_present",
    "repro_artifact_committed",
    "clean_checkout_rerun_matches_claim",
    "sandbox_isolation_verified",
    "tier_run_separation",
    "severity_within_tier_ceiling",
    "budget_within_cap",
    "secret_leak_scan_clean",
    "record_kb_within",
    "protocol_required_evidence_present",
}

_failures: list[str] = []


def check(cond: bool, msg: str) -> None:
    if not cond:
        _failures.append(msg)


def load(name: str) -> dict:
    path = SCHEMA_DIR / name
    if not path.is_file():
        _failures.append(f"{name}: 文件不存在")
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        _failures.append(f"{name}: JSON 解析失败 {exc}")
        return {}


def enums(node: dict | None, key: str) -> set:
    """取某字段枚举里的字符串项。"""
    if not isinstance(node, dict):
        return set()
    field = node.get(key)
    if not isinstance(field, dict):
        return set()
    return {v for v in field.get("enum", []) if isinstance(v, str)}


def main() -> int:
    # 路径由 __file__ 解析，不依赖 cwd：本地从 scripts 目录跑和 CI 从仓库根跑必须同结果
    if not SCHEMA_DIR.is_dir():
        print(f"FAIL: 找不到 schema 目录 {SCHEMA_DIR}", file=sys.stderr)
        return 2

    for name in REQUIRED_SCHEMAS:
        check((SCHEMA_DIR / name).is_file(), f"{name}: 缺失")

    ledger = load("ledger-event.schema.json")
    gate = load("gate-result.schema.json")
    verdict = load("verdict.schema.json")
    if _failures:
        return report()

    # ---------------- ledger-event：append-only 事件流 ----------------
    lp = ledger.get("properties", {})
    for field in ("schema_version", "event_id", "ts", "type", "actor", "run_id", "budget_bucket"):
        check(field in ledger.get("required", []), f"ledger-event: {field} 必须 required")
    check(enums(lp, "actor") >= ACTORS,
          f"ledger-event: actor 枚举缺角色 {sorted(ACTORS - enums(lp, 'actor'))}")
    check(enums(lp, "budget_bucket") >= {"maintenance", "exploration", "meta"},
          "ledger-event: budget_bucket 枚举不完整")

    defs = ledger.get("definitions", {})
    hypothesis = defs.get("hypothesis", {})
    hp = hypothesis.get("properties", {})
    check("falsifier" in hypothesis.get("required", []),
          "ledger-event: hypothesis.falsifier 必须 required（无否证条件即不可实验）")
    check("invariant_source" in hp,
          "ledger-event: 缺 hypothesis.invariant_source（L0/L1/L2 的机械分水岭）")
    source = hp.get("invariant_source", {})
    check("self_authored" in enums(source.get("properties", {}), "kind"),
          "ledger-event: invariant_source.kind 必须含 self_authored（用于把自证封顶在 L1）")
    check("ref_commit" in source.get("properties", {}),
          "ledger-event: invariant_source 缺 ref_commit（provenance 需可被 git 否证）")
    check("evidence_tier" in hp and {"L0", "L1", "L2"} <= enums(hp, "evidence_tier"),
          "ledger-event: evidence_tier 枚举必须是 L0/L1/L2")
    check("lifecycle_stage" in hp,
          "ledger-event: 缺 lifecycle_stage（与 tier / publisher_action 正交的第三条轴）")

    evidence = defs.get("evidence", {})
    proofs_ledger = set(evidence.get("properties", {}).get("independence_proofs", {})
                        .get("items", {}).get("enum", []))
    check(proofs_ledger == INDEPENDENCE_PROOFS,
          f"ledger-event: independence_proofs 漂移 {sorted(proofs_ledger)}")
    dim_ledger = enums(hp, "dimension")
    check(dim_ledger == DIMENSIONS, f"ledger-event: dimension 漂移 {sorted(dim_ledger)}")

    experiment = defs.get("experiment", {})
    arms = experiment.get("properties", {}).get("arms", {})
    check(arms.get("minItems") == 0, "ledger-event: arms 应允许为空（L0/L1 无对照）")

    # ---------------- gate-result：双路 eligibility ----------------
    check(gate.get("additionalProperties") is False,
          "gate-result: 顶层必须 additionalProperties=false（禁止把 LLM 输出夹带进 gate）")
    for field in ("eligible", "maintenance", "exploration", "budget"):
        check(field in gate.get("required", []), f"gate-result: {field} 必须 required")
    check("due" in gate["properties"]["exploration"].get("properties", {}),
          "gate-result: exploration.due 缺失（漏掉它=探索通道被砍）")
    check("work_present" in gate["properties"]["maintenance"].get("properties", {}),
          "gate-result: maintenance.work_present 缺失")
    check("noop_record" in gate["properties"], "gate-result: 缺 noop_record（NO_WORK 机读终态）")
    dimension = gate["properties"].get("dimension", {})
    check("workset" in dimension.get("properties", {}),
          "gate-result: dimension.workset 缺失（工作集是预算的真正来源）")
    score = dimension.get("properties", {}).get("score_components", {})
    check("evidence_cost" in score.get("properties", {}),
          "gate-result: score_components 缺 evidence_cost（必须在分母）")
    check(enums(dimension.get("properties", {}), "assigned") == DIMENSIONS,
          f"gate-result: dimension.assigned 漂移 "
          f"{sorted(enums(dimension.get('properties', {}), 'assigned'))}")
    check(dimension.get("required", []) and "assigned" in dimension.get("required", []),
          "gate-result: dimension.assigned 必须 required")

    # ---------------- verdict：机器决定是否改变仓库状态 ----------------
    vp = verdict.get("properties", {})
    for field in ("checks", "decision", "publisher_action"):
        check(field in verdict.get("required", []), f"verdict: {field} 必须 required")
    check_items = vp.get("checks", {}).get("items", {})
    check_props = check_items.get("properties", {})
    check(enums(check_props, "name") >= VERIFIER_CHECKS,
          f"verdict: checks 枚举不完整，缺 {sorted(VERIFIER_CHECKS - enums(check_props, 'name'))}")
    check({"pass", "fail", "skip", "not_applicable"} <= enums(check_props, "status"),
          "verdict: check.status 枚举不完整")
    check("tier_granted" in vp, "verdict: 缺 tier_granted（verifier 必须重判而非采信申报）")
    check(enums(vp, "publisher_action") == PUBLISHER_ACTIONS,
          f"verdict: publisher_action 漂移 {sorted(enums(vp, 'publisher_action'))}")
    l2 = verdict.get("x-l2-definition", {})
    check(len(l2.get("tier_granted_L2_requires_all", [])) == 3,
          "verdict: L2 必须是三条件合取（稳定复现 ∧ 独立凭证 ∧ 确定性重跑）")
    proofs_verdict = set(vp.get("independence_proofs_granted", {})
                         .get("items", {}).get("enum", []))
    check(proofs_verdict == INDEPENDENCE_PROOFS,
          f"verdict: independence_proofs_granted 漂移 {sorted(proofs_verdict)}")

    # ---------------- 跨文件耦合 ----------------
    check("verdict" in lp, "ledger-event: 必须内嵌 verdict（publisher 的唯一输入）")
    embedded = lp.get("verdict", {})
    check("publisher_action" in json.dumps(embedded),
          "ledger-event: 内嵌 verdict 必须含 publisher_action")
    check({"verdict_recorded", "published", "gate_no_work", "gate_eligible",
           "gate_skipped_run", "hypothesis_added"}
          <= enums(lp, "type"),
          "ledger-event: type 枚举缺关键事件（gate_eligible 必须有，否则 gate_skip_rate 无分母）")
    check("created_by_run" in hp,
          "ledger-event: 缺 created_by_run（tier_run_separation 的比较基准）")
    check("last_observed" in hp,
          "ledger-event: 缺 hypothesis.last_observed —— 陈旧度必须来自观察日期；"
          "用事件写入时间会让一次历史回填把所有维度的探测节律清零")

    # ---------------- 红线：契约文件内不得含密钥形态 ----------------
    blob = json.dumps([ledger, gate, verdict])
    # 只认真实密钥形状：sk- 前必须是非字母数字，后随 >=8 位（避免 risk-driven 之类误报）
    check(re.search(r"(?<![0-9A-Za-z])sk-[0-9A-Za-z]{8,}", blob) is None,
          "契约文件中出现疑似密钥字串")

    return report()


def report() -> int:
    if _failures:
        print("[FAIL] Agent 控制面契约校验未通过：", file=sys.stderr)
        for f in _failures:
            print(f"   - {f}", file=sys.stderr)
        return 1
    # 输出用 ASCII 标记：Windows GBK 控制台无法编码 ✅/❌（会让成功的运行崩成 exit 1）
    print("[OK] Agent 控制面契约校验通过："
          f"{len(REQUIRED_SCHEMAS)} 份 schema；{len(DIMENSIONS)} 维度 / "
          f"{len(INDEPENDENCE_PROOFS)} 种独立性凭证 / {len(VERIFIER_CHECKS)} 项 verifier 检查 / "
          f"{len(ACTORS)} 种 actor，跨文件枚举一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
