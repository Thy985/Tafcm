"""DOCX Agent-native QA — OOXML integrity + semantic extraction for ffx.

实现 docs/DOCX-QA-PIPELINE.md 的 Level A（Agent-native DOCX Quality）：
- OOXML / ZIP structural validation（Content_Types / document / styles /
  settings / rels 无 dangling）
- Semantic validation（paragraph/heading/list/table/formula count + 文本）
- 输出 JSON 质量报告（artifact_integrity / semantic_fidelity 等）

WPS consumer（真实 Office-compatible 打开/转换）由外部 wpscli 执行，
本模块提供结果注入点。
"""

from __future__ import annotations

import os
import re
import zipfile
from pathlib import Path
from typing import Any

REQUIRED_PARTS = [
    "[Content_Types].xml",
    "word/document.xml",
    "word/styles.xml",
    "word/settings.xml",
    "word/_rels/document.xml.rels",
]


def audit_docx(path: str | Path) -> dict[str, Any]:
    """审计 .docx：OOXML 结构 + 语义模型 + WPS consumer → JSON 质量报告。

    Level A（Agent-native）：不依赖 Microsoft Word；ZIP/XML/rels 可程序化验证；
    若主机装有 WPS，额外执行 word2pdf 转换作为真实消费端证据。
    """
    p = Path(path)
    result: dict[str, Any] = {
        "path": str(p),
        "artifact_integrity": "fail",
        "semantic_fidelity": "unknown",
        "wps_compatibility": "unknown",
        "visual_fidelity": "unknown",
        "microsoft_word": "unknown",
        "details": {},
    }

    if not p.exists():
        result["details"]["error"] = f"file not found: {p}"
        return result

    try:
        with zipfile.ZipFile(p) as zf:
            # ZIP 可解包 + CRC（ZipFile 读取时自动校验 CRC）
            names = set(zf.namelist())
            bad = zf.testzip()
            if bad:
                result["details"]["zip_crc"] = f"fail: {bad}"
                return result
            result["details"]["zip_crc"] = "pass"

            # 必需 part 存在性
            missing = [r for r in REQUIRED_PARTS if r not in names]
            result["details"]["missing_parts"] = missing
            if missing:
                return result
            result["details"]["content_types"] = "pass"

            # rels 无 dangling：document.xml.rels 的 Target 必须存在于 ZIP
            rels_xml = zf.read("word/_rels/document.xml.rels").decode(
                "utf-8", errors="replace"
            )
            dangling = _find_dangling_rels(rels_xml, names)
            result["details"]["dangling_rels"] = dangling
            result["details"]["relationships"] = "pass" if not dangling else "fail"

            # document.xml 语义模型
            doc_xml = zf.read("word/document.xml").decode("utf-8", errors="replace")
            semantic = _extract_semantic(doc_xml)
            result["details"]["semantic"] = semantic
            result["artifact_integrity"] = (
                "pass" if not dangling else "warn"
            )
            result["semantic_fidelity"] = "pass" if semantic["text_count"] > 0 else "fail"
    except zipfile.BadZipFile as e:
        result["details"]["error"] = f"not a valid zip/docx: {e}"
        return result
    except Exception as e:  # noqa: BLE001 — 报告型模块，捕获并转 JSON
        result["details"]["error"] = str(e)
        return result

    # WPS consumer：真实 Office-compatible 打开/转换证据（可选增强）
    wps_status, wps_detail = _wps_consumer_check(p)
    result["wps_compatibility"] = wps_status
    result["details"]["wps"] = wps_detail

    # wpscli 深度验证：消费端 PDF 元数据（分页正确性）+ 消费端文本（语义）
    wps_meta = _wps_pdf_metadata_check(p)
    wps_text = _wps_text_semantic_check(p)
    result["details"]["wps_pdf_metadata"] = wps_meta
    result["details"]["wps_semantic_text"] = wps_text

    # LibreOffice consumer：多引擎交叉验证（Level B，可选二级引擎）
    lo_status, lo_detail = _libreoffice_consumer_check(p)
    result["libreoffice_compatibility"] = lo_status
    result["details"]["libreoffice"] = lo_detail

    # OfficeCLI：Agent-native 视觉验证 + 结构化问题分析（CAP-WORD-F 补充）
    oc_visual = _officecli_visual_check(p)
    oc_issues = _officecli_issues_check(p)
    result["details"]["officecli_visual"] = oc_visual
    result["details"]["officecli_issues"] = oc_issues
    if oc_visual.get("status") == "pass":
        result["visual_fidelity"] = "review"
        result["details"]["visual_note"] = "officecli view screenshot 已捕获（Agent/人工审阅）"

    # office_compatibility 多引擎汇总：
    #   pass   = 至少一个真实消费端（WPS/LibreOffice）转换成功
    #   warn   = 至少一个引擎 fail（转换报错）
    #   unknown= 无任何消费端可用（未验证，非失败）
    # 注意：OfficeCLI（officecli_visual/officecli_issues）不计入本聚合——
    # 它是 Agent-native 渲染/问题分析补充，非「Office-compatible 消费端」
    # 转换引擎；其状态独立反映在 visual_fidelity 与 details.officecli_*。
    engine_statuses = [wps_status, lo_status]
    if "pass" in engine_statuses:
        result["office_compatibility"] = "pass"
    elif "fail" in engine_statuses:
        result["office_compatibility"] = "warn"
    else:
        result["office_compatibility"] = "unknown"

    return result


def _find_soffice() -> str | None:
    """探测 LibreOffice soffice.exe（常见安装路径）。"""
    import glob

    candidates = [
        Path("C:/Program Files/LibreOffice/program/soffice.exe"),
        Path("C:/Program Files (x86)/LibreOffice/program/soffice.exe"),
        Path(os.environ.get("PROGRAMFILES", "")) / "LibreOffice" / "program" / "soffice.exe",
        Path(os.environ.get("PROGRAMFILES(X86)", "")) / "LibreOffice" / "program" / "soffice.exe",
    ]
    for c in candidates:
        if c.exists():
            return str(c)
    # 兜底：PATH 中查找
    hits = glob.glob(str(Path(".") / "soffice.exe")) or []
    return hits[0] if hits else None


def _libreoffice_consumer_check(docx_path: Path) -> tuple[str, str]:
    """用 LibreOffice headless 转换 docx → pdf。返回 (status, detail)。

    status ∈ {pass, fail, unknown}：pass = 转换成功（多引擎交叉验证通过）；
    unknown = 主机无 LibreOffice（非失败，仅未验证）。
    """
    import subprocess
    import tempfile

    soffice = _find_soffice()
    if not soffice:
        return "unknown", "soffice not found (LibreOffice 未安装，跳过)"
    with tempfile.TemporaryDirectory() as td:
        try:
            r = subprocess.run(
                [
                    soffice, "--headless", "--convert-to", "pdf",
                    "--outdir", td, str(docx_path),
                ],
                capture_output=True, text=True, timeout=120,
            )
            if r.returncode == 0:
                return "pass", f"libreoffice headless convert ok (soffice={soffice})"
            return "fail", (r.stdout + r.stderr)[-300:]
        except Exception as e:  # noqa: BLE001
            return "fail", f"libreoffice convert error: {e}"


def _find_officecli() -> str | None:
    """探测 OfficeCLI（officecli.exe）——常见安装路径 + 本机实测路径。"""
    import glob
    import shutil

    # PATH / 常见安装目录
    found = shutil.which("officecli") or shutil.which("officecli.exe")
    if found:
        return found
    candidates = [
        Path("D:/Temp/officecli/officecli.exe"),
        Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "OfficeCLI" / "officecli.exe",
        Path("C:/Program Files/OfficeCLI/officecli.exe"),
    ]
    for c in candidates:
        if c.exists():
            return str(c)
    # 兜底：glob 搜索（受限）
    hits = sorted(glob.glob("**/officecli.exe", recursive=True))[:1]
    return hits[0] if hits else None


def _officecli_visual_check(docx_path: Path) -> dict[str, Any]:
    """用 OfficeCLI view screenshot 渲染 docx → PNG（CAP-WORD-F 视觉捕获）。

    status ∈ {pass, fail, unknown}：pass = PNG 已生成（Agent/人工可审阅）；
    unknown = 主机无 OfficeCLI（非失败，仅未验证）。
    """
    import subprocess
    import tempfile

    officecli = _find_officecli()
    base = {"status": "unknown", "png_path": None, "page_count": None}
    if not officecli:
        return base
    with tempfile.TemporaryDirectory() as td:
        try:
            png = str(Path(td) / "page_1.png")
            r = subprocess.run(
                [officecli, "view", str(docx_path), "screenshot", "--page", "1", "--out", png],
                capture_output=True, text=True, timeout=120,
            )
            if r.returncode == 0 and Path(png).exists():
                size = Path(png).stat().st_size
                base["status"] = "pass" if size > 0 else "fail"
                base["png_path"] = png
                base["page_count"] = 1
                return base
            return {"status": "fail", "error": (r.stdout + r.stderr)[-200:]}
        except Exception as e:  # noqa: BLE001
            return {"status": "fail", "error": str(e)}


def _officecli_issues_check(docx_path: Path) -> dict[str, Any]:
    """用 OfficeCLI view issues 获取结构化问题清单（Agent 可自愈）。

    status ∈ {pass, fail, unknown}：pass = issues 查询成功（含问题数）；
    unknown = 主机无 OfficeCLI。
    """
    import json as jsonlib
    import subprocess

    officecli = _find_officecli()
    base = {"status": "unknown", "issue_count": None, "issues": []}
    if not officecli:
        return base
    try:
        r = subprocess.run(
            [officecli, "view", str(docx_path), "issues", "--json"],
            capture_output=True, text=True, timeout=120,
        )
        out = r.stdout.strip()
        start = out.find("{")
        if r.returncode == 0 and start >= 0:
            data = jsonlib.loads(out[start:])
            # R10/schema 校验：data.issues 必须是 list，否则 fail
            # （防止 OfficeCLI 输出格式变更时 .get("issues", []) 空列表误报 pass）
            issues_raw = data.get("data", {}).get("issues")
            if not isinstance(issues_raw, list):
                base["status"] = "fail"
                base["error"] = (
                    f"officecli issues schema 不符（data.issues 非 list）: "
                    f"{out[:200]}"
                )
                return base
            issues = issues_raw
            base["status"] = "pass"
            base["issue_count"] = len(issues)
            base["issues"] = [
                {"id": i.get("id"), "severity": i.get("severity"),
                 "path": i.get("path"), "message": i.get("message")}
                for i in issues[:20]  # 截断，避免超长
            ]
            return base
        base["status"] = "fail"
        base["error"] = out[-200:]
        return base
    except Exception as e:  # noqa: BLE001
        base["status"] = "fail"
        base["error"] = str(e)
        return base


def _find_wpscli() -> str | None:
    """探测 WPS 命令行工具（wpscli.exe），常见用户级/程序级安装路径。"""
    import glob

    candidates = [
        Path(os.environ.get("LOCALAPPDATA", ""))
        / "Kingsoft" / "WPS Office" / "*" / "clitool" / "wpscli.exe",
        Path("C:/Program Files") / "Kingsoft" / "WPS Office"
        / "*" / "clitool" / "wpscli.exe",
    ]
    for pat in candidates:
        hits = sorted(glob.glob(str(pat)))
        if hits:
            return hits[-1]
    return None


def _wps_consumer_check(docx_path: Path) -> tuple[str, str]:
    """尝试用 WPS word2pdf 转换 docx。返回 (status, detail)。

    status ∈ {pass, fail, unknown}：pass = 转换成功（真实消费端可解析）；
    unknown = 主机无 WPS（非失败，仅未验证）。
    """
    import subprocess
    import tempfile

    wpscli = _find_wpscli()
    if not wpscli:
        return "unknown", "wpscli not found (WPS 未安装，跳过)"
    with tempfile.TemporaryDirectory() as td:
        try:
            r = subprocess.run(
                [wpscli, "word2pdf", str(docx_path), "--json"],
                capture_output=True, text=True, timeout=90,
            )
            out = r.stdout + r.stderr
            if r.returncode == 0 and '"status":"success"' in out.replace(" ", ""):
                return "pass", f"wps word2pdf ok (wpscli={wpscli})"
            return "fail", out[-300:]
        except Exception as e:  # noqa: BLE001
            return "fail", f"wps convert error: {e}"


def _wps_pdf_metadata_check(docx_path: Path) -> dict[str, Any]:
    """用 WPS pdfinfo 读取转换后 PDF 元数据（页数/扫描提示）。

    wpscli 管道：word2pdf → pdfinfo（消费端分页正确性证据）。
    返回 dict（status + page_count + is_scan_document 等）。
    """
    import json as jsonlib
    import subprocess
    import tempfile

    wpscli = _find_wpscli()
    base = {"status": "unknown", "page_count": None, "is_scan_document": None}
    if not wpscli:
        return base
    with tempfile.TemporaryDirectory() as td:
        try:
            pdf = str(Path(td) / "out.pdf")
            r1 = subprocess.run(
                [wpscli, "word2pdf", str(docx_path), "--output", pdf, "--json"],
                capture_output=True, text=True, timeout=90,
            )
            if r1.returncode != 0:
                base["status"] = "fail"
                base["error"] = (r1.stdout + r1.stderr)[-200:]
                return base
            r2 = subprocess.run(
                [wpscli, "pdfinfo", pdf, "--json"],
                capture_output=True, text=True, timeout=60,
            )
            out = r2.stdout.strip()
            # pdfinfo JSON 行：{"type":"completed","page_count":1,"is_scan_document":false,...}
            start = out.find("{")
            if start >= 0:
                data = jsonlib.loads(out[start:])
                base["status"] = "pass"
                base["page_count"] = data.get("page_count")
                base["is_scan_document"] = data.get("is_scan_document")
                return base
            base["status"] = "fail"
            base["error"] = out[-200:]
            return base
        except Exception as e:  # noqa: BLE001
            base["status"] = "fail"
            base["error"] = str(e)
            return base


def _wps_text_semantic_check(docx_path: Path) -> dict[str, Any]:
    """用 WPS pdf2txt 提取消费端文本（真实消费者视角的语义）。

    wpscli 管道：word2pdf → pdf2txt；返回 text_preview + text_count。
    """
    import subprocess
    import tempfile

    wpscli = _find_wpscli()
    base = {"status": "unknown", "text_count": 0, "text_preview": ""}
    if not wpscli:
        return base
    with tempfile.TemporaryDirectory() as td:
        try:
            pdf = str(Path(td) / "out.pdf")
            r1 = subprocess.run(
                [wpscli, "word2pdf", str(docx_path), "--output", pdf, "--json"],
                capture_output=True, text=True, timeout=90,
            )
            if r1.returncode != 0:
                base["status"] = "fail"
                base["error"] = (r1.stdout + r1.stderr)[-200:]
                return base
            txt = str(Path(td) / "out.txt")
            r2 = subprocess.run(
                [wpscli, "pdf2txt", pdf, "--output", txt, "--json"],
                capture_output=True, text=True, timeout=90,
            )
            if r2.returncode != 0:
                base["status"] = "fail"
                base["error"] = (r2.stdout + r2.stderr)[-200:]
                return base
            content = Path(txt).read_text(encoding="utf-8", errors="replace")
            base["status"] = "pass" if content.strip() else "fail"
            base["text_count"] = len(content.split())
            base["text_preview"] = content[:120]
            return base
        except Exception as e:  # noqa: BLE001
            base["status"] = "fail"
            base["error"] = str(e)
            return base


def _find_dangling_rels(rels_xml: str, zip_names: set[str]) -> list[str]:
    """解析 rels 中 Relationship Target，返回不在 ZIP 内的悬空引用。"""
    dangling: list[str] = []
    for m in re.finditer(r'Target="([^"]+)"', rels_xml):
        target = m.group(1)
        if target.startswith(("http", "mailto")):
            continue
        resolved = target[1:] if target.startswith("/") else f"word/{target}"
        if resolved not in zip_names:
            dangling.append(target)
    return dangling


def _extract_semantic(doc_xml: str) -> dict[str, int | str]:
    """从 document.xml 提取语义模型（与 Dart 侧 semantic extractor 对齐）。"""
    paragraphs = len(re.findall(r"<w:p(?:\s|>)", doc_xml))
    headings = len(re.findall(r"Heading|heading", doc_xml))
    lists = len(re.findall(r"w:numPr", doc_xml))
    tables = len(re.findall(r"<w:tbl(?:\s|>)", doc_xml))
    formulas = len(re.findall(r"m:oMath", doc_xml))
    texts = re.findall(r"<w:t[^>]*>([^<]*)</w:t>", doc_xml)
    text_count = len(texts)
    joined = "|".join(texts)
    return {
        "paragraph_count": paragraphs,
        "heading_count": headings,
        "list_count": lists,
        "table_count": tables,
        "formula_count": formulas,
        "text_count": text_count,
        "text_preview": joined[:80],
    }
