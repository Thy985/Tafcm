#!/usr/bin/env python3
"""fingerprint.py — Finding 稳定身份注册表（E4 Finding Identity 修复）

问题（VALIDATION.md E4 根因）：identity 完全依赖 Agent 的 LLM 自然语言判断，
同一 Finding 跨运行可能被标回 NEW、Finding ID 漂移（F-02 → F-01），
因为机器侧没有可计算的 Finding 身份。

方案：stable_fingerprint = SHA-256(category | evidence_file_path | normalized_summary)
  - category：Audit Finding 的 Category 枚举（bug/regression/...）——稳定受控词
  - evidence_file_path：从 Evidence 字段提取的**文件名**（.dart/.py/.yml 等），
    不取行号（代码移动后行号会变）、不取完整路径（目录重构会变）
  - normalized_summary：Summary 归一化（小写、去空白/标点、截断 48 字符）
    ——缓解 LLM 措辞漂移；evidence 文件路径是强锚点，summary 是辅助

注册表：docs/agent-audit/FINDINGS.md（机器维护，Agent 读取做跨运行去重）
  | fingerprint | latest_id | category | evidence | status | issue | first_seen | last_seen |

用法：
  fingerprint.py <audit.md> [registry.md]
  - 提取 audit 全部 Finding 块，计算 fingerprint
  - 与注册表比对：命中 = 旧 Finding 的延续（输出 HIT + 旧 ID）；未命中 = 新 Finding
  - 更新注册表（latest_id/status/issue/first_seen/last_seen 演进；重复运行幂等）
  - 输出 dedup 报告到 stdout（机器可读），同时写 <audit>.dedup.json（workflow 上传）

依赖：仅 Python 标准库。禁止针对实验/特定 Finding 硬编码。
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})-maintainer-audit\.md$")
REGISTRY_MARKER = "<!-- REGISTRY_ROWS -->"
# 默认注册表固定"头"（新建/头丢失时回退）。与既有已生成文件头保持一致，
# 避免新建文件产生与新 schema 抽取结果不一致的头。
DEFAULT_REGISTRY_SCHEMA = (
    "# Tafcm Agent Finding Registry（机器维护，Agent 读取去重）\n\n"
    "> 每行 = 一个稳定 Finding 身份（fingerprint）。Agent 运行前先读本表：\n"
    "> fingerprint 命中 = 旧 Finding 的延续（标 UNCHANGED/UPDATED 并关联既有 Issue），\n"
    "> 不得重新标 NEW / 不得新建 Issue。由 fingerprint.py 自动维护。\n\n"
    "| fingerprint | latest_id | category | evidence | status | issue | first_seen | last_seen |\n"
    "|-------------|-----------|----------|----------|--------|-------|------------|-----------|\n"
)
# 归一化时保留的中文/字母数字（去标点与空白）
_KEEP = re.compile(r"[^\w\u4e00-\u9fff]+")
# Evidence 中的文件路径锚点：取 文件名（去行号后缀）
_FILE_RE = re.compile(r"([\w-]+\.(?:dart|py|yml|yaml|json|md|sh|html))(?::\d+)?")
# Summary 归一化截断长度（缓解措辞漂移同时保留关键词）
_SUMMARY_MAX = 48


def _field(block: str, name: str) -> str:
    """解析 `Field: value` 行，容忍 Markdown 变体前缀/包裹（与 validate_audit 一致）。"""
    m = re.search(rf"^\s*(?:[-*+]\s+)?\*{{0,2}}{re.escape(name)}\*{{0,2}}\s*:\s*(.+)$",
                  block, re.MULTILINE)
    return m.group(1).strip() if m else ""


def normalize_summary(summary: str) -> str:
    """归一化：小写、去标点/空白、去行号、截断。"""
    s = _KEEP.sub(" ", summary.lower())
    s = re.sub(r"\s+", " ", s).strip()
    return s[:_SUMMARY_MAX]


def evidence_files(evidence: str) -> list[str]:
    """从 Evidence 提取文件名锚点（去重保序，最多 3 个）。"""
    seen: list[str] = []
    for m in _FILE_RE.finditer(evidence or ""):
        name = m.group(1)
        if name not in seen:
            seen.append(name)
        if len(seen) >= 3:
            break
    return seen


def fingerprint(category: str, files: list[str], norm_summary: str) -> str:
    """stable_fingerprint。

    锚点优先级（回归验证 33506769952 实测修正）：
    - 有 evidence 文件路径时：`SHA-256(category | files)`——文件路径是强锚点，
      不受 Summary 措辞漂移影响（同一 bug 两次运行的 Summary 可能不同，但
      证据文件相同 → fingerprint 必须相同才能命中注册表）
    - 无 evidence 文件路径时：`SHA-256(category | norm_summary)`——兜底。
    """
    if files:
        payload = "|".join([category, ",".join(files)])
    else:
        payload = "|".join([category, norm_summary])
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


def extract_findings(text: str) -> list[dict]:
    """从 New Findings 段提取全部 Finding 块。"""
    next_headers = ["## Existing Issue Updates", "## Ecosystem Findings", "## Pending Decisions"]
    start = text.find("## New Findings")
    if start == -1:
        return []
    seg = text[start:]
    for nh in next_headers:
        idx = seg.find(nh)
        if idx != -1:
            seg = seg[:idx]
            break
    findings = []
    for m in re.finditer(r"(?ms)^### (F-\d{4}-\d{2}-\d{2}-\d{2})\b(.*?)(?=^### |\Z)", seg):
        fid, block = m.group(1), m.group(2)
        category = _field(block, "Category")
        summary = _field(block, "Summary")
        files = evidence_files(_field(block, "Evidence"))
        norm = normalize_summary(summary)
        findings.append({
            "id": fid,
            "category": category,
            "evidence_files": files,
            "norm_summary": norm,
            "fingerprint": fingerprint(category, files, norm),
            "status": _field(block, "Status"),
            "issue": _field(block, "Related Issue"),
        })
    return findings


def load_registry(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("| ") or "fingerprint" in line and "latest_id" in line:
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) >= 8:
            rows.append({"fingerprint": cells[0], "latest_id": cells[1],
                         "category": cells[2], "evidence": cells[3],
                         "status": cells[4], "issue": cells[5],
                         "first_seen": cells[6], "last_seen": cells[7]})
    return rows


def row_line(row: dict) -> str:
    return (f"| {row['fingerprint']} | {row['latest_id']} | {row['category']} "
            f"| {row['evidence']} | {row['status']} | {row['issue']} "
            f"| {row['first_seen']} | {row['last_seen']} |")


def _registry_schema(text: str) -> str:
    """抽取注册表固定"头"（标题/说明/表头/分隔线），丢弃全部历史数据行。

    分隔线行（`|---|...|`）之后即数据区；返回分隔行结尾（含换行）之前的
    全部内容作为 schema。若无匹配行（文件缺失/损坏）返回空串，调用方回退标准头。
    """
    m = re.search(r"(?m)^\s*\|[ \t:\-|]+\|\s*$", text)  # 表格分隔行
    if m:
        return text[: m.end()] + "\n"
    return ""


def collapse_and_write(reg_path: Path, merged: dict[str, dict]) -> None:
    """幂等重建注册表：固定"头"（schema）+ 去重唯一行 + 标记行。

    Issue #289：旧实现只替换标记行、保留标记上方全部历史行，导致注册表
    只增不减无限膨胀。这里**整体重建数据区**，无论既有文件含多少重复行，
    都按 fingerprint 去重后写回唯一行，使运行幂等、历史重复一次清空。
    """
    lines = sorted(merged.values(), key=lambda r: r["fingerprint"])
    table_rows = "".join(f"{row_line(r)}\n" for r in lines)

    reg_text = reg_path.read_text(encoding="utf-8") if reg_path.is_file() else ""
    schema = _registry_schema(reg_text) if reg_text else ""
    if not schema:
        schema = DEFAULT_REGISTRY_SCHEMA
    reg_path.write_text(f"{schema}{table_rows}{REGISTRY_MARKER}\n", encoding="utf-8")


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print("usage: fingerprint.py <audit.md> [registry.md]", file=sys.stderr)
        return 2
    audit_path = Path(sys.argv[1])
    reg_path = Path(sys.argv[2]) if len(sys.argv) == 3 else \
        audit_path.parent / "FINDINGS.md"
    if not DATE_RE.match(audit_path.name) or not audit_path.is_file():
        print(f"FAIL: Audit 文件不合法: {audit_path}", file=sys.stderr)
        return 1

    text = audit_path.read_text(encoding="utf-8")
    date = audit_path.stem[:10]
    findings = extract_findings(text)
    if not findings:
        print("no findings in audit (No significant findings. 或解析失败)")
        return 0

    registry = load_registry(reg_path)
    by_fp = {r["fingerprint"]: r for r in registry}

    report = {"date": date, "findings": []}
    new_rows: list[dict] = []
    for f in findings:
        hit = by_fp.get(f["fingerprint"])
        entry = {
            "fingerprint": f["fingerprint"],
            "latest_id": f["id"],
            "category": f["category"],
            "evidence": ",".join(f["evidence_files"]),
            "status": f["status"],
            "issue": f["issue"],
            "first_seen": hit["first_seen"] if hit else date,
            "last_seen": date,
        }
        # 幂等：注册表中同一 fingerprint 的 latest_id 已更新过则不重复追加
        if hit and hit["latest_id"] == f["id"]:
            # 更新状态/issue 但保持 first_seen
            hit.update({"status": f["status"], "issue": f["issue"], "last_seen": date})
            new_rows.append(hit)
        elif hit:
            new_rows.append(entry)  # 延续：latest_id 演进
        else:
            new_rows.append(entry)  # 新 Finding

        report["findings"].append({
            "id": f["id"],
            "fingerprint": f["fingerprint"],
            "category": f["category"],
            "evidence_files": f["evidence_files"],
            "status": f["status"],
            "issue": f["issue"],
            "hit_previous": bool(hit),
            "previous_id": hit["latest_id"] if hit else None,
        })
        tag = "HIT" if hit else "NEW"
        prev = f" (prev={hit['latest_id']})" if hit else ""
        print(f"[{tag}] {f['id']} fp={f['fingerprint'][:10]} "
              f"cat={f['category']} files={','.join(f['evidence_files']) or '-'}{prev}")

    # 写注册表（保留未出现的旧行 + 本次行，按 fingerprint 排序稳定）
    #
    # ⚠️ Issue #289 修复：**整体重建数据区**，而非「只替换标记行」。
    # 旧实现 `re.sub/str.replace` 只把新表插入到 `<!-- REGISTRY_ROWS -->`
    # 处、保留标记上方全部历史行 → 每次运行把 280+ 历史行原样保留并再
    # 追加一份完整新表，注册表只增不减无限膨胀（W39：257 重复/最多 29 次）。
    # 现在：抽取固定"头"（标题/说明/表头/分隔线 = schema）后，用去重后
    # 的唯一行重建整个数据区，使运行幂等、历史重复一次清空。
    merged: dict[str, dict] = {r["fingerprint"]: r for r in registry}
    for r in new_rows:
        merged[r["fingerprint"]] = r
    collapse_and_write(reg_path, merged)

    # dedup 报告（workflow 上传 / 供校验）
    report["summary"] = {
        "total": len(findings),
        "hits": sum(1 for f in report["findings"] if f["hit_previous"]),
        "new": sum(1 for f in report["findings"] if not f["hit_previous"]),
    }
    (audit_path.parent / f"{audit_path.stem}.dedup.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"registry updated: {reg_path} (rows={len(merged)})")
    print(f"summary: total={report['summary']['total']} "
          f"hits={report['summary']['hits']} new={report['summary']['new']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

