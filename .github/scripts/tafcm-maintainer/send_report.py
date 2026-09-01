#!/usr/bin/env python3
"""send_report.py — 发送 Tafcm Maintainer 状态变化摘要邮件（双邮件策略）

输入：report.json（generate_report.py 产物）或 --audit-dir（digest 聚合模式）
环境变量（Secrets，workflow 注入，绝不写入仓库）：
  MAIL_HOST / MAIL_PORT / MAIL_USERNAME / MAIL_PASSWORD / MAIL_TO

邮件模式（SCHEMA.md §8，双邮件策略 POLICY.md §5.1）：
  --mode alert  立即邮件（P0/P1 / Release Blocker / 安全 / 需要决策）
  --mode digest 每周 Digest（状态变化摘要：新增/升级/解决/生态/需要你决策）
  --mode auto   自动：有 P0/P1 或待决策 → alert；否则跳过
                （digest 由 workflow 周五 10:00 UTC 独立 job 以 --mode digest 显式触发）

digest 聚合模式：
  --audit-dir <dir>  从最近 --days 天（默认 7）audit 文件合成 digest（不依赖当日 report.json）
  --days <N>         聚合窗口天数（默认 7）

原则：邮件做**状态变化摘要**（"自上次汇报以来发生了什么值得你知道的变化"），
**不是**每日 Audit 复述。让维护者 7 天不看邮箱也不错过上下文。
无重要变化时明确跳过（EMAIL_SKIPPED，exit 0，不伪装成功）。

失败语义（POLICY.md §6）：
  - MAIL_* secrets 未配置 → EMAIL_SKIPPED（exit 0）
  - 发送失败 → EMAIL_DELIVERY=FAILED（exit 1）
    （workflow 该步骤 continue-on-error，Audit 仍是 SUCCESS，由 status 步骤区分报告）
依赖：仅 Python 标准库（smtplib / email）+ 同目录 generate_report 解析函数。
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import smtplib
import sys
from email.header import Header
from email.mime.text import MIMEText
from email.utils import formatdate
from pathlib import Path

import generate_report as gr  # 复用 parse_audit / git_head / pubspec_version

SEV_EMOJI = {"P0": "🔴", "P1": "🟠", "P2": "🟡", "P3": "🟢"}
ECOSYSTEM_EMOJI = {"KEEP": "✅", "INVESTIGATE": "🔍", "REPLACE": "⚠️", "DEPRECATE": "🚫"}
STATUS_LABEL = {
    "NEW": "新增", "UPDATED": "升级", "RESOLVED": "解决", "REJECTED": "已拒绝",
    "UNCHANGED": "未变化", "DUPLICATE": "重复", "WAITING_FOR_HUMAN": "等待你",
}

ALERT_PRIORITIES = {"P0", "P1"}


def has_alert(report: dict) -> bool:
    """立即邮件触发条件：P0/P1 新发现或升级、需要决策。"""
    if report.get("pending_decisions"):
        return True
    for f_ in report.get("findings", []):
        if f_.get("severity") in ALERT_PRIORITIES and f_.get("status") in ("NEW", "UPDATED", "WAITING_FOR_HUMAN"):
            return True
    return False


def render_alert(report: dict) -> tuple[str, str]:
    """立即邮件 → (subject, body)。"""
    d = report.get("date", "unknown")
    subject = f"[Tafcm] Maintainer Alert — {d}"
    lines = ["⚠️ 需要立即关注", ""]
    flagged = False
    for f_ in report.get("findings", []):
        if f_.get("severity") in ALERT_PRIORITIES and f_.get("status") in ("NEW", "UPDATED", "WAITING_FOR_HUMAN"):
            flagged = True
            lines.append(f"- [{f_.get('severity')}] {f_.get('summary', '')}")
            lines.append(f"  根因：{f_.get('status', '')} · Confidence: {f_.get('confidence', '')}"
                         + (f" · Issue: #{f_['issue']}" if f_.get("issue") else ""))
            lines.append("")
    for iu in report.get("issue_updates", []):
        if iu.get("status") == "WAITING_FOR_HUMAN" and iu.get("root_cause") in ("Confirmed", "Likely"):
            flagged = True
            lines.append(f"- Issue #{iu.get('issue')} 等待决策（根因：{iu.get('root_cause')}）")
            lines.append(f"  下一步：{iu.get('next_step', '')}")
            lines.append("")
    if report.get("pending_decisions"):
        flagged = True
        lines.append("需要你决策")
        for p in report.get("pending_decisions", []):
            lines.append(f"- {p}")
    if not flagged:
        lines = ["无 P0/P1 严重项，但仍需关注：", ""]
        lines.append("（详见每周 Digest）")
    return subject, "\n".join(lines)


def render_digest(report: dict, window_days: int = 7) -> tuple[str, str]:
    """每周 Digest → (subject, body)：状态变化摘要。"""
    d = report.get("date", "unknown")
    end = dt.date.fromisoformat(d) if d != "unknown" else dt.date.today()
    start = end - dt.timedelta(days=window_days - 1)
    subject = f"[Tafcm] Maintainer Digest · {start} → {end}"

    lines = ["Tafcm Weekly Maintainer Digest", ""]
    lines.append("项目状态")
    lines.append(f"CI {report.get('ci', 'unknown')} · Tests {report.get('tests', 'unknown')}"
                 f" · Build {report.get('build', 'unknown')}")
    lines.append("")

    findings = report.get("findings", [])
    if findings:
        lines.append("过去一周新增")
        for f_ in findings:
            sev = f_.get("severity", "P2")
            ref = f"#{f_['issue']}" if f_.get("issue") else f_.get("id", "?")
            lines.append(f"- {ref} [{sev}] {f_.get('summary', '')}")
            lines.append(f"  状态：{STATUS_LABEL.get(f_.get('status', ''), f_.get('status', ''))}"
                         f" · Confidence: {f_.get('confidence', '')}")
        lines.append("")

    resolved = [f_ for f_ in findings if f_.get("status") in ("RESOLVED", "REJECTED")]
    if resolved:
        lines.append("过去一周解决")
        for f_ in resolved:
            lines.append(f"- {'✅' if f_.get('status') == 'RESOLVED' else '⛔'} {f_.get('summary', '')}")
        lines.append("")

    if report.get("ecosystem"):
        lines.append("生态变化")
        for e in report.get("ecosystem", []):
            emoji = ECOSYSTEM_EMOJI.get(e.get("recommendation", ""), "ℹ️")
            poc = "值得 PoC" if e.get("poc") == "yes" else "仍 KEEP/观察"
            lines.append(f"- {emoji} {e.get('topic', '')} → {e.get('recommendation', '')}（{poc}）")
        lines.append("")

    if report.get("pending_decisions"):
        lines.append("需要你决策")
        for i, p in enumerate(report.get("pending_decisions", []), 1):
            lines.append(f"{i}. {p}")
        lines.append("")

    if not findings and not report.get("ecosystem") and not report.get("pending_decisions"):
        lines.append("过去一周无重要事项")
    lines.append("")
    lines.append("其他")
    lines.append("无重要事项")
    return subject, "\n".join(lines)


def send(host: str, port: int, username: str, password: str, to_addr: str,
         subject: str, body: str) -> None:
    msg = MIMEText(body, "plain", "utf-8")
    msg["Subject"] = Header(subject, "utf-8")
    msg["From"] = username
    msg["To"] = to_addr
    msg["Date"] = formatdate(localtime=True)
    # 端口语义：465=SMTPS(SSL 直连)，587=STARTTLS 升级，其余按明文（常见 25）
    if port == 465:
        with smtplib.SMTP_SSL(host, port, timeout=30) as smtp:
            smtp.login(username, password)
            smtp.sendmail(username, [to_addr], msg.as_string())
    else:
        with smtplib.SMTP(host, port, timeout=30) as smtp:
            smtp.ehlo()
            if port == 587:
                smtp.starttls()
                smtp.ehlo()
            smtp.login(username, password)
            smtp.sendmail(username, [to_addr], msg.as_string())


def load_from_audits(audit_dir: str, days: int = 7) -> dict:
    """从最近 N 天 audit 文件聚合 report 数据（digest 模式，不依赖当日 report.json）。

    按日期倒序取最近 `days` 个 `YYYY-MM-DD-maintainer-audit.md` 文件，
    用 generate_report.parse_audit 解析后合并 findings / issue_updates /
    ecosystem / pending_decisions；仓库信息取最新文件。
    """
    files = sorted(Path(audit_dir).glob("*-maintainer-audit.md"), reverse=True)[:days]
    if not files:
        print(f"FAIL: {audit_dir} 下无 audit 文件", file=sys.stderr)
        raise SystemExit(1)
    merged: dict = {"findings": [], "issue_updates": [], "ecosystem": [],
                    "pending_decisions": []}
    for f in files:
        data = gr.parse_audit(f)
        for key in ("findings", "issue_updates", "ecosystem", "pending_decisions"):
            merged[key].extend(data.get(key, []))
    latest = files[0]
    merged["date"] = latest.stem[:10]
    merged["commit"] = gr.git_head()
    merged["version"] = gr.pubspec_version()
    merged["ci"] = merged["tests"] = merged["build"] = "unknown"
    return merged


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("report", nargs="?", help="report.json 路径（digest 聚合模式可省略）")
    ap.add_argument("--mode", choices=["auto", "alert", "digest"], default="auto",
                    help="auto: 有 P0/P1 或待决策→alert，否则跳过；digest 由周五 job 显式触发")
    ap.add_argument("--audit-dir", help="digest 聚合模式：从该目录最近 N 天 audit 合成")
    ap.add_argument("--days", type=int, default=7, help="digest 聚合窗口天数（默认 7）")
    args = ap.parse_args()

    # 输入来源：--audit-dir（digest 聚合）优先；否则 report.json
    if args.audit_dir:
        report = load_from_audits(args.audit_dir, args.days)
    else:
        if not args.report:
            print("FAIL: 缺少 report.json 或 --audit-dir", file=sys.stderr)
            return 2
        path = Path(args.report)
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

    # 模式决策：auto 只发 alert；digest 由 workflow 周五 job 显式 --mode digest 触发
    mode = args.mode
    if mode == "auto":
        if has_alert(report):
            mode = "alert"
        else:
            print("EMAIL_SKIPPED: 无 P0/P1 或待决策事项（不发每日复述邮件；digest 见周五周报）")
            return 0

    if mode == "alert":
        subject, body = render_alert(report)
    else:
        subject, body = render_digest(report, window_days=args.days)

    try:
        send(host, port, username, password, to_addr, subject, body)
        print("EMAIL_DELIVERY=OK")
        print(f"✅ 邮件已发送 [{mode}]: {subject} → {to_addr}")
        return 0
    except Exception as e:  # noqa: BLE001 —— 邮件失败明确上报，不吞异常
        print("EMAIL_DELIVERY=FAILED", file=sys.stderr)
        print(f"❌ 邮件发送失败: {type(e).__name__}: {e}", file=sys.stderr)
        print("提示：若 SMTP 服务器要求 SSL 直连请用 MAIL_PORT=465；", file=sys.stderr)
        print("      若要求 STARTTLS 请用 MAIL_PORT=587。", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
