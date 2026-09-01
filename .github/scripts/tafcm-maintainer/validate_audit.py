#!/usr/bin/env python3
"""validate_audit.py — Tafcm Maintainer Audit 格式校验（workflow 强制门禁）

按 .agent/tafcm-maintainer/SCHEMA.md §2 校验
docs/agent-audit/YYYY-MM-DD-maintainer-audit.md：
  - 文件名匹配 YYYY-MM-DD-maintainer-audit.md（本地日期 UTC+8，与 main #220 约定一致）
  - 必需五块小节齐全（Repository Health / New Findings / Existing Issue Updates /
    Ecosystem Findings / Pending Decisions）
  - Finding 段枚举值合法（Category / Severity / Confidence / Status-状态机）
  - Existing Issue Updates 段状态 / Root Cause 合法
  - Ecosystem Findings 段 Recommendation / Decision 合法
  - Pending Decisions 段为 checkbox 列表
  - 无 Finding 时出现 "No significant findings."

失败 exit 1 → workflow FAILED（Audit 生成失败不得伪装成成功）。
依赖：仅 Python 标准库。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REQUIRED_SECTIONS = [
    "## Repository Health",
    "## New Findings",
    "## Existing Issue Updates",
    "## Ecosystem Findings",
    "## Pending Decisions",
]

VALID_CATEGORY = {"bug", "regression", "test-gap", "architecture", "ecosystem", "tech-debt"}
VALID_SEVERITY = {"P0", "P1", "P2", "P3"}
VALID_CONFIDENCE = {"High", "Medium", "Low"}
VALID_STATUS = {"NEW", "UNCHANGED", "UPDATED", "RESOLVED", "REJECTED", "DUPLICATE", "WAITING_FOR_HUMAN"}
VALID_ISSUE_UPDATE_STATUS = {"UNCHANGED", "UPDATED", "RESOLVED", "REJECTED", "WAITING_FOR_HUMAN"}
VALID_RC = {"Confirmed", "Likely", "Hypothesis", "Unknown"}
VALID_ECO_REC = {"KEEP", "INVESTIGATE", "REPLACE", "DEPRECATE"}
VALID_ECO_POC = {"yes", "no"}

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-maintainer-audit\.md$")
FINDING_ID_RE = re.compile(r"^F-\d{4}-\d{2}-\d{2}-\d{2}$")
ECO_ID_RE = re.compile(r"^E-\d{4}-\d{2}-\d{2}-\d{2}$")
ISSUE_ID_RE = re.compile(r"^Issue #\d+$")


def check_field(block: str, field: str, valid: set[str], errors: list[str],
                label: str = "Finding") -> None:
    """检查 block 中的 `Field: value` 行，value 必须 ∈ valid。"""
    m = re.search(rf"^{re.escape(field)}:\s*(.+)$", block, re.MULTILINE)
    if not m:
        errors.append(f"{label} 缺 {field} 字段")
        return
    value = m.group(1).strip()
    if value not in valid:
        errors.append(f"{label} {field} 值非法: {value!r}（合法: {sorted(valid)}）")


def check_required_fields(block: str, fields: list[str], errors: list[str],
                          label: str) -> None:
    for f in fields:
        if not re.search(rf"^{re.escape(f)}:", block, re.MULTILINE):
            errors.append(f"{label} 缺 {f} 字段")


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

    # 1. 必需五块小节
    for sec in REQUIRED_SECTIONS:
        if sec not in text:
            errors.append(f"缺少必需小节: {sec}")

    next_after_findings = ["## Existing Issue Updates", "## Ecosystem Findings",
                           "## Pending Decisions"]

    # 2. New Findings 段
    findings_block = section_text(text, "## New Findings", next_after_findings)
    if re.search(r"(?m)^No significant findings\.?$", findings_block):
        # 无 Finding：允许，跳过枚举校验
        pass
    elif findings_block.strip() == "" or "## New Findings" not in findings_block:
        # 段不存在已在步骤 1 报错
        pass
    else:
        # 按 "### F-YYYY-MM-DD-NN" 切块（标题允许 ID 后带描述）
        blocks = re.split(r"(?m)^### F-\d{4}-\d{2}-\d{2}-\d{2}", findings_block)
        if len(blocks) < 2:
            errors.append("New Findings 段既无 'No significant findings.' 也无 F-ID 块")
        for i, block in enumerate(blocks[1:], start=1):
            if not block.strip():
                errors.append(f"Findings 块 #{i} 为空")
                continue
            check_field(block, "Category", VALID_CATEGORY, errors)
            check_field(block, "Severity", VALID_SEVERITY, errors)
            check_field(block, "Confidence", VALID_CONFIDENCE, errors)
            check_field(block, "Status", VALID_STATUS, errors)
            check_required_fields(block, ["Summary", "Evidence", "Impact",
                                          "Recommendation", "Related Issue"],
                                  errors, f"Finding #{i}")

    # 3. Existing Issue Updates 段（状态 / Root Cause）
    updates_block = section_text(text, "## Existing Issue Updates",
                                 ["## Ecosystem Findings", "## Pending Decisions"])
    if updates_block and not re.search(r"(?m)^None\.?$", updates_block):
        issue_blocks = re.split(r"(?m)^### Issue #\d+", updates_block)
        for i, block in enumerate(issue_blocks[1:], start=1):
            if not block.strip():
                errors.append(f"Issue Update 块 #{i} 为空")
                continue
            check_field(block, "Status", VALID_ISSUE_UPDATE_STATUS, errors, "Issue Update")
            check_field(block, "Root Cause", VALID_RC, errors, "Issue Update")
            check_required_fields(block, ["New Evidence", "Next Step"],
                                  errors, f"Issue Update #{i}")

    # 4. Ecosystem Findings 段（Recommendation / Decision）
    eco_block = section_text(text, "## Ecosystem Findings", ["## Pending Decisions"])
    if eco_block and not re.search(r"(?m)^No significant ecosystem findings\.?$", eco_block):
        eco_blocks = re.split(r"(?m)^### E-\d{4}-\d{2}-\d{2}-\d{2}", eco_block)
        if len(eco_blocks) < 2:
            errors.append("Ecosystem Findings 段既无 'No significant ecosystem findings.' 也无 E-ID 块")
        for i, block in enumerate(eco_blocks[1:], start=1):
            if not block.strip():
                errors.append(f"Ecosystem 块 #{i} 为空")
                continue
            check_field(block, "Recommendation", VALID_ECO_REC, errors, "Ecosystem")
            check_field(block, "Decision", VALID_ECO_POC, errors, "Ecosystem")
            check_required_fields(block, ["Topic", "Current Solution", "Alternative",
                                          "Comparison"],
                                  errors, f"Ecosystem #{i}")

    # 5. Pending Decisions 段（checkbox 列表或 None）
    pend_block = section_text(text, "## Pending Decisions", [])
    if pend_block and not re.search(r"(?m)^None\.?$", pend_block):
        if not re.search(r"(?m)^- \[ \]", pend_block):
            errors.append("Pending Decisions 段应为 '- [ ] <事项>' checkbox 列表或 'None.'")

    if errors:
        print("=== Audit 校验失败 ===", file=sys.stderr)
        for e in errors:
            print(f"  ✗ {e}", file=sys.stderr)
        return 1
    print(f"✅ Audit 格式校验通过: {path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
