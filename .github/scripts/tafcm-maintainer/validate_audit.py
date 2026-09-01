#!/usr/bin/env python3
"""validate_audit.py — Tafcm Maintainer Audit 格式校验（workflow 强制门禁）

按 .agent/tafcm-maintainer/SCHEMA.md §2 校验
docs/agent-audit/YYYY-MM-DD-maintainer-audit.md：
  - 文件名匹配 YYYY-MM-DD-maintainer-audit.md（本地日期 UTC+8，与 main #220 约定一致）
  - 必需小节齐全（Repository State / Findings / Issue Investigations /
    Ecosystem Watch / Architecture / Test Gaps / Recommended Actions）
  - Finding 段枚举值合法（Category / Severity / Confidence / Status）
  - 无 Finding 时出现 "No significant findings."

失败 exit 1 → workflow FAILED（Audit 生成失败不得伪装成成功）。
依赖：仅 Python 标准库。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REQUIRED_SECTIONS = [
    "## Repository State",
    "## Findings",
    "## Issue Investigations",
    "## Ecosystem Watch",
    "## Architecture",
    "## Test Gaps",
    "## Recommended Actions",
]

VALID_CATEGORY = {"bug", "regression", "test-gap", "architecture", "ecosystem", "tech-debt"}
VALID_SEVERITY = {"P0", "P1", "P2", "P3"}
VALID_CONFIDENCE = {"High", "Medium", "Low"}
VALID_STATUS = {"new", "open", "resolved", "won't-fix", "duplicate"}
VALID_RC = {"Confirmed", "Likely", "Hypothesis", "Unknown"}

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-maintainer-audit\.md$")
FINDING_ID_RE = re.compile(r"^F-\d{4}-\d{2}-\d{2}-\d{2}$")


def check_finding_field(block: str, field: str, valid: set[str], errors: list[str]) -> None:
    """检查 block 中的 `Field: value` 行，value 必须 ∈ valid。"""
    m = re.search(rf"^{re.escape(field)}:\s*(.+)$", block, re.MULTILINE)
    if not m:
        errors.append(f"Finding 缺 {field} 字段")
        return
    value = m.group(1).strip()
    if value not in valid:
        errors.append(f"Finding {field} 值非法: {value!r}（合法: {sorted(valid)}）")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_audit.py <audit.md>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not DATE_RE.match(path.name):
        print(f"FAIL: 文件名不合法（需 YYYY-MM-DD-maintainer-audit.md）: {path.name}", file=sys.stderr)
        return 1
    if not path.is_file():
        print(f"FAIL: Audit 文件不存在: {path}", file=sys.stderr)
        return 1

    text = path.read_text(encoding="utf-8")
    errors: list[str] = []

    # 1. 必需小节
    for sec in REQUIRED_SECTIONS:
        if sec not in text:
            errors.append(f"缺少必需小节: {sec}")

    # 2. Findings 段
    findings_block = text.split("## Issue Investigations")[0]  # Findings 至下一节
    # 行级精确匹配：只有独立行 `No significant findings.` 才视为"无 Finding"声明；
    # 避免子串匹配误判（如某 Finding 的 Evidence 内容恰好包含该文本）。
    if re.search(r"(?m)^No significant findings\.?$", findings_block):
        # 无 Finding：允许，跳过枚举校验
        pass
    else:
        # 按 "### F-YYYY-MM-DD-NN" 切块（标题允许 ID 后带描述，如
        # "### F-2026-09-01-01（续 F1 昨日）— 标题"）
        blocks = re.split(r"(?m)^### F-\d{4}-\d{2}-\d{2}-\d{2}", findings_block)
        if len(blocks) < 2:
            errors.append("Findings 段既无 'No significant findings.' 也无 F-ID 块")
        for i, block in enumerate(blocks[1:], start=1):
            if not block.strip():
                errors.append(f"Findings 块 #{i} 为空")
                continue
            check_finding_field(block, "Category", VALID_CATEGORY, errors)
            check_finding_field(block, "Severity", VALID_SEVERITY, errors)
            check_finding_field(block, "Confidence", VALID_CONFIDENCE, errors)
            check_finding_field(block, "Status", VALID_STATUS, errors)
            for required in ("Problem", "Evidence", "Impact", "Recommendation"):
                if not re.search(rf"^{re.escape(required)}:", block, re.MULTILINE):
                    errors.append(f"Finding #{i} 缺 {required} 字段")

    # 3. Root Cause 值（Issue Investigations 段）
    inv_block = text.split("## Ecosystem Watch")[0]
    for m in re.finditer(r"^Root Cause:\s*(.+)$", inv_block, re.MULTILINE):
        if m.group(1).strip() not in VALID_RC:
            errors.append(f"Root Cause 值非法: {m.group(1).strip()!r}")

    if errors:
        print("=== Audit 校验失败 ===", file=sys.stderr)
        for e in errors:
            print(f"  ✗ {e}", file=sys.stderr)
        return 1
    print(f"✅ Audit 格式校验通过: {path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
