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
import re
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_SCHEMA = REPO_ROOT / ".github" / "schemas" / "gate-result.schema.json"
DEFAULT_FRONTIER = REPO_ROOT / ".agent" / "tafcm-maintainer" / "FRONTIER.md"

sys.path.insert(0, str(Path(__file__).resolve().parent))
# state 契约的真相在写入方（ledger.py state）；两边各写一份键名，漂移就只能靠影子期
# 读数去发现——那正是本闸门要避免的调试方式。
from ledger import STATE_REQUIRED_KEYS, STATE_SCHEMA_VERSION  # noqa: E402

MAINTENANCE_CAP_TODAY = 1.0      # 单位：llm_cost_estimate
EXPLORATION_CAP_TODAY = 0.6
EXPLORATION_SLOT_DAYS = 7        # 每周一次探索槽位
DIMENSION_STALE_DAYS = 21        # 超过即视为 frontier 陈旧
NEVER_PROBED_STALENESS = 90      # 从未探测过维度的陈旧度替身
COVERAGE_FLOOR_DAYS = 30         # 高实验成本维度的覆盖下限

# 结构性抖动只统计产品代码路径。不从 DIMENSION_WORKSET 取并集：那会把 infra_ci 的
# .github/ 与 tools/ 也算进来，而 CI 配置改动不构成"代码结构抖动"。
CHURN_CODE_PREFIXES = ("flutter_app/lib/", "flutter_app/test/")
# Agent 夜间管道自己写进 main 的产物。它们不构成"有人改了代码"，留着就是自指：
# 上一夜的输出 → 这一夜的输入，maintenance 通道会夜夜必开。
AGENT_OWNED_PREFIXES = ("docs/agent-audit/", "docs/agent-investigations/")
STRUCTURAL_CHURN_LINES = 800     # 未校准，见设计文档 §6-8

HYP_ID_RE = re.compile(r"^HYP-(\d{1,6})$")

# FRONTIER.md 的小节标记（活跃区读数依赖两者同时存在）
FRONTIER_ACTIVE_MARKER = "## 活跃队列"
FRONTIER_COOLING_MARKER = "## 冷却区"

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


def _last_audit_ref() -> tuple[str | None, date | None]:
    """最近一次 daily maintainer audit 的 (sha, 日期)——近似"上次审查时刻"。

    返回 sha 而不只是日期：判定要的是"那次审查之后进了什么"，用 rev-range 表达。
    """
    try:
        out = _run(["git", "log", "-1", "--format=%H%x09%cd", "--date=short",
                    "--grep=chore(agent): daily maintainer audit", "origin/main"])
    except GateError:
        return None, None
    out = out.strip()
    if not out:
        return None, None
    sha, _, committed = out.partition("\t")
    try:
        return sha, date.fromisoformat(committed.strip())
    except ValueError:
        raise GateError(f"无法解析 audit 日期: {out!r}")


def _is_agent_owned(path: str) -> bool:
    return path.startswith(AGENT_OWNED_PREFIXES)


def _collect_live_signals(run_date: date) -> dict:
    audit_sha, audit_at = _last_audit_ref()
    if audit_sha:
        # 必须是 <audit sha>..origin/main，不能是"日期窗口"：审查提交本身就落在那天，
        # 用日期取窗口会把"上一次审查自己写的文件"当成新变更 → maintenance 夜夜必开。
        # 影子期读数就此失去意义，而这是 P0-1b 激活判定的唯一数据来源。
        rev_range = f"{audit_sha}..origin/main"
        since_clause: list[str] = []
    else:
        # 首夜还没有 audit 提交：按窗口取最近一天，行为与建闸前一致
        since = (run_date - timedelta(days=1))
        rev_range = "origin/main"
        since_clause = [f"--since={since.isoformat()}"]
    raw = _run(["git", "log", *since_clause, "--name-only",
                "--format=COMMIT:%H", rev_range])
    commits: dict[str, list[str]] = {}
    self_referential = 0
    current = None
    for line in raw.splitlines():
        line = line.strip()
        if line.startswith("COMMIT:"):
            current = line[len("COMMIT:"):]
            commits.setdefault(current, [])
        elif line and current:
            commits[current].append(line)
    # 剔除 Agent 自己产出的路径：账本三件套 + audit 正文都是每晚确定性写入 main 的，
    # 留着它们，"有变更"就等于"上个夜晚管道跑过"，与有没有人写代码无关。
    filtered: dict[str, list[str]] = {}
    for sha, paths in commits.items():
        human = [p for p in paths if not _is_agent_owned(p)]
        if len(human) != len(paths):
            self_referential += 1
        if human:
            filtered[sha] = human
    commits = filtered

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
        # 读数可复核：剔除是自指防御，不是把证据藏起来——被剔的提交数要留在结果里
        "self_referential_commits_excluded": self_referential,
        "untriaged_issue_count": int(untriaged or 0),
        "failed_check_count": int(failed or 0),
        "frontier_entries": _frontier_open_entries(),
        "days_since_last_exploration": None,   # 无账本前由 --fixture 或人工提供
        "last_exploration_date": None,
        "dimension_state": {},
        "churn": churn,
        "budget": {},
    }


FRONTIER_TARGET_RE = re.compile(r"target:\s*([^\s（()]+)")
FRONTIER_ID_RE = re.compile(r"^### (FR-\d+)")


def _frontier_open_entries(path: Path = DEFAULT_FRONTIER) -> list[dict]:
    """活跃区 Entry → `[{id, target}]`。

    两个小节标记都必须存在：只按 `## 冷却区` 切分时，标题一旦被改名，cooling 与
    retired 条目会全数落进"活跃区"，让 frontier_change 静默虚高——一个会左右
    maintenance 触发器的解析，不该用 docstring 里的"注意"来宽容。

    target 是 `frontier_change` 与近期 diff 求交用的：契约要的是"这条未闭合证据链
    所指的文件又被改了"，不是"存在未闭合 Entry"（后者会让通道每晚必开）。
    """
    if not path.is_file():
        return []
    text = path.read_text(encoding="utf-8")
    for marker in (FRONTIER_ACTIVE_MARKER, FRONTIER_COOLING_MARKER):
        if marker not in text:
            raise GateError(f"FRONTIER.md 缺少小节标记 {marker!r}，无法判定活跃区")
    active = text.split(FRONTIER_ACTIVE_MARKER, 1)[1].split(FRONTIER_COOLING_MARKER, 1)[0]

    entries: list[dict] = []
    current: dict | None = None
    for line in active.splitlines():
        id_match = FRONTIER_ID_RE.match(line)
        if id_match:
            current = {"id": id_match.group(1), "target": None}
            entries.append(current)
            continue
        if current is not None and current["target"] is None:
            target_match = FRONTIER_TARGET_RE.search(line)
            if target_match:
                current["target"] = target_match.group(1).rstrip("/")
    return entries


def _target_touched(target: str | None, changed_paths: list[str]) -> bool:
    """Entry 的 target 与近期变更是否有交集：同文件，或同一目录下的兄弟文件。"""
    if not target:
        return False
    if target in changed_paths:
        return True
    target_dir = target.rsplit("/", 1)[0] + "/" if "/" in target else ""
    for path in changed_paths:
        if target_dir and path.startswith(target_dir):
            return True
        parent = path.rsplit("/", 1)[0] + "/" if "/" in path else ""
        if parent and target.startswith(parent):
            return True
    return False


# ---------------------------------------------------------------- 判定
def maintenance_channel(signals: dict) -> dict:
    reasons: list[str] = []
    commits = signals.get("commits_since_last_audit") or []
    changed_paths = sorted({p for c in commits for p in c.get("paths", [])})
    entries = signals.get("frontier_entries") or []

    if commits:
        reasons.append("changed_code")
    if int(signals.get("untriaged_issue_count") or 0) > 0:
        reasons.append("untriaged_issue")
    if int(signals.get("failed_check_count") or 0) > 0:
        reasons.append("test_failure")
    # 契约语义：open candidate 的 target 路径出现在近期 diff 里，才算 frontier 变化。
    # 只数 Entry 条数会让一条长期 blocked 的 FR 把 maintenance 通道夜夜打开。
    if any(_target_touched(e.get("target"), changed_paths) for e in entries):
        reasons.append("frontier_change")

    return {
        "work_present": bool(reasons),
        "reasons": sorted(reasons),
        "signals": {
            "commits_since_last_audit": len(commits),
            "changed_paths": changed_paths[:40],
            "untriaged_issue_count": int(signals.get("untriaged_issue_count") or 0),
            "failed_check_count": int(signals.get("failed_check_count") or 0),
            "open_candidate_count": len(entries),
        },
    }


def exploration_channel(signals: dict, run_date: date, dimension_ids: list[str],
                        stale_dimensions: list[str]) -> dict:
    reasons: list[str] = []
    gap = signals.get("days_since_last_exploration")
    last = signals.get("last_exploration_date")
    if gap is None and last:
        # 账本只提供日期不提供天数时自行推算。缺这一层，"有账本"反而比"没账本"更保守：
        # 下面的槽位分支两个条件都进不去，每周探索被静默关闭。
        gap = _days_since(last, run_date)
        if gap is None:
            raise GateError(f"last_exploration_date 无法解析：{last!r}")
    if gap is None and last is None:
        # 账本尚未建立时，探索通道按周槽位兜底运行（否则探索能力会被静默清零）
        if run_date.weekday() == 2:
            reasons.append("scheduled_slot")
    elif gap is not None and int(gap) >= EXPLORATION_SLOT_DAYS:
        reasons.append("scheduled_slot")

    state = signals.get("dimension_state", {}) or {}
    if stale_dimensions:
        # 两件事都要能说，不许互相遮蔽：只 append 一个原因时，"有维度从没探测过"
        # 会把"有维度探测过但过期了"盖掉——影子期就从读数里看不出该走哪条策略。
        if any(_never_probed(signals, d) for d in stale_dimensions):
            reasons.append("dimension_never_probed")
        if any(not _never_probed(signals, d) for d in stale_dimensions):
            reasons.append("frontier_stale")

    churn = signals.get("churn") or {}
    if sum(lines for path, lines in churn.items()
           if path.startswith(CHURN_CODE_PREFIXES)) > STRUCTURAL_CHURN_LINES:
        reasons.append("structural_churn")

    high_cost_covered = []
    for dim in dimension_ids:
        if DIMENSION_EVIDENCE_COST.get(dim, 1.0) < 3.0:
            continue
        d_state = state.get(dim, {}) or {}
        days = _days_since(d_state.get("last_probed"), run_date)
        if _never_probed(signals, dim) or (days is not None and days >= COVERAGE_FLOOR_DAYS):
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


def _is_stale(d_state: dict, run_date: date, never_probed: bool = False) -> bool:
    """陈旧 = 账本说从没查过，或有明确日期且已超期。缺数据不算陈旧。"""
    if never_probed or d_state.get("never_probed"):
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


def _normalize_candidate(raw: object) -> str:
    """账本候选 id → 契约形状 `HYP-NNN`。

    账本写的是完整 id（与 ledger-event.hypothesis_id 同形），不是能 `int()` 的序号。
    纯数字只是兼容旧 fixture。无法归一的形状原样返回，交给写前契约校验拒绝——
    闸门宁可响亮失败，也不在这里静默修形。
    """
    text = str(raw).strip()
    match = HYP_ID_RE.match(text)
    if match:
        return f"HYP-{int(match.group(1)):03d}"
    if text.isdigit():
        return f"HYP-{int(text):03d}"
    return text


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
        "candidates": sorted({_normalize_candidate(c) for c in
                              (state.get(best_dim, {}) or {}).get("candidate_ids", [])}),
        "score_components": best_components,
        "anti_inflation": {
            "severity_ceiling_by_tier": {"L0": "medium", "L1": "high", "L2": "critical"},
            "llm_scored_fields_capped": ["severity", "expected_value"],
        },
    }


def budget_block(signals: dict) -> dict:
    given = signals.get("budget") or {}
    # 账本还没记成本 → spent_today 永远是 0 → 上限永远不触发。这必须是机读事实，
    # 不能只写在注释里：否则影子期会把"闸门很宽容"读成"预算够用"。
    cost_observed = any((given.get(name) or {}).get("spent_today")
                        for name in ("maintenance", "exploration"))

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
            "exploration": bucket("exploration", EXPLORATION_CAP_TODAY),
            "enforced": cost_observed,
            "note": None if cost_observed else "cost_not_recorded：账本尚无成本行，日上限不生效"}


def _never_probed(signals: dict, dimension: str) -> bool:
    """探测记录由账本给（闸门行分配过的维度 + 有假设的维度）。

    没有这个字段就等于"不知道探测过没有"，此时不许推断成"从没探测过"——否则一空的
    fixture 会让 7 个维度全部陈旧、探索通道夜夜放行，把自指饱和换成另一种饱和。
    """
    probed = signals.get("probed_dimensions")
    if isinstance(probed, list):
        return dimension not in probed
    return bool((signals.get("dimension_state") or {}).get(dimension, {}).get("never_probed"))


def evaluate(signals: dict, run_date: date) -> dict:
    maintenance = maintenance_channel(signals)
    state = signals.get("dimension_state") or {}
    stale_dims = [d for d in DIMENSION_WORKSET
                  if _is_stale(state.get(d) or {}, run_date,
                               never_probed=_never_probed(signals, d))]
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
        # GITHUB_STEP_SUMMARY 是整个 job 共享的文件，后面的步骤用 >> 往里加。
        # 用写模式会把它们的内容抹掉——闸门是第 2 步，今天还没人排在它前面。
        with open(summary_path, "a", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")

    if github_output:
        with open(github_output, "a", encoding="utf-8") as fh:
            fh.write(f"eligible={str(result['eligible']).lower()}\n")
            fh.write(f"channel={channel}\n")
            fh.write(f"dimension={dim_id or ''}\n")
            fh.write(f"not_eligible_reason={result['not_eligible_reason'] or ''}\n")

    print("\n".join(lines))
    print(f"[OK] gate-result 写出 {out_path}（{size_kb:.1f}KB，契约校验通过）")
    return []


def merge_ledger_state(signals: dict, state_path: Path) -> dict:
    """把账本算出的真实陈旧度并进来（账本优先于缺省，不覆盖已有探针值）。

    没有这一步，调度器的 staleness 只能来自 fixture；有了它，P0-1 与 P0-2 才闭环：
    账本 → 陈旧度 → 领域分配 → 激活与否。

    契约是硬前置：`ledger.py state` 少给一个键、把 dict 给成字符串，都必须在这里响。
    曾经的做法是 `.get()` 到底，结果 schema 漂移安静地退化成"今晚没有陈旧维度"，
    影子期就把"闸门读不到账本"和"确实没有陈旧"记成了同一件事。
    """
    try:
        ledger_state = json.loads(Path(state_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise GateError(f"账本 state 不可读：{state_path}（{exc}）") from exc
    if not isinstance(ledger_state, dict):
        raise GateError(f"账本 state 必须是对象，实得 {type(ledger_state).__name__}")
    missing = [k for k in STATE_REQUIRED_KEYS if k not in ledger_state]
    if missing:
        raise GateError(f"账本 state 缺必填键 {missing}——ledger.py 与闸门已经漂移，"
                        "不许按缺省值继续判")
    version = ledger_state.get("schema_version")
    if version != STATE_SCHEMA_VERSION:
        raise GateError(f"账本 state schema_version={version!r}，闸门认 "
                        f"{STATE_SCHEMA_VERSION!r}")
    if not isinstance(ledger_state.get("dimension_state"), dict):
        raise GateError("账本 state 的 dimension_state 不是对象")
    for key in ("days_since_last_exploration", "last_exploration_date"):
        if signals.get(key) is None and ledger_state.get(key) is not None:
            signals[key] = ledger_state[key]
    # 陈旧度永远以账本为准（fixture/探针给的只是没有账本时的替身）
    signals["dimension_state"] = ledger_state["dimension_state"]
    signals["probed_dimensions"] = ledger_state["probed_dimensions"]
    signals["ledger_state_events"] = ledger_state["events_total"]
    return signals


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
    parser.add_argument("--state-file", type=Path,
                        help="ledger.py state 的输出：把真实陈旧度/候选队列并进来（账本→调度闭环）")
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
        if args.state_file:
            signals = merge_ledger_state(signals, Path(args.state_file))
        for pair in args.var:
            if "=" not in pair:
                raise GateError(f"--var 需要 KEY=VALUE：{pair}")
            key, _, value = pair.partition("=")
            try:
                signals[key] = json.loads(value)
            except json.JSONDecodeError:
                signals[key] = value
        # evaluate/emit 也在 try 内：判定阶段的 GateError（如无法解析的账本日期）
        # 必须走同一条响亮失败路径，不能变成裸 traceback。
        result, extras = evaluate(signals, run_date)
        problems = emit(result, extras, Path(args.output), Path(args.schema),
                        args.max_record_kb, args.summary, args.github_output)
    except GateError as exc:
        print(f"[FAIL] gate 判定失败：{exc}", file=sys.stderr)
        return 1
    except (json.JSONDecodeError, OSError, ValueError) as exc:
        print(f"[FAIL] gate 输入不可用：{exc}", file=sys.stderr)
        return 1

    if problems:
        for problem in problems:
            print(f"[FAIL] {problem}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
