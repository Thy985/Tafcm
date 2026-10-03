#!/usr/bin/env python3
"""双路 Eligibility Gate + 确定性 Dimension Scheduler（P0-1）。

契约：`.github/schemas/gate-result.schema.json`（写前自校验 + KB 硬顶）。

两条**独立**的 eligibility：

    eligible = maintenance.work_present OR exploration.due

- Maintenance（precision 通道）：由变更驱动——新 commit / 未分诊 issue / CI 红 /
  Frontier 变化。
- Exploration（recall 通道）：由**预算与陈旧度**驱动——探索槽位到期 / 维度长期未探测 /
  结构性抖动 / 从未探测过的维度 / 覆盖下限。

为什么必须两条：单一 has-work 闸会把 repository-driven 主动探索一起关掉，而那正是
#245-250 性能批次这类已验证价值产出的来源（见 .github/仓库Agent设计与治理.md §3.1）。

**零 LLM**：本步骤不得调用任何模型，也不得从模型输出取任何字段
（schema 顶层 additionalProperties=false 就是为此兜底）。

纯 stdlib，可在 CI 与本地运行。测试用 `--fixture` 注入信号，不碰网络。
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_SCHEMA = REPO_ROOT / ".github" / "schemas" / "gate-result.schema.json"
DEFAULT_FRONTIER = REPO_ROOT / ".agent" / "tafcm-maintainer" / "FRONTIER.md"

MAINTENANCE_CAP_TODAY = 1.0      # 单位：llm_cost_estimate
EXPLORATION_CAP_TODAY = 0.6
EXPLORATION_SLOT_DAYS = 7        # 每周一次探索槽位
DIMENSION_STALE_DAYS = 21        # 超过即视为 frontier 陈旧
NEVER_PROBED_STALENESS = 90      # 从未探测过维度的陈旧度替身
COVERAGE_FLOOR_DAYS = 30         # 高实验成本维度的覆盖下限

# 维度 → 允许观察的工作集前缀（成本归因到工作集大小，不归因到日历条数）
DIMENSION_WORKSET = {
    "performance": ("flutter_app/lib/core/", "flutter_app/lib/domain/"),
    "correctness_test_gap": ("flutter_app/lib/core/parser/", "flutter_app/test/"),
    "architecture_data_flow": ("flutter_app/lib/",),
    "persistence": ("flutter_app/lib/core/services/", "flutter_app/lib/data/"),
    "export": ("flutter_app/lib/domain/services/",),
    "ux_state": ("flutter_app/lib/presentation/", "flutter_app/lib/providers/"),
    "infra_ci": (".github/", "tools/"),
}

# 实验成本查表（protocol 维度的固有成本，不由模型填写）
DIMENSION_EVIDENCE_COST = {
    "performance": 2.0,          # 需要 benchmark
    "correctness_test_gap": 1.5,  # 需要 reproduction + test
    "export": 2.5,               # 需要实际 artifact 比对
    "persistence": 2.0,          # round-trip + 崩溃恢复
    "architecture_data_flow": 1.0,  # trace 为主，最便宜
    "ux_state": 3.0,             # 常需真机
    "infra_ci": 1.0,
}

ACTIVATION_WEIGHT = {
    "test-failure": 3.0,
    "changed-code": 2.0,
    "new-issue": 2.0,
    "ci-red": 2.5,
    "structural-churn": 1.6,
    "frontier-stale": 1.2,
    "new-evidence": 1.4,
    "risk-driven": 1.0,
    "scheduled_slot": 1.0,
    "dimension_never_probed": 1.3,
    "coverage_floor": 1.2,
}

# 期望价值 = severity 档 × 该维度历史采纳率；无历史时用保守先验（不用模型自评）
DEFAULT_EXPECTED_VALUE = 0.4
SEVERITY_FACTOR = {"critical": 1.0, "high": 0.8, "medium": 0.5, "low": 0.25}


class GateError(RuntimeError):
    """gate 自身算不出来 —— 必须响，不得静默降级成 NO_WORK。"""


# ---------------------------------------------------------------- 探针（真实运行）
def _run(args: list[str]) -> str:
    import subprocess

    proc = subprocess.run(args, cwd=REPO_ROOT, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
    if proc.returncode != 0:
        raise GateError(f"探针失败: {' '.join(args)} -> {proc.stderr.strip()[:200]}")
    return proc.stdout


def _last_audit_date(frontier_mode: str = "audit") -> date | None:
    """最近一次 daily maintainer audit 提交日期（近似"上次审查时刻"）。"""
    try:
        out = _run(["git", "log", "-1", "--format=%cd", "--date=short",
                    "--grep=chore(agent): daily maintainer audit", "origin/main"])
    except GateError:
        return None
    out = out.strip()
    if not out:
        return None
    try:
        return date.fromisoformat(out)
    except ValueError:
        raise GateError(f"无法解析 audit 日期: {out!r}")


def _collect_live_signals(run_date: date) -> dict:
    audit_at = _last_audit_date()
    since = (audit_at - timedelta(days=1)) if audit_at else (run_date - timedelta(days=1))
    raw = _run(["git", "log", f"--since={since.isoformat()}", "--name-only",
                "--format=COMMIT:%H", "origin/main"])
    commits: dict[str, list[str]] = {}
    current = None
    for line in raw.splitlines():
        line = line.strip()
        if line.startswith("COMMIT:"):
            current = line[len("COMMIT:"):]
            commits.setdefault(current, [])
        elif line and current:
            commits[current].append(line)

    untriaged = _run(["gh", "issue", "list", "--state", "open", "--search", "no:label",
                      "--json", "number", "--jq", "length"]).strip()
    failed = _run(["gh", "run", "list", "--branch", "main", "--limit", "20",
                   "--json", "conclusion", "--jq",
                   '[.[] | select(.conclusion=="failure")] | length']).strip()
    churn_raw = _run(["git", "log", "--since", (run_date - timedelta(days=7)).isoformat(),
                      "--numstat", "--format=", "origin/main"])
    churn: dict[str, int] = {}
    for line in churn_raw.splitlines():
        parts = line.split("\t")
        if len(parts) == 3 and parts[0].isdigit():
            churn[parts[2].strip()] = churn.get(parts[2].strip(), 0) + int(parts[0])

    return {
        "date": run_date.isoformat(),
        "commits_since_last_audit": [{"sha": sha, "paths": paths}
                                     for sha, paths in commits.items()],
        "untriaged_issue_count": int(untriaged or 0),
        "failed_check_count": int(failed or 0),
        "frontier_open_candidates": _frontier_open_count(),
        "days_since_last_exploration": None,   # 无账本前由 --fixture 或人工提供
        "last_exploration_date": None,
        "dimension_state": {},
        "churn": churn,
        "budget": {},
    }


def _frontier_open_count() -> int:
    if not DEFAULT_FRONTIER.is_file():
        return 0
    text = DEFAULT_FRONTIER.read_text(encoding="utf-8")
    active = text.split("## 冷却区")[0]
    return active.count("\n### FR-")


# ---------------------------------------------------------------- 判定
def maintenance_channel(signals: dict) -> dict:
    reasons: list[str] = []
    commits = signals.get("commits_since_last_audit") or []
    if commits:
        reasons.append("changed_code")
    if int(signals.get("untriaged_issue_count") or 0) > 0:
        reasons.append("untriaged_issue")
    if int(signals.get("failed_check_count") or 0) > 0:
        reasons.append("test_failure")
    if int(signals.get("frontier_open_candidates") or 0) > 0:
        reasons.append("frontier_change")

    changed_paths = sorted({p for c in commits for p in c.get("paths", [])})
    return {
        "work_present": bool(reasons),
        "reasons": sorted(reasons),
        "signals": {
            "commits_since_last_audit": len(commits),
            "changed_paths": changed_paths[:40],
            "untriaged_issue_count": int(signals.get("untriaged_issue_count") or 0),
            "failed_check_count": int(signals.get("failed_check_count") or 0),
            "open_candidate_count": int(signals.get("frontier_open_candidates") or 0),
        },
    }


def exploration_channel(signals: dict, run_date: date, dimension_ids: list[str],
                        stale_dimensions: list[str]) -> dict:
    reasons: list[str] = []
    gap = signals.get("days_since_last_exploration")
    last = signals.get("last_exploration_date")
    if gap is None and last is None:
        # 账本尚未建立时，探索通道按周槽位兜底运行（否则探索能力会被静默清零）
        if run_date.weekday() == 2:
            reasons.append("scheduled_slot")
    elif gap is not None and int(gap) >= EXPLORATION_SLOT_DAYS:
        reasons.append("scheduled_slot")

    state = signals.get("dimension_state", {}) or {}
    if stale_dimensions:
        never = [d for d in stale_dimensions if state.get(d, {}).get("never_probed")]
        reasons.append("dimension_never_probed" if never else "frontier_stale")

    churn = signals.get("churn") or {}
    if sum(churn.get(p, 0) for p in churn if p.startswith("flutter_app/lib/")) > 800:
        reasons.append("structural_churn")

    high_cost_covered = []
    for dim in dimension_ids:
        if DIMENSION_EVIDENCE_COST.get(dim, 1.0) < 3.0:
            continue
        d_state = state.get(dim, {}) or {}
        days = _days_since(d_state.get("last_probed"), run_date)
        if d_state.get("never_probed") or (days is not None and days >= COVERAGE_FLOOR_DAYS):
            high_cost_covered.append(dim)
    if high_cost_covered:
        reasons.append("coverage_floor")

    return {
        "due": bool(reasons),
        "reasons": sorted(set(reasons)),
        "signals": {
            "days_since_last_exploration": (int(gap) if gap is not None else None),
            "last_exploration_date": last,
            "stale_dimensions": sorted(stale_dimensions),
        },
    }


def _days_since(iso: str | None, run_date: date, default: int | None = None) -> int | None:
    """缺数据返回 default（默认 None = 未知），**不得**当成"很久没查"。

    把未知当陈旧会让探索通道每晚放行，正好退化成本设计要关闭的每日无界全扫。
    只有账本显式记了 never_probed 才按高陈旧度处理。
    """
    if not iso:
        return default
    try:
        return (run_date - date.fromisoformat(iso[:10])).days
    except ValueError:
        return default


def _staleness(d_state: dict, run_date: date) -> int:
    """打分用陈旧度：显式 never_probed 记高值；有日期按日期；无数据记 0（未知不占优）。"""
    if d_state.get("never_probed"):
        return NEVER_PROBED_STALENESS
    days = _days_since(d_state.get("last_probed"), run_date)
    return days if days is not None else 0


def _is_stale(d_state: dict, run_date: date) -> bool:
    """陈旧 = 账本说从没查过，或有明确日期且已超期。缺数据不算陈旧。"""
    if d_state.get("never_probed"):
        return True
    days = _days_since(d_state.get("last_probed"), run_date)
    return days is not None and days >= DIMENSION_STALE_DAYS


def _dimension_churn(churn: dict[str, int], dimension: str) -> int:
    prefixes = DIMENSION_WORKSET.get(dimension, ())
    return sum(lines for path, lines in churn.items() if path.startswith(prefixes))


def _dimension_for_path(path: str) -> str | None:
    """路径 → 维度：取**最具体**的匹配前缀。

    `flutter_app/lib/` 也匹配 presentation 下的文件；不排最长前缀的话，
    architecture_data_flow（最宽、最便宜的维度）会吞掉所有变更。
    """
    best, best_len = None, -1
    for dim, prefixes in DIMENSION_WORKSET.items():
        for prefix in prefixes:
            if path.startswith(prefix) and len(prefix) > best_len:
                best, best_len = dim, len(prefix)
    return best


def assign_dimension(signals: dict, run_date: date, maintenance: dict) -> tuple[str, dict]:
    """确定性领域分配：领域必须由本步骤决定，不得由 LLM 选——否则 Agent 会漂向
    实验成本最低的 parser/export 维度，复制 24-issue 的聚类偏差。"""
    state = signals.get("dimension_state") or {}
    churn = signals.get("churn") or {}
    changed = maintenance["signals"]["changed_paths"]

    if maintenance["work_present"]:
        counts: dict[str, int] = {}
        for path in changed:
            dim = _dimension_for_path(path)
            if dim:
                counts[dim] = counts.get(dim, 0) + 1
        pool = [d for d, _ in sorted(counts.items(), key=lambda t: (-t[1], t[0]))] \
            or list(DIMENSION_WORKSET)
        reason = "changed-code"
    else:
        never = [d for d in DIMENSION_WORKSET if (state.get(d) or {}).get("never_probed")]
        known_stale = [d for d in DIMENSION_WORKSET
                       if _is_stale(state.get(d) or {}, run_date)
                       and not (state.get(d) or {}).get("never_probed")]
        # 无数据 ≠ 陈旧：未知维度只作为兜底池参与打分，不构成为由放行探索
        pool = never or known_stale or list(DIMENSION_WORKSET)
        reason = ("dimension_never_probed" if never
                  else "frontier-stale" if known_stale else "risk-driven")

    scored: list[tuple[float, str, dict]] = []
    for dim in pool:
        d_state = state.get(dim, {}) or {}
        staleness = _staleness(d_state, run_date)
        churn_value = _dimension_churn(churn, dim)
        severity = d_state.get("open_severity", "medium")
        risk = SEVERITY_FACTOR.get(severity, SEVERITY_FACTOR["medium"])
        expected = float(d_state.get("adopted_rate", DEFAULT_EXPECTED_VALUE))
        weight = ACTIVATION_WEIGHT.get(reason, 1.0)
        cost = DIMENSION_EVIDENCE_COST.get(dim, 1.0)
        score = (risk * (1.0 + churn_value / 1000.0) * (1.0 + staleness / 30.0)
                 * weight * max(expected, 0.05)) / cost
        components = {
            "risk": round(risk, 4),
            "churn": churn_value,
            "staleness_days": staleness,
            "activation_weight": round(weight, 4),
            "expected_value": round(expected, 4),
            "evidence_cost": cost,
            "score": round(score, 6),
        }
        scored.append((score, dim, components))

    # 决定性排序：分数 → 陈旧度 → 名称（同分不得随运行漂移）
    scored.sort(key=lambda t: (-t[0], -t[2]["staleness_days"], t[1]))
    best_score, best_dim, best_components = scored[0]

    workset = sorted({p for p in (signals.get("churn") or {})
                      if p.startswith(DIMENSION_WORKSET[best_dim])})[:25]
    if not workset:
        workset = list(DIMENSION_WORKSET[best_dim])

    return best_dim, {
        "assigned": best_dim,
        "workset": workset,
        "candidates": [f"HYP-{int(c):03d}" for c in
                       (signals.get("dimension_state", {}).get(best_dim, {})
                        .get("candidate_ids", []))],
        "score_components": best_components,
        "anti_inflation": {
            "severity_ceiling_by_tier": {"L0": "medium", "L1": "high", "L2": "critical"},
            "llm_scored_fields_capped": ["severity", "expected_value"],
        },
    }


def budget_block(signals: dict) -> dict:
    given = signals.get("budget") or {}

    def bucket(name: str, cap: float, unit: str = "llm_cost_estimate") -> dict:
        raw = given.get(name) or {}
        spent = float(raw.get("spent_today", 0.0))
        remaining = round(max(cap - spent, 0.0), 4)
        return {
            "spent_today": spent,
            "cap_today": cap,
            "spent_this_week": float(raw.get("spent_this_week")) if
                "spent_this_week" in raw else None,
            "cap_this_week": float(raw.get("cap_this_week")) if
                "cap_this_week" in raw else None,
            "remaining": remaining,
            "unit": unit,
            "exhausted": remaining <= 0.0,
        }

    return {"maintenance": bucket("maintenance", MAINTENANCE_CAP_TODAY),
            "exploration": bucket("exploration", EXPLORATION_CAP_TODAY)}


def evaluate(signals: dict, run_date: date) -> dict:
    maintenance = maintenance_channel(signals)
    state = signals.get("dimension_state") or {}
    stale_dims = [d for d in DIMENSION_WORKSET if _is_stale(state.get(d) or {}, run_date)]
    exploration = exploration_channel(signals, run_date, list(DIMENSION_WORKSET), stale_dims)
    budget = budget_block(signals)

    # 每条通道各自受自己的预算约束；两本账都空时必须停下（旧写法在这里会漏：
    # maintenance 耗尽 + exploration 耗尽时仍会算出 eligible=true）。
    can_maintenance = maintenance["work_present"] and not budget["maintenance"]["exhausted"]
    can_exploration = exploration["due"] and not budget["exploration"]["exhausted"]
    eligible = can_maintenance or can_exploration

    if eligible:
        reason = None
    elif maintenance["work_present"] and exploration["due"]:
        reason = "both_budgets_exhausted"
    elif maintenance["work_present"]:
        reason = "maintenance_budget_exhausted"
    elif exploration["due"]:
        reason = "exploration_budget_exhausted"
    else:
        reason = "no_work"

    dimension = None
    if eligible:
        dim_id, dimension = assign_dimension(signals, run_date, maintenance)
    else:
        dim_id = None

    noop = None
    if not eligible:
        noop = {
            "date": run_date.isoformat(),
            "reason": reason or "no_work",
            "duration_s": None,
            "llm_activated": False,
        }

    return (
        {
            "schema_version": "1.0",
            "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "run_date": run_date.isoformat(),
            "eligible": eligible,
            "maintenance": maintenance,
            "exploration": exploration,
            "not_eligible_reason": reason,
            "dimension": dimension,
            "budget": budget,
            "noop_record": noop,
        },
        {
            "channel": ("maintenance" if maintenance["work_present"]
                        else "exploration" if exploration["due"] else "none"),
            "dimension_id": dim_id,
        },
    )


# ---------------------------------------------------------------- 输出
def emit(result: dict, extras: dict, out_path: Path, schema_path: Path, max_kb: float,
         summary_path: Path | None, github_output: Path | None) -> list[str]:
    from contract_minicheck import load_schema, validate

    channel = extras["channel"]
    dim_id = extras["dimension_id"]

    schema = load_schema(schema_path)
    errors = validate(result, schema, schema)
    if errors:
        return [f"契约校验失败: {e}" for e in errors]

    text = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True)
    size_kb = len(text.encode("utf-8")) / 1024.0
    if size_kb > max_kb:
        return [f"记录超限 {size_kb:.1f}KB > {max_kb}KB（防账本自毁）"]

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(text + "\n", encoding="utf-8")

    lines = [
        f"# Eligibility Gate — {result['run_date']}",
        "",
        f"- eligible: **{str(result['eligible']).lower()}** · channel: `{channel}` · "
        f"dimension: `{dim_id or '-'}`",
        f"- maintenance: {result['maintenance']['work_present']} "
        f"{result['maintenance']['reasons']}",
        f"- exploration: {result['exploration']['due']} {result['exploration']['reasons']}",
        f"- budget: maintenance 剩 {result['budget']['maintenance']['remaining']} / "
        f"exploration 剩 {result['budget']['exploration']['remaining']}",
    ]
    if result["noop_record"]:
        lines.append(f"- NO_WORK: `{result['noop_record']['reason']}`（本次零 token）")
    if summary_path:
        Path(summary_path).write_text("\n".join(lines) + "\n", encoding="utf-8")

    if github_output:
        with open(github_output, "a", encoding="utf-8") as fh:
            fh.write(f"eligible={str(result['eligible']).lower()}\n")
            fh.write(f"channel={channel}\n")
            fh.write(f"dimension={dim_id or ''}\n")
            fh.write(f"not_eligible_reason={result['not_eligible_reason'] or ''}\n")

    print("\n".join(lines))
    print(f"[OK] gate-result 写出 {out_path}（{size_kb:.1f}KB，契约校验通过）")
    return []


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, help="信号 JSON（测试/复盘用，给了就不跑探针）")
    parser.add_argument("--date", help="运行日期 YYYY-MM-DD（默认今天 UTC）")
    parser.add_argument("--output", type=Path,
                        default=REPO_ROOT / ".tmp" / "tafcm-maintainer" / "gate-result.json")
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    parser.add_argument("--summary", type=Path, help="GITHUB_STEP_SUMMARY 路径")
    parser.add_argument("--github-output", type=Path, help="GITHUB_OUTPUT 路径")
    parser.add_argument("--max-record-kb", type=float, default=16.0)
    parser.add_argument("--var", action="append", default=[], help="KEY=VALUE 覆盖信号")
    args = parser.parse_args(argv)

    run_date = date.fromisoformat(args.date) if args.date else datetime.now(
        timezone.utc).date()

    try:
        if args.fixture:
            signals = json.loads(Path(args.fixture).read_text(encoding="utf-8"))
            signals.setdefault("date", run_date.isoformat())
        else:
            signals = _collect_live_signals(run_date)
        for pair in args.var:
            if "=" not in pair:
                raise GateError(f"--var 需要 KEY=VALUE：{pair}")
            key, _, value = pair.partition("=")
            try:
                signals[key] = json.loads(value)
            except json.JSONDecodeError:
                signals[key] = value
    except GateError as exc:
        print(f"[FAIL] gate 探针失败：{exc}", file=sys.stderr)
        return 1
    except (json.JSONDecodeError, OSError, ValueError) as exc:
        print(f"[FAIL] gate 输入不可用：{exc}", file=sys.stderr)
        return 1

    result, extras = evaluate(signals, run_date)
    problems = emit(result, extras, Path(args.output), Path(args.schema),
                    args.max_record_kb, args.summary, args.github_output)
    if problems:
        for problem in problems:
            print(f"[FAIL] {problem}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
