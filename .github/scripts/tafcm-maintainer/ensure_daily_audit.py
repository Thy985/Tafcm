#!/usr/bin/env python3
"""ensure_daily_audit.py — 保证每日 audit 文件存在（修复 Issue #288）

背景（Issue #288）：maintainer workflow 偶发在"无 significant findings"日
出现 audit 缺失——workflow 整体 success 但 docs/agent-audit/ 无当日文件，
每日连续性断裂，次日 Agent 读近 N 天 audit 时跳过缺失日，趋势分析断裂。

方案（对齐 #288 建议）：无论 Cline 是否产出 findings，都确保当日
audit 文件存在并得到提交（即使内容为 "No significant findings."）。

本脚本为 workflow 的兜底步骤：checkout 后、Verify/Update 之前运行——
- 若当日 audit 文件已存在（Cline 正常产出）：不动，直接返回 0
- 若当日 audit 文件缺失（Cline 无产出 / 静默失败）：生成一个最小且
  满足 validate_audit.py 格式的 "No significant findings." 兜底文件，
  并明确标注为"自动生成兜底"，保证每日连续性

依赖：仅 Python 标准库。
"""
from __future__ import annotations

import argparse
import sys
from datetime import datetime
from pathlib import Path

TEMPLATE = """# Tafcm Daily Maintainer Audit

> 运行日期：{date}（本地 UTC+8）· 触发：schedule / workflow_dispatch
> ⚠️ 本文件由 ensure_daily_audit.py **自动生成的兜底 audit**：当日 Cline
> Maintainer 未正常产出审计文件（Issue #288），为保持每日连续性由机器兜底生成。
> 请次日 Maintainer 审查时核对当日仓库状态。

## Repository Health

Commit: 待核对（自动兜底未执行审查）
Version: 见 pubspec.yaml
CI: 待核对
Tests: 待核对
Build: 待核对

## New Findings

No significant findings.

## Existing Issue Updates

None.

## Ecosystem Findings

No significant ecosystem findings.

## Pending Decisions

None.

<!-- 兜底原因：#288 保持每日 audit 文件连续 -->
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("audit_dir", help="docs/agent-audit 目录")
    ap.add_argument("--date", default=None,
                    help="本地日期 YYYY-MM-DD（默认 = 系统本地日，UTC+8 由调用方处理）")
    args = ap.parse_args()

    audit_dir = Path(args.audit_dir)
    date = args.date or datetime.utcnow().strftime("%Y-%m-%d")
    audit_path = audit_dir / f"{date}-maintainer-audit.md"

    if not audit_dir.is_dir():
        print(f"FAIL: audit 目录不存在: {audit_dir}", file=sys.stderr)
        return 1

    if audit_path.is_file():
        print(f"ℹ️ 当日 audit 已存在，无需兜底: {audit_path.name}")
        return 0

    # 生成兜底（只补当日，避免误补历史缺失日）
    audit_path.parent.mkdir(parents=True, exist_ok=True)
    audit_path.write_text(TEMPLATE.format(date=date), encoding="utf-8")
    print(f"✅ 已生成兜底 audit（#288 保持每日连续）: {audit_path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())