#!/usr/bin/env python3
"""generate_report.py — 从 Audit 生成机器可读 report.json（邮件输入）

按 .agent/tafcm-maintainer/SCHEMA.md §7 生成：
  {
    "date", "commit", "version", "ci", "tests", "build",
    "findings": [{id, severity, confidence, status, summary, issue}],
    "issue_updates": [{issue, status, root_cause, next_step}],
    "ecosystem": [{id, topic, recommendation, poc}],
    "pending_decisions": [...]
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
    next_after_findings = ["## Existing Issue Updates", "## Ecosystem Findings",
                           "## Pending Decisions"]

    # ---- New Findings ----
    findings = []
    f_block = section_text(text, "## New Findings", next_after_findings)
    for m in re.finditer(r"(?ms)^### (F-\d{4}-\d{2}-\d{2}-\d{2})\b(.*?)(?=^### |\Z)", f_block):
        fid, block = m.group(1), m.group(2)
        issue_m = re.search(r"(?m)^Related Issue:\s*#?(\d+)\s*$", block)
        findings.append({
            "id": fid,
            "severity": _field(block, "Severity"),
            "confidence": _field(block, "Confidence"),
            "status": _field(block, "Status"),
            "summary": _field(block, "Summary"),
            "issue": int(issue_m.group(1)) if issue_m else None,
        })

    # ---- Existing Issue Updates ----
    issue_updates = []
    iu_block = section_text(text, "## Existing Issue Updates",
                            ["## Ecosystem Findings", "## Pending Decisions"])
    for m in re.finditer(r"(?ms)^### Issue #(\d+)\b(.*?)(?=^### |\Z)", iu_block):
        num, block = m.group(1), m.group(2)
        issue_updates.append({
            "issue": int(num),
            "status": _field(block, "Status"),
            "root_cause": _field(block, "Root Cause"),
            "next_step": _field(block, "Next Step"),
        })

    # ---- Ecosystem Findings ----
    ecosystem = []
    eco_block = section_text(text, "## Ecosystem Findings", ["## Pending Decisions"])
    for m in re.finditer(r"(?ms)^### (E-\d{4}-\d{2}-\d{2}-\d{2})\b(.*?)(?=^### |\Z)", eco_block):
        eid, block = m.group(1), m.group(2)
        ecosystem.append({
            "id": eid,
            "topic": _field(block, "Topic"),
            "recommendation": _field(block, "Recommendation"),
            "poc": _field(block, "Decision"),
        })

    # ---- Pending Decisions ----
    pend_block = section_text(text, "## Pending Decisions", [])
    pending_decisions = [l.strip() for l in re.findall(r"(?m)^- \[ \]\s*(.+)$", pend_block)]

    return {"findings": findings, "issue_updates": issue_updates,
            "ecosystem": ecosystem, "pending_decisions": pending_decisions}


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
          f"(findings={len(report['findings'])}, issue_updates={len(report['issue_updates'])}, "
          f"ecosystem={len(report['ecosystem'])}, pending={len(report['pending_decisions'])})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
