#!/usr/bin/env python3
"""send_report.py — 发送 Tafcm Daily Maintainer Report 邮件

输入：report.json（generate_report.py 产物）
环境变量（Secrets，workflow 注入，绝不写入仓库）：
  MAIL_HOST / MAIL_PORT / MAIL_USERNAME / MAIL_PASSWORD / MAIL_TO

邮件内容（SCHEMA.md §6）：只报告值得维护者关注的事，**不包含完整 Audit**。
邮件标题：Tafcm Daily Maintainer Report — YYYY-MM-DD

失败语义（POLICY.md §6）：
  - MAIL_* secrets 未配置 → 打印 EMAIL_SKIPPED（明确跳过，exit 0，不伪装成功）
  - 配置了但发送失败 → 打印 EMAIL_DELIVERY=FAILED，exit 1
    （workflow 该步骤 continue-on-error，Audit 仍是 SUCCESS，由 status 步骤区分报告）
依赖：仅 Python 标准库（smtplib / email）。
"""
from __future__ import annotations

import json
import os
import smtplib
import sys
from email.header import Header
from email.mime.text import MIMEText
from email.utils import formatdate
from pathlib import Path

SEV_EMOJI = {"P0": "🔴", "P1": "🟠", "P2": "🟡", "P3": "🟢"}
ECOSYSTEM_EMOJI = {"KEEP": "✅", "INVESTIGATE": "🔍", "REPLACE": "⚠️", "DEPRECATE": "🚫"}


def render_body(report: dict) -> str:
    d = report["date"]
    findings = report.get("findings", [])
    inv = report.get("issue_investigations", [])
    eco = report.get("ecosystem", [])
    actions = report.get("recommended_actions", [])

    if not findings and not inv and not eco and not actions:
        return (
            f"# Tafcm Daily Maintainer Report — {d}\n\n"
            "No significant findings today.\n\n"
            f"Repository:\nCI: {report.get('ci', 'unknown')}\n"
            f"Tests: {report.get('tests', 'unknown')}\n"
            f"Build: {report.get('build', 'unknown')}\n"
        )

    lines = [f"# Tafcm Daily Maintainer Report — {d}", ""]

    lines.append("## Repository Health")
    lines.append(f"CI: {report.get('ci', 'unknown')}")
    lines.append(f"Tests: {report.get('tests', 'unknown')}")
    lines.append(f"Build: {report.get('build', 'unknown')}")
    lines.append("")

    if findings:
        lines.append("## New Findings")
        for f_ in findings:
            sev = f_.get("severity", "P2")
            emoji = SEV_EMOJI.get(sev, "⬜")
            lines.append(f"- {emoji} [{sev}] {f_.get('title', '')} ({f_.get('id', '')})")
            lines.append(f"  Confidence: {f_.get('confidence', '')} | Action: {f_.get('action', '')}"
                         + (f" | Issue: #{f_['issue']}" if f_.get("issue") else ""))
        lines.append("")

    if inv:
        lines.append("## Issue Investigations")
        for i in inv:
            lines.append(f"- Issue #{i.get('issue', '?')}: Root Cause={i.get('root_cause', '')} "
                         f"Status={i.get('status', '')}")
        lines.append("")

    if eco:
        lines.append("## Ecosystem Watch")
        for e in eco:
            emoji = ECOSYSTEM_EMOJI.get(e.get("recommendation", ""), "ℹ️")
            lines.append(f"- {emoji} {e.get('topic', '')} → {e.get('recommendation', '')}")
        lines.append("")

    if actions:
        lines.append("## Recommended Actions")
        for idx, a in enumerate(actions, 1):
            lines.append(f"{idx}. {a}")
        lines.append("")

    return "\n".join(lines)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: send_report.py <report.json>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"FAIL: report.json 不存在: {path}", file=sys.stderr)
        return 1
    report = json.loads(path.read_text(encoding="utf-8"))

    host = os.environ.get("MAIL_HOST", "").strip()
    port_raw = os.environ.get("MAIL_PORT", "").strip()
    username = os.environ.get("MAIL_USERNAME", "").strip()
    password = os.environ.get("MAIL_PASSWORD", "")
    to_addr = os.environ.get("MAIL_TO", "").strip()

    if not host or not username or not password or not to_addr:
        print("EMAIL_SKIPPED: MAIL_* secrets 未配置（workflow 已配置后启用）")
        return 0

    # MAIL_PORT 防护：非数字或越界（1-65535）视为配置错误，明确失败而非崩溃
    try:
        port = int(port_raw) if port_raw else 587
    except ValueError:
        print(f"EMAIL_DELIVERY=FAILED: MAIL_PORT 非数字: {port_raw!r}", file=sys.stderr)
        return 1
    if not (1 <= port <= 65535):
        print(f"EMAIL_DELIVERY=FAILED: MAIL_PORT 越界: {port}", file=sys.stderr)
        return 1

    date = report.get("date", "unknown")
    subject = f"Tafcm Daily Maintainer Report — {date}"
    body = render_body(report)

    msg = MIMEText(body, "plain", "utf-8")
    msg["Subject"] = Header(subject, "utf-8")
    msg["From"] = username
    msg["To"] = to_addr
    msg["Date"] = formatdate(localtime=True)

    try:
        with smtplib.SMTP(host, port, timeout=30) as smtp:
            smtp.ehlo()
            if port == 587:
                smtp.starttls()
                smtp.ehlo()
            smtp.login(username, password)
            smtp.sendmail(username, [to_addr], msg.as_string())
        print("EMAIL_DELIVERY=OK")
        print(f"✅ 邮件已发送: {subject} → {to_addr}")
        return 0
    except Exception as e:  # noqa: BLE001 —— 邮件失败明确上报，不吞异常
        print("EMAIL_DELIVERY=FAILED", file=sys.stderr)
        print(f"❌ 邮件发送失败: {type(e).__name__}: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
