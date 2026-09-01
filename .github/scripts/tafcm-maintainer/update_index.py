#!/usr/bin/env python3
"""update_index.py — 更新 docs/agent-audit/INDEX.md（每日追加一行）

从当日 Audit（五块事实账本）解析统计并追加到 INDEX.md 表格：
  | Date | New | Updated | Resolved | Issues | Ecosystem | Pending |
  - New:      状态 = NEW 的 Finding 数
  - Updated:  状态 = UPDATED 的 Finding 数
  - Resolved: 状态 = RESOLVED / REJECTED 的 Finding 数
  - Issues:   当日创建的 Agent Issue 数（扫描 Findings 块 Related Issue 字段）
  - Ecosystem: E-ID 块数量
  - Pending:  Pending Decisions 段 checkbox 条数

若当日行已存在（重复运行）则不重复追加。
依赖：仅 Python 标准库。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})-maintainer-audit\.md$")
MARKER = "<!-- INDEX_ROWS -->"

NEXT_AFTER_FINDINGS = ["## Existing Issue Updates", "## Ecosystem Findings",
                       "## Pending Decisions"]


def section_text(text: str, header: str, next_headers: list[str]) -> str:
    """取 [header, next_header) 区间文本（含 header 行）。"""
    start = text.find(header)
    if start == -1:
        return ""
    seg = text[start:]
    for nh in next_headers:
        idx = seg.find(nh)
        if idx != -1:
            return seg[:idx]
    return seg


def _field(block: str, name: str) -> str:
    m = re.search(rf"^{re.escape(name)}:\s*(.+)$", block, re.MULTILINE)
    return m.group(1).strip() if m else ""


def parse_audit(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")

    # ---- New Findings 状态计数 ----
    f_block = section_text(text, "## New Findings", NEXT_AFTER_FINDINGS)
    findings_status: dict[str, int] = {"NEW": 0, "UPDATED": 0, "RESOLVED": 0}
    for m in re.finditer(r"(?ms)^### F-\d{4}-\d{2}-\d{2}-\d{2}\b(.*?)(?=^### |\Z)", f_block):
        st = _field(m.group(1), "Status")
        if st == "NEW":
            findings_status["NEW"] += 1
        elif st == "UPDATED":
            findings_status["UPDATED"] += 1
        elif st in ("RESOLVED", "REJECTED"):
            findings_status["RESOLVED"] += 1

    # Issues：Findings 块 Related Issue 字段（`Related Issue: #123` 或 `Related Issue: 123`）
    issues = len(re.findall(r"(?m)^Related Issue:\s*#?(\d+)\s*$", f_block))

    # Ecosystem：E-ID 块数量
    eco_block = section_text(text, "## Ecosystem Findings", ["## Pending Decisions"])
    ecosystems = len(re.findall(r"(?m)^### E-\d{4}-\d{2}-\d{2}-\d{2}", eco_block))

    # Pending Decisions：checkbox 条数
    pend_block = section_text(text, "## Pending Decisions", [])
    pending = len(re.findall(r"(?m)^- \[ \]\s*", pend_block))

    date = path.stem[:10]
    return {"date": date,
            "new": findings_status["NEW"],
            "updated": findings_status["UPDATED"],
            "resolved": findings_status["RESOLVED"],
            "issues": issues,
            "ecosystem": ecosystems,
            "pending": pending}


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: update_index.py <audit.md> <index.md>", file=sys.stderr)
        return 2
    audit_path = Path(sys.argv[1])
    index_path = Path(sys.argv[2])
    if not DATE_RE.match(audit_path.name):
        print(f"FAIL: Audit 文件名不合法（需 YYYY-MM-DD-maintainer-audit.md）: {audit_path.name}",
              file=sys.stderr)
        return 1
    if not audit_path.is_file():
        print(f"FAIL: Audit 文件不存在: {audit_path}", file=sys.stderr)
        return 1
    if not index_path.is_file():
        print(f"FAIL: INDEX 文件不存在: {index_path}", file=sys.stderr)
        return 1

    row = parse_audit(audit_path)
    text = index_path.read_text(encoding="utf-8")

    # 去重：当日行已存在则不追加
    date_line = row["date"]
    if re.search(rf"(?m)^\| {re.escape(date_line)} \|", text):
        print(f"ℹ️ 当日行已存在，跳过: {date_line}")
        return 0
    if MARKER not in text:
        # 兼容带描述文本的标记行（如 "<!-- INDEX_ROWS: ... -->"）
        alt = re.search(r"(?m)^<!-- INDEX_ROWS[^\n]*-->$", text)
        if not alt:
            print(f"FAIL: INDEX.md 缺少标记行 {MARKER}", file=sys.stderr)
            return 1
        marker_line = alt.group(0)
    else:
        marker_line = MARKER

    line = (f"| {row['date']} | {row['new']} | {row['updated']} | {row['resolved']} "
            f"| {row['issues']} | {row['ecosystem']} | {row['pending']} |")
    updated = text.replace(marker_line, f"{line}\n{marker_line}", 1)
    index_path.write_text(updated, encoding="utf-8")
    print(f"✅ INDEX 已追加: {line}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
