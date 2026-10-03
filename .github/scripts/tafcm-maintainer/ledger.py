#!/usr/bin/env python3
"""Canonical Ledger：仓库 Agent 的唯一机器账本（P0-2）。

契约：`.github/schemas/ledger-event.schema.json`（NDJSON，一行一个事件，append-only）。

为什么账本与展示必须分开（#289 的结构答案）：
Dashboard issue / FINDINGS.md / FRONTIER.md / metrics 都是**只读投影**。以前展示层
就是状态层，改一次展示就可能毁一次账本（注册表自毁事故）。现在写入只经本模块，
投影只读本模块的输出。

强制的不变量（每条都有测试，不是文档承诺）：
1. **身份由脚本计算**：`event_id` / `hypothesis_id` / `fingerprint` 由脚本生成；
   上游给了不一致的值就拒写（沿用 ADR-0025 "模型不得输出 fingerprint" 的同一原则）。
2. **Finding 身份复用 fingerprint.py**：账本与注册表共用
   `SHA-256(category|files|norm_summary)[:16]`，绝不另起一套 identity。
3. **自证阻断**：`tier_promoted=L2` / `verdict.decision=verified` 只能由 verifier
   及以上角色写，且 `run_id` 必须不同于该 hypothesis 的 `created_by_run`。
4. **append-only**：只追加，永不重写；已有行损坏时**报错退出**，不"顺手修复"。
5. **单条 KB 硬顶**：超限拒写（账本自毁的另一半防线）。
6. **去重**：同 fingerprint 已有开放假设 → 记 `duplicate_of`，不新建 HYP 编号。

用法：
  ledger.py append --event <file> [--ledger <path>] [--dry-run]
  ledger.py import-audit --audit docs/agent-audit/<date>-maintainer-audit.md
  ledger.py import-findings [--registry docs/agent-audit/FINDINGS.md]
  ledger.py state --out <json>              # 供 eligibility_gate 当 --fixture 的真实信号
  ledger.py project --out-md <path> --out-metrics <path>
  ledger.py reconcile --registry <path>     # 账本与注册表不得漂移
纯标准库。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import date, datetime, timezone
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
REPO_ROOT = SCRIPTS.parents[2]
sys.path.insert(0, str(SCRIPTS))

from contract_minicheck import load_schema, validate  # noqa: E402

LEDGER_SCHEMA = REPO_ROOT / ".github" / "schemas" / "ledger-event.schema.json"
DEFAULT_LEDGER = REPO_ROOT / "docs" / "agent-audit" / "ledger.ndjson"
DEFAULT_REGISTRY = REPO_ROOT / "docs" / "agent-audit" / "FINDINGS.md"

MAX_RECORD_KB = 32.0
SELF_ISSUED_FIELDS = ("event_id", "hypothesis_id", "fingerprint")
# 允许写"已确认/已发布"的角色。scout / investigator 只能提交证据，不能签字。
PROMOTION_ACTORS = {"verifier", "publisher", "supervisor", "human", "importer"}
PROMOTION_TYPES = {"tier_promoted", "verdict_recorded", "published"}
# 闸门行没有 hypothesis_id：它们是"这次评估发生了什么"，不是某个假设的演进。
GATE_TYPES = {"gate_eligible", "gate_no_work", "gate_skipped_run"}
LIFECYCLE = ["candidate", "active", "deepening", "blocked", "verified", "cooling", "retired"]


class LedgerError(RuntimeError):
    """账本写入被拒——调用方（CI / workflow）必须让它响，不得吞掉。"""


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def finding_fingerprint(category: str, files: list[str], summary: str) -> str:
    """复用 fingerprint.py 的算法，保证账本与 FINDINGS.md 是同一套身份。"""
    import fingerprint as fp

    return fp.fingerprint(category or "", files or [], fp.normalize_summary(summary or ""))


def read_events(ledger_path: Path) -> list[dict]:
    if not ledger_path.is_file():
        return []
    events: list[dict] = []
    for lineno, line in enumerate(ledger_path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError as exc:
            # 损坏行绝不"跳过"或"重建"：账本坏掉必须是显式事故
            raise LedgerError(f"账本第 {lineno} 行损坏（{exc}）；拒绝在损坏账本上继续写入") from exc
    return events


def _event_id(payload: dict) -> str:
    raw = json.dumps(payload, sort_keys=True, ensure_ascii=False) + now_iso()
    return "EV-" + hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def _next_hypothesis_id(events: list[dict]) -> str:
    used = [int(e["hypothesis_id"].split("-")[1]) for e in events
            if e.get("hypothesis_id", "").startswith("HYP-")]
    return f"HYP-{max(used, default=0) + 1:03d}"


def _open_by_fingerprint(events: list[dict]) -> dict[str, str]:
    """fingerprint → 仍未闭合的 hypothesis_id。"""
    open_map: dict[str, str] = {}
    closed: set[str] = set()
    for event in events:
        hyp = event.get("hypothesis_id")
        fp_value = event.get("fingerprint")
        if not hyp or not fp_value:
            continue
        if event.get("type") in {"retired", "duplicate_of"} or \
                (event.get("hypothesis") or {}).get("lifecycle_stage") in {"retired", "verified"}:
            closed.add(fp_value)
        if fp_value not in closed:
            open_map[fp_value] = hyp
    return open_map


def _created_run(events: list[dict], hypothesis_id: str) -> str | None:
    for event in events:
        if event.get("hypothesis_id") == hypothesis_id and event.get("type") == "hypothesis_added":
            return (event.get("hypothesis") or {}).get("created_by_run") or event.get("run_id")
    return None


def prepare(event: dict, events: list[dict], schema: dict) -> dict:
    """补齐脚本生成的身份字段，然后跑全部不变量校验。"""
    out = dict(event)
    out.setdefault("schema_version", "1.0")
    out.setdefault("ts", now_iso())

    etype = out.get("type")
    if not etype:
        raise LedgerError("事件缺 type")

    # --- 不变量 1：身份字段由脚本拥有 ---
    supplied_fp = out.get("fingerprint")
    computed_fp = None
    hypothesis = out.get("hypothesis") or {}
    if etype in {"hypothesis_added", "hypothesis_updated"} and hypothesis:
        computed_fp = finding_fingerprint(
            hypothesis.get("category", hypothesis.get("dimension", "")),
            hypothesis.get("evidence_files", []),
            # 身份锚点用注册表同一套归一化 Summary；用 title 会让同一个 Finding
            # 在账本与 FINDINGS.md 里拿到两个 fingerprint（=第二个真相）。
            hypothesis.get("norm_summary", hypothesis.get("title", "")),
        )
    if computed_fp is not None:
        if out.get("actor") == "importer":
            # 历史导入沿用注册表已赋予的身份：重算会给同一个 Finding 造出第二个 id，
            # 而"同一个 finding 两套身份"正是本阶段要消灭的问题。例外只对
            # run_id 以 import- 开头的事件开放，且这类事件只由 import-findings 子命令
            # 从 FINDINGS.md 自行构造——写账本的永远是确定性步骤，不是 LLM。
            if not (supplied_fp and _is_hex16(supplied_fp)
                    and str(out.get("run_id", "")).startswith("import-")):
                raise LedgerError("importer 例外仅适用于 import-* 运行，"
                                  "且必须携带注册表里的 fingerprint")
            out["fingerprint"] = supplied_fp
        elif supplied_fp not in (None, computed_fp):
            raise LedgerError(f"上游给的 fingerprint={supplied_fp} 与脚本算出的 "
                              f"{computed_fp} 不一致——身份不接受申报")
        else:
            out["fingerprint"] = computed_fp
    elif supplied_fp is not None and etype not in {"verdict_recorded", "published"}:
        raise LedgerError(f"{etype} 不得自带 fingerprint")

    if etype == "hypothesis_added":
        existing = _open_by_fingerprint(events)
        if computed_fp and computed_fp in existing:
            out["duplicate_of"] = existing[computed_fp]
            out["hypothesis_id"] = existing[computed_fp]
        else:
            out["hypothesis_id"] = out.get("hypothesis_id") or _next_hypothesis_id(events)
            hypothesis.setdefault("created_by_run", out.get("run_id"))
            out["hypothesis"] = hypothesis
    elif not out.get("hypothesis_id") and etype not in GATE_TYPES:
        raise LedgerError(f"{etype} 缺 hypothesis_id")

    out["event_id"] = _event_id(out)

    # --- 不变量 3：自证阻断 ---
    actor = out.get("actor")
    if etype in PROMOTION_TYPES or (out.get("verdict") or {}).get("decision") == "verified":
        if actor not in PROMOTION_ACTORS:
            raise LedgerError(f"actor={actor} 无权写 {etype}（提假设者不得批准自己的假设）")
        created = _created_run(events, out.get("hypothesis_id", ""))
        if created and created == out.get("run_id"):
            raise LedgerError("same_run_confirmation：确认与提出在同一 run")

    # --- 不变量 5：KB 硬顶 ---
    probe = dict(out)
    probe.pop("record_kb", None)
    size_kb = len(json.dumps(probe, ensure_ascii=False).encode("utf-8")) / 1024.0
    out["record_kb"] = round(size_kb, 3)
    if size_kb > MAX_RECORD_KB:
        raise LedgerError(f"记录 {size_kb:.1f}KB 超上限 {MAX_RECORD_KB}KB")

    # --- 契约校验（写前）---
    errors = validate(out, schema, schema)
    if errors:
        raise LedgerError("契约不符：" + "; ".join(errors[:6]))

    return out


def append(ledger_path: Path, event: dict, dry_run: bool = False) -> dict:
    schema = load_schema(LEDGER_SCHEMA)
    events = read_events(ledger_path)
    prepared = prepare(event, events, schema)
    line = json.dumps(prepared, ensure_ascii=False, sort_keys=True)
    if dry_run:
        print(f"[DRY-RUN] 可写入：{prepared['type']} {prepared.get('hypothesis_id', '')}".strip())
        return prepared
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    with open(ledger_path, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")
    print(f"[OK] append {prepared['type']} "
          f"id={prepared.get('hypothesis_id', '-')} dup={prepared.get('duplicate_of') or '-'}")
    return prepared


def cmd_append(args: argparse.Namespace) -> int:
    event = json.loads(Path(args.event).read_text(encoding="utf-8"))
    try:
        append(Path(args.ledger), event, args.dry_run)
    except LedgerError as exc:
        print(f"[REJECT] {exc}", file=sys.stderr)
        return 1
    return 0


def cmd_import_audit(args: argparse.Namespace) -> int:
    """把每晚 audit 的 Finding 接进账本（散文 audit 继续存在，但状态从此进账本）。

    两条刻意的降级：
    - `evidence_tier` 一律 L1：散文审计没有实验、没有对照、没有确定性重跑，
      按 §3.2 的定义到不了 L2。
    - `severity` 超 L1 天花板（critical/high）强制降到 medium，并在
      `severity_declared` 里留下原值——降级必须可见，否则就成了悄悄改数据。
    - `invariant_source.kind = self_authored`：审计结论的预期出自 Agent 自己，
      这正是它封顶 L1 的原因，如实记录而不是假装它有出处。
    """
    import fingerprint as fp

    audit_path = Path(args.audit)
    text = audit_path.read_text(encoding="utf-8")
    findings = fp.extract_findings(text)
    if not findings:
        print(f"[OK] import-audit：{audit_path.name} 无 Finding（No significant findings）")
        return 0

    ledger_path = Path(args.ledger)
    events = read_events(ledger_path)
    before = len(events)
    schema = load_schema(LEDGER_SCHEMA)
    audit_date = audit_path.stem[:10]

    for finding in findings:
        block = _finding_block(text, finding["id"])
        declared_p = (fp._field(block, "Severity") or "P3").strip()
        declared = P_SEVERITY.get(declared_p, "low")
        # §3.2：散文审计没有实验/对照/确定性重跑 → 封顶 L1，
        # 而 L1 不得携带 critical/high。降级必须留痕，否则就是悄悄改数据。
        capped = declared if declared in ("low", "medium") else "medium"
        summary = (fp._field(block, "Summary") or finding["norm_summary"])[:500]
        event = {
            "type": "hypothesis_added",
            "actor": "scout",
            "run_id": f"audit-{audit_date}",
            "budget_bucket": "maintenance",
            "hypothesis": {
                "dimension": _category_to_dimension(finding.get("category", "")),
                "area": ",".join(finding.get("evidence_files", [])) or "unknown",
                "title": finding.get("id", f"{audit_date}-?"),
                "statement": summary,
                "invariant": "n/a（散文审计未声明被测不变量）",
                "invariant_source": {"kind": "self_authored"},
                "falsifier": "n/a（散文审计未设计否证实验）",
                "evidence_tier": "L1",
                "severity": capped,
                "severity_declared": declared_p,
                "category": finding.get("category", "unknown"),
                "norm_summary": finding["norm_summary"],
                "evidence_files": finding.get("evidence_files", []),
                "lifecycle_stage": "candidate",
                "last_observed": audit_date,
                "related_issue": finding.get("issue") or None,
                "created_by_run": f"audit-{audit_date}",
            },
        }
        events.append(prepare(event, events, schema))

    imported = len(events) - before
    if args.dry_run:
        print(f"[DRY-RUN] import-audit：可导入 {imported} 条 Finding")
        return 0
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    with open(ledger_path, "a", encoding="utf-8") as fh:
        for event in events[before:]:
            fh.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")
    downgraded = sum(1 for e in events[before:]
                     if (e.get("hypothesis") or {}).get("severity") == "medium"
                     and (e.get("hypothesis") or {}).get("severity_declared") in P_HIGH_SEVERITY)
    print(f"[OK] import-audit：导入 {imported} 条（其中 {downgraded} 条 P1/P0 触到 "
          f"L1 天花板被降为 medium）")
    return 0


P_SEVERITY = {"P0": "critical", "P1": "high", "P2": "medium", "P3": "low"}
P_HIGH_SEVERITY = {"P0", "P1"}


def _finding_block(text: str, finding_id: str) -> str:
    import re

    match = re.search(rf"(?ms)^### {re.escape(finding_id)}\b(.*?)(?=^### |\Z)", text)
    return match.group(1) if match else ""


def cmd_append_gate(args: argparse.Namespace) -> int:
    """把 gate-result.json 折成一行账本事件——每次 run 都留痕。

    没有 `gate_eligible` 行就没有分母，`gate_skip_rate` 与
    `llm_cost_per_activation` 都无法计算；这正是"给空转标上价格"的起点。
    """
    gate_path = Path(args.gate_result)
    if not gate_path.is_file():
        # 影子阶段闸门可能自己失败。这里必须留一行，而不是安静跳过——
        # "没记录"和"记录了失败"的差别就是账本能不能回答昨晚发生了什么。
        if not args.missing_reason:
            raise LedgerError(f"gate-result 缺失：{gate_path}")
        event = {
            "type": "gate_skipped_run",
            "actor": "scheduler",
            "run_id": args.run_id,
            "budget_bucket": "meta",
            "gate": {"channel": "none", "reasons": [args.missing_reason], "dimension": None},
        }
        append(Path(args.ledger), event, args.dry_run)
        return 0

    gate = json.loads(gate_path.read_text(encoding="utf-8"))
    reason = gate.get("not_eligible_reason")
    if (gate.get("maintenance") or {}).get("work_present"):
        channel = "maintenance"
    elif (gate.get("exploration") or {}).get("due"):
        channel = "exploration"
    else:
        channel = "none"

    if gate.get("eligible"):
        etype, bucket = "gate_eligible", channel
    elif reason and reason.endswith("budget_exhausted"):
        etype = "gate_skipped_run"
        bucket = ("maintenance" if reason == "maintenance_budget_exhausted"
                  else "exploration" if reason == "exploration_budget_exhausted" else "meta")
    else:
        etype, bucket = "gate_no_work", "meta"

    reasons = list((gate.get("maintenance") or {}).get("reasons", [])
                   + (gate.get("exploration") or {}).get("reasons", []))
    if not gate.get("eligible"):
        reasons = sorted(set(reasons + [reason or "no_work"]))

    event = {
        "type": etype,
        "actor": "scheduler",
        "run_id": args.run_id,
        "budget_bucket": bucket if bucket in ("maintenance", "exploration") else "meta",
        "gate": {
            "channel": channel if channel in ("maintenance", "exploration") else "none",
            "reasons": reasons,
            "dimension": (gate.get("dimension") or {}).get("assigned"),
        },
    }
    if args.duration_s or args.llm_cost is not None:
        event["cost"] = {"duration_s": (float(args.duration_s)
                                         if args.duration_s else None),
                         "llm_cost_estimate": args.llm_cost}
    append(Path(args.ledger), event, args.dry_run)
    return 0


def cmd_import_findings(args: argparse.Namespace) -> int:
    """把历史注册表导入账本，使账本成为完整历史而不是第二个孤岛。"""
    registry_path = Path(args.registry)
    ledger_path = Path(args.ledger)
    rows = _registry_rows(registry_path)
    events = read_events(ledger_path)
    already = {e.get("fingerprint") for e in events}
    imported, schema = 0, load_schema(LEDGER_SCHEMA)
    before = len(events)
    for row in rows:
        if row["fingerprint"] in already:
            continue
        event = {
            "type": "hypothesis_added",
            "actor": "importer",
            "fingerprint": row["fingerprint"],
            "run_id": f"import-{args.date}",
            "budget_bucket": "meta",
            "hypothesis": {
                "dimension": _category_to_dimension(row["category"]),
                "area": ",".join(row["files"]) or row["category"],
                "title": row["latest_id"],
                "statement": f"历史 Finding {row['latest_id']}（由 FINDINGS.md 注册表导入）",
                "invariant": "n/a（导入记录，无本次实验）",
                "invariant_source": {"kind": "shipped_behavior"},
                "falsifier": "n/a（导入记录）",
                "evidence_tier": "L1",
                # 注册表里没有 severity 字段，导入行统一记 medium：不得为了填满字段而
                # 给历史 Finding 造一个当年没人评过的等级（provenance 要诚实）。
                "severity": "medium",
                "category": row["category"],
                "evidence_files": row["files"],
                "lifecycle_stage": "retired" if row["status"] == "RESOLVED" else "active",
                "last_observed": row["last_seen"] or args.date,
                "created_by_run": f"import-{args.date}",
            },
        }
        events.append(prepare(event, events, schema))
        imported += 1
    if args.dry_run:
        print(f"[DRY-RUN] 可导入 {imported} 条（注册表共 {len(rows)} 行）")
        return 0
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    with open(ledger_path, "a", encoding="utf-8") as fh:
        for event in events[before:]:
            fh.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")
    print(f"[OK] import-findings：新增 {imported} 条 / 注册表 {len(rows)} 行")
    return 0


def _registry_rows(registry_path: Path) -> list[dict]:
    rows = []
    if not registry_path.is_file():
        return rows
    for line in registry_path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("| "):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 8 or not _is_hex16(cells[0]):
            continue
        rows.append({
            "fingerprint": cells[0], "latest_id": cells[1], "category": cells[2],
            "files": [f for f in cells[3].split(",") if f and f != "-"],
            "status": cells[4], "issue": cells[5], "first_seen": cells[6], "last_seen": cells[7],
        })
    return rows


def _is_hex16(value: str) -> bool:
    return len(value) == 16 and all(c in "0123456789abcdef" for c in value)


CATEGORY_TO_DIMENSION = {
    "bug": "correctness_test_gap", "regression": "correctness_test_gap",
    "performance": "performance", "architecture": "architecture_data_flow",
    "export": "export", "test-gap": "correctness_test_gap", "doc": "infra_ci",
}


def _category_to_dimension(category: str) -> str:
    return CATEGORY_TO_DIMENSION.get(category, "infra_ci")


def latest_state(events: list[dict]) -> dict[str, dict]:
    """hypothesis_id → 最新字段（投影与 gate 信号都用它）。"""
    state: dict[str, dict] = {}
    for event in events:
        hyp = event.get("hypothesis_id")
        if not hyp:
            continue
        entry = state.setdefault(hyp, {"events": 0})
        entry["events"] += 1
        entry.setdefault("created_ts", event.get("ts"))
        entry["updated_ts"] = event.get("ts")
        entry["last_actor"] = event.get("actor")
        if event.get("fingerprint"):
            entry["fingerprint"] = event["fingerprint"]
        if event.get("type") in LIFECYCLE or event.get("hypothesis", {}).get("lifecycle_stage"):
            entry["lifecycle"] = (event.get("hypothesis") or {}).get("lifecycle_stage",
                                                                     event["type"])
        payload = event.get("hypothesis") or {}
        if payload:
            entry["dimension"] = payload.get("dimension", entry.get("dimension"))
            entry["tier"] = payload.get("evidence_tier", entry.get("tier"))
            entry["severity"] = payload.get("severity", entry.get("severity"))
            entry["created_by_run"] = payload.get("created_by_run",
                                                  entry.get("created_by_run"))
            observed = payload.get("last_observed")
            if observed and observed > (entry.get("last_observed") or ""):
                entry["last_observed"] = observed
        if event.get("verdict"):
            entry["verdict"] = event["verdict"].get("decision")
            entry["verdict_run"] = event.get("run_id")
        if (event.get("issue") or {}).get("number"):
            entry["issue"] = event["issue"]["number"]
    return state


def cmd_state(args: argparse.Namespace) -> int:
    """产出 eligibility_gate 需要的真实信号：陈旧度 / 探索节律 / 候选队列。

    这是 §3.9 "已知未接"的补齐：调度器的陈旧度从此来自账本，而不是 fixture。
    """
    run_date = date.fromisoformat(args.date)
    events = read_events(Path(args.ledger))
    state = latest_state(events)

    dimension_state: dict[str, dict] = {}
    for entry in state.values():
        dim = entry.get("dimension")
        if not dim:
            continue
        # 用观察日期算陈旧度；事件 ts 是写入时间，回填历史时会把节律清零
        last_seen = entry.get("last_observed") or (entry.get("updated_ts") or "")[:10]
        bucket = dimension_state.setdefault(dim, {
            "last_probed": last_seen, "open_candidates": 0, "candidate_ids": [],
            "open_severity": "low", "never_probed": False,
        })
        if last_seen > (bucket["last_probed"] or ""):
            bucket["last_probed"] = last_seen
        if entry.get("lifecycle") not in {"retired", "verified"}:
            bucket["open_candidates"] += 1
            hyp = next((k for k, v in state.items() if v is entry), None)
            if hyp:
                bucket["candidate_ids"].append(int(hyp.split("-")[1]))
            if _SEVERITY_RANK.get(entry.get("severity", "low"), 0) > \
                    _SEVERITY_RANK.get(bucket["open_severity"], 0):
                bucket["open_severity"] = entry.get("severity", "low")

    exploration_events = [e for e in events if e.get("budget_bucket") == "exploration"]
    last_exploration = max((e.get("ts", "")[:10] for e in exploration_events), default=None)
    payload = {
        "date": run_date.isoformat(),
        "dimension_state": dimension_state,
        "days_since_last_exploration": ((run_date - date.fromisoformat(last_exploration)).days
                                         if last_exploration else None),
        "last_exploration_date": last_exploration,
        "commits_since_last_audit": [],
        "untriaged_issue_count": 0,
        "failed_check_count": 0,
        "frontier_open_candidates": sum(1 for v in state.values()
                                        if v.get("lifecycle") not in {"retired", "verified"}),
        "churn": {},
        "budget": {},
    }
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text(json.dumps(payload, ensure_ascii=False, indent=2),
                              encoding="utf-8")
    print(f"[OK] state 写出 {args.out}（{len(state)} 个假设，"
          f"{len(dimension_state)} 个维度有历史）")
    return 0


_SEVERITY_RANK = {"low": 0, "medium": 1, "high": 2, "critical": 3}


def cmd_project(args: argparse.Namespace) -> int:
    """从账本重生成只读投影。投影不许手写，只许被生成。"""
    events = read_events(Path(args.ledger))
    state = latest_state(events)

    lines = [
        "# Agent Ledger 投影（自动生成，请勿手改）",
        "",
        f"> 由 `ledger.py project` 生成于 {now_iso()}；唯一真相是 `ledger.ndjson`。",
        f"> 事件 {len(events)} 条 / 假设 {len(state)} 个。",
        "",
        "| hypothesis | dimension | tier | lifecycle | severity | verdict | issue | updated |",
        "|------------|-----------|------|-----------|----------|---------|-------|---------|",
    ]
    for hyp in sorted(state):
        entry = state[hyp]
        lines.append("| {} | {} | {} | {} | {} | {} | {} | {} |".format(
            hyp, entry.get("dimension", "-"), entry.get("tier", "-"),
            entry.get("lifecycle", "-"), entry.get("severity", "-"),
            entry.get("verdict", "-"), entry.get("issue", "-"),
            (entry.get("updated_ts") or "-")[:10]))

    Path(args.out_md).write_text("\n".join(lines) + "\n", encoding="utf-8")

    gate_rows = [e for e in events if e.get("type") in GATE_TYPES]
    evaluations = len(gate_rows)
    skipped = sum(1 for e in gate_rows if e["type"] in {"gate_no_work", "gate_skipped_run"})
    activations = [e for e in events if e.get("type") == "hypothesis_added"
                   and e.get("actor") != "importer"]
    metrics = {
        "events_total": len(events),
        "gate_evaluations": evaluations,
        "gate_no_work": sum(1 for e in gate_rows if e["type"] == "gate_no_work"),
        "gate_skipped_run": sum(1 for e in gate_rows if e["type"] == "gate_skipped_run"),
        "gate_eligible": sum(1 for e in gate_rows if e["type"] == "gate_eligible"),
        "llm_activations": len(activations),
        # 分母是"闸门评估次数"，不是日历天数：这样才不会被节假日与手动触发扭曲
        "gate_skip_rate": round(skipped / evaluations, 4) if evaluations else None,
        "by_bucket": _count_by(events, "budget_bucket"),
        "by_tier": {t: sum(1 for v in state.values() if v.get("tier") == t)
                    for t in ("L0", "L1", "L2")},
        "published_issues": sum(1 for v in state.values() if v.get("issue")),
        "verified": sum(1 for v in state.values() if v.get("verdict") == "verified"),
        "cost_estimate": {
            "llm_cost_estimate": round(sum((e.get("cost") or {}).get("llm_cost_estimate") or 0.0
                                            for e in events), 4),
        },
    }
    Path(args.out_metrics).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out_metrics).write_text(json.dumps(metrics, ensure_ascii=False, indent=2),
                                      encoding="utf-8")
    print(f"[OK] project 写出 {args.out_md} + {args.out_metrics}")
    return 0


def _count_by(events, key: str) -> dict:
    counts: dict[str, int] = {}
    for event in events:
        value = event.get(key)
        if value is not None:
            counts[str(value)] = counts.get(str(value), 0) + 1
    return counts


def cmd_reconcile(args: argparse.Namespace) -> int:
    """账本与 FINDINGS.md 注册表不得漂移（两套状态并存期间的过渡守门）。"""
    ledger_fps = {e.get("fingerprint") for e in read_events(Path(args.ledger))
                  if e.get("fingerprint")}
    registry = _registry_rows(Path(args.registry))
    missing = [r["fingerprint"] for r in registry if r["fingerprint"] not in ledger_fps]
    if missing:
        print(f"[FAIL] 注册表有 {len(missing)} 条身份不在账本里："
              f"{', '.join(missing[:5])} …（跑 import-findings 补齐）", file=sys.stderr)
        return 1
    print(f"[OK] reconcile：注册表 {len(registry)} 行全部存在于账本（{len(ledger_fps)} 个身份）")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ledger", default=str(DEFAULT_LEDGER))
    sub = parser.add_subparsers(dest="command", required=True)

    p_append = sub.add_parser("append")
    p_append.add_argument("--event", required=True)
    p_append.add_argument("--dry-run", action="store_true")
    p_append.set_defaults(func=cmd_append)

    p_gate = sub.add_parser("append-gate")
    p_gate.add_argument("--gate-result", required=True)
    p_gate.add_argument("--run-id", required=True)
    p_gate.add_argument("--duration-s")
    p_gate.add_argument("--llm-cost", type=float)
    p_gate.add_argument("--missing-reason",
                        help="gate-result 缺失时写这行的原因（影子阶段闸门自身可能失败）")
    p_gate.add_argument("--dry-run", action="store_true")
    p_gate.set_defaults(func=cmd_append_gate)

    p_audit = sub.add_parser("import-audit")
    p_audit.add_argument("--audit", required=True)
    p_audit.add_argument("--dry-run", action="store_true")
    p_audit.set_defaults(func=cmd_import_audit)

    p_import = sub.add_parser("import-findings")
    p_import.add_argument("--registry", default=str(DEFAULT_REGISTRY))
    p_import.add_argument("--date", default=date.today().isoformat())
    p_import.add_argument("--dry-run", action="store_true")
    p_import.set_defaults(func=cmd_import_findings)

    p_state = sub.add_parser("state")
    p_state.add_argument("--out", required=True)
    p_state.add_argument("--date", default=date.today().isoformat())
    p_state.set_defaults(func=cmd_state)

    p_project = sub.add_parser("project")
    p_project.add_argument("--out-md", required=True)
    p_project.add_argument("--out-metrics", required=True)
    p_project.set_defaults(func=cmd_project)

    p_recon = sub.add_parser("reconcile")
    p_recon.add_argument("--registry", default=str(DEFAULT_REGISTRY))
    p_recon.set_defaults(func=cmd_reconcile)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except LedgerError as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 1
    except (OSError, json.JSONDecodeError) as exc:
        print(f"[FAIL] 账本输入不可用：{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
