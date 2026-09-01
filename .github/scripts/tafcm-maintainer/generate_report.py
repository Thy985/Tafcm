#!/usr/bin/env python3
"""generate_report.py — 从 Audit 生成机器可读 report.json（邮件输入）

按 .agent/tafcm-maintainer/SCHEMA.md §6 生成：
  {
    "date", "commit", "version", "ci", "tests", "build",
    "findings": [{id, severity, confidence, title, action, issue}],
    "issue_investigations": [{issue, root_cause, status}],
    "ecosystem": [{id, topic, recommendation}],
    "recommended_actions": [...]
  }

report.json 不入库，仅作为邮件中间产物（workflow 上传 artifact）。
依赖：仅 Python 标准库。
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})-maintainer-audit\.md$")


def git_head() -> str:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=10,
        )
        return out.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


def parse_audit(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")

    findings = []
    # 标题允许 ID 后带描述（如 "### F-2026-09-01-01（续 F1 昨日）— 标题"）
    for m in re.finditer(r"(?ms)^### (F-\d{4}-\d{2}-\d{2}-\d{2})\b(.*?)(?=^### |\Z)", text):
        fid, block = m.group(1), m.group(2)
        def field(name: str) -> str:
            fm = re.search(rf"^{re.escape(name)}:\s*(.+)$", block, re.MULTILINE)
            return fm.group(1).strip() if fm else ""
        issue_m = re.search(r"(?m)^Issue:\s*#?(\d+)\s*$", block)
        findings.append({
            "id": fid,
            "severity": field("Severity"),
            "confidence": field("Confidence"),
            "title": field("Problem"),
            "action": "issue-created" if issue_m else "audit-only",
            "issue": int(issue_m.group(1)) if issue_m else None,
        })

    inv = []
    inv_block = text.split("## Ecosystem Watch")[0].split("## Issue Investigations")[-1]
    for m in re.finditer(r"(?ms)^### Issue #(\d+)\b(.*?)(?=^### |\Z)", inv_block):
        num, block = m.group(1), m.group(2)
        def f2(name: str) -> str:
            fm = re.search(rf"^{re.escape(name)}:\s*(.+)$", block, re.MULTILINE)
            return fm.group(1).strip() if fm else ""
        inv.append({
            "issue": int(num),
            "root_cause": f2("Root Cause"),
            "status": f2("Status"),
        })

    eco = []
    for m in re.finditer(r"(?ms)^### (E-\d{4}-\d{2}-\d{2}-\d{2})$(.*?)(?=^### |\Z)", text):
        eid, block = m.group(1), m.group(2)
        def f3(name: str) -> str:
            fm = re.search(rf"^{re.escape(name)}:\s*(.+)$", block, re.MULTILINE)
            return fm.group(1).strip() if fm else ""
        eco.append({"id": eid, "topic": f3("Topic"), "recommendation": f3("Recommendation")})

    actions_section = text.split("## Recommended Actions")[-1]
    actions = [l.strip() for l in re.findall(r"(?m)^\d+\.\s+(.+)$", actions_section)]

    return {"findings": findings, "issue_investigations": inv,
            "ecosystem": eco, "recommended_actions": actions}


def pubspec_version() -> str:
    """从 flutter_app/pubspec.yaml 提取 version 字段（如 1.0.1+1）。

    仓库根相对路径（workflow 默认 working-directory=$GITHUB_WORKSPACE）；
    文件缺失或字段缺失时回退 "N/A"。
    """
    try:
        pubspec = Path("flutter_app/pubspec.yaml").read_text(encoding="utf-8")
    except OSError:
        return "N/A"
    vm = re.search(r"^version:\s*(.+)$", pubspec, re.MULTILINE)
    return vm.group(1).strip() if vm else "N/A"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("audit", help="docs/agent-audit/YYYY-MM-DD-maintainer-audit.md")
    ap.add_argument("--out", required=True, help="report.json 输出路径")
    args = ap.parse_args()

    path = Path(args.audit)
    if not DATE_RE.match(path.name) or not path.is_file():
        print(f"FAIL: Audit 文件不合法: {path}", file=sys.stderr)
        return 1

    data = parse_audit(path)
    report = {
        "date": path.stem[:10],
        "commit": git_head(),
        "version": pubspec_version(),
        "ci": "unknown",
        "tests": "unknown",
        "build": "unknown",
        **data,
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"✅ report.json 已生成: {out} "
          f"(findings={len(report['findings'])}, investigations={len(report['issue_investigations'])}, "
          f"ecosystem={len(report['ecosystem'])})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
