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

    return result


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
