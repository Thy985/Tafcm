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
VALID_FRONTIER_STATUS = {"in-progress", "needs-device-validation", "confirmed", "rejected"}
VALID_ACTIVATION = {"changed-code", "new-issue", "test-failure", "new-evidence", "risk-driven"}
VALID_VERIFICATION = {"in-progress", "needs-device-validation", "confirmed", "rejected"}
VALID_FRONTIER_LIFECYCLE = {"active", "deepening", "blocked", "cooling", "retired", "candidate"}
FRONTIER_PATH = Path(".agent/tafcm-maintainer/FRONTIER.md")

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-maintainer-audit\.md$")
FINDING_ID_RE = re.compile(r"^F-\d{4}-\d{2}-\d{2}-\d{2}$")
ECO_ID_RE = re.compile(r"^E-\d{4}-\d{2}-\d{2}-\d{2}$")
ISSUE_ID_RE = re.compile(r"^Issue #\d+$")


def _field_re(field: str) -> str:
    """构造字段行正则：容忍 Markdown 常见变体前缀/包裹。

    实测 Cline 输出会在字段行前加 `- ` 列表前缀或 `**` 加粗包裹
    （2026-09-01 v2 首次运行失败根因）。保持枚举值校验强度不变，
    仅放宽行首匹配：
      `- Category: tech-debt` / `**Category:** tech-debt` / `Category: tech-debt` 均接受。
    """
    return rf"^\s*(?:[-*+]\s+)?\*{{0,2}}{re.escape(field)}\*{{0,2}}\s*:\s*(.+)$"


def check_field(block: str, field: str, valid: set[str], errors: list[str],
                label: str = "Finding") -> None:
    """检查 block 中的 `Field: value` 行，value 必须 ∈ valid。"""
    m = re.search(_field_re(field), block, re.MULTILINE)
    if not m:
        errors.append(f"{label} 缺 {field} 字段")
        return
    value = m.group(1).strip()
    if value not in valid:
        errors.append(f"{label} {field} 值非法: {value!r}（合法: {sorted(valid)}）")


def check_required_fields(block: str, fields: list[str], errors: list[str],
                          label: str) -> None:
    for f in fields:
        if not re.search(_field_re(f), block, re.MULTILINE):
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


def validate_frontier(errors: list[str]) -> None:
    """SUP-04：校验 FRONTIER.md（若存在）。向后兼容：文件不存在则跳过（不破坏旧流程）。"""
    if not FRONTIER_PATH.is_file():
        return
    text = FRONTIER_PATH.read_text(encoding="utf-8")
    # 每个 Entry 必须含必填字段 + 枚举合法。区块：### FR-NNN 到下一个 ### 或文件尾。
    blocks = re.split(r"(?m)^### FR-\d{3}", text)
    for i, block in enumerate(blocks[1:], start=1):
        if not block.strip():
            errors.append(f"Frontier Entry #{i} 为空")
            continue
        check_field(block, "activation_reason", VALID_ACTIVATION, errors, f"Frontier #{i}")
        check_field(block, "verification_status", VALID_VERIFICATION, errors, f"Frontier #{i}")
        check_required_fields(block,
                              ["id", "area", "depth", "open_question", "next_action",
                               "blocking_reason", "last_verified_at", "activation_reason",
                               "verification_status"],
                              errors, f"Frontier #{i}")
        # id 格式必须 FR-NNN（递增，永不复用），仅存在不够
        id_m = re.search(_field_re("id"), block, re.MULTILINE)
        if id_m and not re.match(r"^FR-\d{3}$", id_m.group(1).strip()):
            errors.append(f"Frontier #{i}: id 格式非法（需 FR-NNN），实际: {id_m.group(1).strip()!r}")
        # 闭合必须有产出物：confirmed / rejected 的 Entry 不得缺失证据落点。
        # 只认字段行（`related_issue:` / `evidence:`），避免 activation_reason 值里的
        # "new-evidence" 单词被误判为产出物。
        m = re.search(_field_re("verification_status"), block, re.MULTILINE)
        if m and m.group(1).strip() in ("confirmed", "rejected"):
            has_output = (re.search(r"(?i)^\s*(?:[-*+]\s+)?related[_ ]issue\s*:", block, re.MULTILINE)
                          or re.search(r"(?i)^\s*(?:[-*+]\s+)?evidence\s*:", block, re.MULTILINE))
            if not has_output:
                errors.append(f"Frontier #{i}: {m.group(1).strip()} 闭合必须有产出物（related_issue: #NNN 或 evidence: <落点>）")
        # needs-device-validation 必须有 handoff（executor + reason）——POLICY §2.3.2
        if m and m.group(1).strip() == "needs-device-validation":
            if not re.search(_field_re("handoff"), block, re.MULTILINE):
                errors.append(f"Frontier #{i}: needs-device-validation 必须有 handoff 字段（executor + reason）")


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

    # 5. Pending Decisions 段（checkbox 或编号列表，或 None）
    pend_block = section_text(text, "## Pending Decisions", [])
    if pend_block and not re.search(r"(?m)^None\.?$", pend_block):
        if not (re.search(r"(?m)^- \[ \]", pend_block)
                or re.search(r"(?m)^\s*(?:[-*+]\s+)?\d+\.\s+", pend_block)):
            errors.append("Pending Decisions 段应为 '- [ ] <事项>' checkbox / '1. <事项>' 编号列表或 'None.'")

    # 6. SUP-04：FRONTIER.md（未闭合审查任务队列）格式校验（若存在）
    validate_frontier(errors)
    if errors:
        print("=== Audit 校验失败 ===", file=sys.stderr)
        for e in errors:
            print(f"  ✗ {e}", file=sys.stderr)
        return 1
    print(f"✅ Audit 格式校验通过: {path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
