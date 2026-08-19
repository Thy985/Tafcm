"""FFX Verification Orchestrator — 能力无关的编排循环。

verify / diagnose / repair-verify 三命令的通用逻辑。
退出码：0 PASS / 1 FAIL / 2 WARN / 3 INCONCLUSIVE / 127 ENV_MISSING（ADR-0030）。
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from . import contract as contract_mod
from . import failure as failure_mod
from .adapters import create
from .adapters.base import CapabilityAdapter
from .evidence import Evidence, EvidenceGraph

_STATUS_EXIT = {"pass": 0, "warn": 2, "fail": 1, "inconclusive": 3}


def _as_of() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _load_adapter(capability: str) -> CapabilityAdapter:
    contract = contract_mod.load_contract(capability)
    return create(capability, contract)  # type: ignore[return-value]


def verify(capability: str) -> tuple[dict[str, Any], int]:
    """执行完整验证链 → (report, exit_code)。FAIL 时写 Failure Record 并返回 diagnostic_id。"""
    graph = EvidenceGraph()
    try:
        adapter = _load_adapter(capability)
    except (contract_mod.ContractError, KeyError) as e:
        report = {
            "capability": capability,
            "status": "error",
            "message": str(e),
            "evidence": [],
            "as_of": _as_of(),
        }
        return report, 2

    try:
        adapter.discover(graph)
        adapter.prepare(graph)
        adapter.execute(graph)
        adapter.collect_evidence(graph)
        decision = adapter.evaluate(graph)
    except EnvironmentError as e:
        report = {
            "capability": capability,
            "status": "env_missing",
            "message": str(e),
            "evidence": graph.to_list(),
            "as_of": _as_of(),
        }
        return report, 127
    except Exception as e:  # runner/桥接失败 → FAIL（非环境）
        graph.add(Evidence("verify", "orchestrator", 1, f"verification error: {e}"))
        report = {
            "capability": capability,
            "status": "fail",
            "message": f"verification error: {e}",
            "evidence": graph.to_list(),
            "as_of": _as_of(),
        }
        return report, 1

    status = decision["status"]
    report: dict[str, Any] = {
        "capability": capability,
        "status": status,
        "coverage": decision.get("coverage", {}),
        "unknown": decision.get("unknown", []),
        "next_actions": decision.get("next_actions", []),
        "evidence": graph.to_list(),
        "as_of": _as_of(),
    }
    exit_code = _STATUS_EXIT.get(status, 3)

    if status == "fail":
        fid = failure_mod.next_artifact_id()
        failure_mod.write_failure({
            "id": fid,
            "capability": capability,
            "status": "failed",
            "stage": "evaluate",
            "tool": "ffx",
            "summary": f"checks failed: {decision.get('coverage', {}).get('checks')}",
            "before": {"status": "failed", "coverage": decision.get("coverage", {})},
            "evidence": graph.to_list(),
        })
        report["diagnostic_id"] = fid
    return report, exit_code


def diagnose(failure_id: str) -> dict[str, Any]:
    """按 Failure Record 聚合诊断包（不自动修复）。"""
    try:
        rec = failure_mod.load_failure(failure_id)
    except FileNotFoundError as e:
        return {"failure_id": failure_id, "status": "error", "message": str(e)}

    prefix = failure_id.split("_")[0]
    bundle: dict[str, Any] = {
        "failure_id": failure_id,
        "capability": rec.get("capability"),
        "stage": rec.get("stage"),
        "summary": rec.get("summary"),
        "evidence": rec.get("evidence", []),
        # R13 修复：按证据链做根因分类（替代写死 suggested_next_action）——
        # 依据 stage 顺序 + exit_code 模式，给 Agent 可消费的分类信号。
        "root_cause": _classify_root_cause(rec),
    }
    if prefix == "trc":
        # ADI 关联（P0.1 markdown 失败为 art_；trc_ 分支预留，ADL 对齐后实现）
        bundle["adi"] = {
            "note": "trc_ prefix: bind to ADI trace (latest-error/trace/replay)",
            "bound": False,
        }
    else:
        bundle["artifact"] = {
            "note": "art_ prefix: artifact/verification failure, no ADI trace",
            "before": rec.get("before", {}),
        }
    bundle["suggested_next_action"] = "inspect evidence, fix root cause, then: ffx capability repair-verify " + failure_id
    return bundle


def _classify_root_cause(rec: dict) -> dict[str, Any]:
    """R13：基于 failure record 的证据链做根因分类（启发式，非穷举）。

    分类信号（按优先级）：
    - 存在 exit_code 127 证据 → env_missing（环境缺失）
    - stage 停在 discover/prepare → setup_failure（准备阶段失败）
    - stage 停在 execute 且 evidence 含 runner 错误 → runner_failure
    - 其余 → unknown（无法从证据确定）
    """
    evidence = rec.get("evidence", []) or []
    exit_codes = [e.get("exit_code") for e in evidence if isinstance(e, dict)]
    stages = [e.get("stage") for e in evidence if isinstance(e, dict)]

    if 127 in exit_codes:
        return {"category": "env_missing", "signal": "exit_code 127 (ENV_MISSING)"}
    if "execute" in stages:
        return {"category": "runner_failure", "signal": f"evidence stages: {stages}"}
    if stages and stages[-1] in ("discover", "prepare"):
        return {"category": "setup_failure", "signal": f"stopped at stage: {stages[-1]}"}
    return {"category": "unknown", "signal": f"exit_codes={exit_codes}"}


def repair_verify(failure_id: str) -> tuple[dict[str, Any], int]:
    """修复后重验：before/after/regression 实证（Agent 声明仅触发，不证明）。"""
    try:
        rec = failure_mod.load_failure(failure_id)
    except FileNotFoundError as e:
        return {"failure_id": failure_id, "status": "error", "message": str(e)}, 2

    capability = rec.get("capability", "markdown")
    report, exit_code = verify(capability)
    after_status = report.get("status")
    before = rec.get("before", {})

    # evidence_delta：对比 before/after 的 coverage 快照
    before_cov = before.get("coverage", {})
    after_cov = report.get("coverage", {})
    delta = _diff_coverage(before_cov, after_cov)

    # R7 修复：除 coverage 数字外，对比 evidence 内容（新增/消失的
    # stage 或 summary 变化）——回归信号不应只看数字，还应看证据链变化。
    before_ev = rec.get("evidence", [])
    after_ev = report.get("evidence", [])
    before_stages = {e.get("stage") for e in before_ev if isinstance(e, dict)}
    after_stages = {e.get("stage") for e in after_ev if isinstance(e, dict)}
    evidence_delta = {
        "new_stages": sorted(after_stages - before_stages),
        "gone_stages": sorted(before_stages - after_stages),
        "before_count": len(before_ev),
        "after_count": len(after_ev),
    }

    regression: dict[str, Any] = {"status": "n/a", "detail": "only 1 capability in registry (P0.1)"}
    result = {
        "before": before.get("status", "unknown"),
        "after": after_status,
        "regression": regression,
        "evidence_delta": delta,
        "evidence_graph_delta": evidence_delta,
        "diagnostic_id": failure_id,
        "report": report,
    }
    return result, exit_code


def _diff_coverage(before: dict, after: dict) -> list[dict[str, Any]]:
    keys = set(before) | set(after)
    out = []
    for k in sorted(keys):
        b, a = before.get(k), after.get(k)
        # R15 修复：类型规范化后再比较——int 1 与 float 1.0 语义相同，
        # 直接 != 会误报 delta（噪声）。数值统一转 float 比较。
        if _values_differ(b, a):
            out.append({"metric": k, "before": b, "after": a})
    return out


def _values_differ(b: Any, a: Any) -> bool:
    """R15：规范化比较——数值 int/float 归一化；否则严格 !=。"""
    if isinstance(b, (int, float)) and isinstance(a, (int, float)):
        return float(b) != float(a)
    return b != a
