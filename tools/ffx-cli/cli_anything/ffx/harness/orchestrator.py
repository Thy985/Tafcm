"""FFX Verification Orchestrator — 能力无关的编排循环。

verify / diagnose / repair-verify 三命令的通用逻辑。
退出码：0 PASS / 1 FAIL / 2 WARN / 3 INCONCLUSIVE / 127 ENV_MISSING（ADR-0030）。
"""
from __future__ import annotations

import subprocess
from datetime import datetime, timezone
from typing import Any

from . import contract as contract_mod
from . import failure as failure_mod
from .adapters import create
from .adapters.base import CapabilityAdapter
from .evidence import Evidence, EvidenceGraph

_STATUS_EXIT = {"pass": 0, "warn": 2, "fail": 1, "inconclusive": 3}


def _as_of() -> dict[str, str]:
    """G10（2026-08-20）：每个 PASS/FAIL 可回答谁/何时/哪个 git SHA。

    返回 {git_sha, timestamp}——禁止「之前跑过，所以 PASS」：证据必须
    携带执行时刻与代码版本。
    """
    sha = "unknown"
    try:
        r = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode == 0:
            sha = r.stdout.strip()[:12] or "unknown"
    except Exception:  # noqa: BLE001 — 非 git 环境降级 unknown
        sha = "unknown"
    return {
        "git_sha": sha,
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


def _extract_evidence_signature(evidence: list[dict[str, Any]]) -> str:
    """从证据链提取 signature（3.11.4 Failure Identity 四层第 4 维）：
    execute 阶段的 metrics 关键数值特征（roundtrip_convergence /
    render_failure_count / adi 观察 id 等）——同一 check 不同数值可区分。"""
    for e in evidence or []:
        if e.get("stage") != "execute":
            continue
        detail = e.get("detail") or {}
        m = detail.get("metrics") or detail
        for key in (
            "roundtrip_convergence",
            "render_failure_count",
            "adi_latest_observation",
            "passed",
            "failed",
        ):
            if key in m:
                return f"{key}={m[key]}"
    return "n/a"


def _failure_class_of(rec_or_report: dict[str, Any]) -> str:
    """failure_class（四层第 3 维）：从 status/stage/summary 推导。"""
    status = rec_or_report.get("status")
    if status == "env_missing":
        return "env_missing"
    if "runner_error" in str(rec_or_report.get("message", "")):
        return "runner_error"
    return "check_failure"


def _failure_fingerprint(
    capability: str,
    checks: dict[str, Any],
    failure_class: str = "check_failure",
    evidence_signature: str = "n/a",
) -> str:
    """失败指纹（3.11.4 Failure Identity 四层冻结，评审 §2）：
    capability + failing_check + failure_class + evidence_signature。

    'formula:render_observable:check_failure:adi=err_xxx' 与
    'formula:render_observable:svg_parse:svg_token_17' 是不同指纹——
    同一 check 下不同 bug 可区分（评审 §2：check 名不代表实际 Bug）。
    """
    failed = sorted(k for k, v in (checks or {}).items() if v is False)
    check = ",".join(failed) if failed else "fail"
    return f"{capability}:{check}:{failure_class}:{evidence_signature}"


def _baseline_failure_set(exclude_capability: str) -> set[str]:
    """baseline 失败集合 F1（3.11.3）：failures 目录中排除修复目标 capability
    的历史失败指纹——长期：bug 修复后旧指纹应被 resolved 清出 baseline。"""
    base: set[str] = set()
    try:
        for fid in failure_mod.list_failures():
            try:
                rec = failure_mod.load_failure(fid)
            except Exception:  # noqa: BLE001 — 单个 record 损坏跳过
                continue
            cap = rec.get("capability")
            if not cap or cap == exclude_capability:
                continue
            before = rec.get("before", {})
            checks = before.get("coverage", {}).get("checks", {})
            base.add(
                _failure_fingerprint(
                    cap,
                    checks,
                    _failure_class_of(rec),
                    _extract_evidence_signature(rec.get("evidence", [])),
                )
            )
    except Exception:  # noqa: BLE001 — failures 目录不可读 → 空 baseline
        return set()
    return base


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
        # 3.11 证据层明示（防证据层级偷换）：透传 adapter 的 execution 字段
        "execution": decision.get("execution", {}),
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

    # REGRESSION path（D5 修复 2026-08-20）：registry ≥2 时，遍历其他
    # capability 各自 verify——任一 fail = 修复引入了回归；全 pass = 未回归。
    regression: dict[str, Any] = {"status": "n/a", "detail": "only 1 capability in registry (P0.1)"}
    from cli_anything.ffx.harness.adapters import available as _available

    others = [c for c in _available() if c != capability]
    if others:
        reg_results: dict[str, str] = {}
        # 3.11.3 regression 语义升级（评审 §1）：baseline failure set + fingerprint diff。
        # before_failures = F1（failures 目录历史指纹，排除修复目标）
        # after_failures  = F2（repair-verify 时其他能力当前 fail 指纹）
        # new = F2-F1（真回归）/ resolved = F1-F2 / persistent = F1∩F2
        before_set = _baseline_failure_set(capability)
        after_set: set[str] = set()
        for other in others:
            other_report, other_exit = verify(other)
            other_status = other_report.get("status", "unknown")
            reg_results[other] = other_status
            if other_status == "fail":
                checks = other_report.get("coverage", {}).get("checks", {})
                after_set.add(_failure_fingerprint(other, checks))
        new_failures = sorted(after_set - before_set)
        resolved_failures = sorted(before_set - after_set)
        persistent_failures = sorted(before_set & after_set)
        regression = {
            "status": "pass" if not new_failures else "fail",
            "detail": (
                f"regression diff over {others}: {reg_results}"
                f"{' (persistent: ' + str(persistent_failures) + ')' if persistent_failures else ''}"
                if not new_failures
                else f"REGRESSION: {new_failures} new after fix ({reg_results})"
            ),
            "checked": others,
            "results": reg_results,
            "before_failures": sorted(before_set),
            "after_failures": sorted(after_set),
            "resolved_failures": resolved_failures,
            "new_failures": new_failures,
            "persistent_failures": persistent_failures,
        }
    # 3.11.5 repair result 语义（评审 §3）：Repair Success ≠ Capability Clean。
    # 3.11.6 target_failure 四态冻结（评审 §5）：unknown→pass 不应压成 PERSISTENT——
    #   RESOLVED    before 有 failure，after 无
    #   PERSISTENT  before 有 failure，after 仍有
    #   NOT_OBSERVED before 无可确认 target failure，after 通过
    #   INTRODUCED  before 无 target，after 新出现（本次引入）
    before_failed = before.get("status") == "failed"
    if not before_failed:
        target_failure = "NOT_OBSERVED" if after_status != "fail" else "INTRODUCED"
    elif after_status == "pass":
        target_failure = "RESOLVED"
    else:
        target_failure = "PERSISTENT"
    result = {
        "before": before.get("status", "unknown"),
        "after": after_status,
        "target_failure": target_failure,
        "persistent_baseline_count": len(regression.get("persistent_failures", [])),
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
