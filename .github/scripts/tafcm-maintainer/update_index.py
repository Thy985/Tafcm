#!/usr/bin/env python3
"""update_index.py — 更新 docs/agent-audit/INDEX.md（每日追加一行）

从当日 Audit 解析统计并追加到 INDEX.md 表格：
  | Date | Findings | Issues | Ecosystem | Open Actions |
  - Findings: F-ID 块数量
  - Issues: 当日创建的 Issue 数（扫描 Findings 块 Issue 字段中的数字）
  - Ecosystem: E-ID 块数量
  - Open Actions: Recommended Actions 编号项数量（1. 2. 3. ...）

若当日行已存在（重复运行）则不重复追加。
依赖：仅 Python 标准库。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})-maintainer-audit\.md$")
MARKER = "<!-- INDEX_ROWS -->"


def parse_audit(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")

    findings = len(re.findall(r"(?m)^### F-\d{4}-\d{2}-\d{2}-\d{2}$", text))
    # Issue 字段：`Issue: 123` 或 `Issue: #123`
    issues = len(re.findall(r"(?m)^Issue:\s*#?(\d+)\s*$", text))

    ecosystems = len(re.findall(r"(?m)^### E-\d{4}-\d{2}-\d{2}-\d{2}$", text))

    # Recommended Actions 编号项（1. 2. 3.）
    actions_section = text.split("## Recommended Actions")[-1]
    open_actions = len(re.findall(r"(?m)^\d+\.\s+", actions_section))

    date = path.stem[:10]
    return {"date": date, "findings": findings, "issues": issues,
            "ecosystem": ecosystems, "open_actions": open_actions}


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

    line = (f"| {row['date']} | {row['findings']} | {row['issues']} "
            f"| {row['ecosystem']} | {row['open_actions']} |")
    updated = text.replace(marker_line, f"{line}\n{marker_line}", 1)
    index_path.write_text(updated, encoding="utf-8")
    print(f"✅ INDEX 已追加: {line}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
