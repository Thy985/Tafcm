"""wpscli 消费端薄封装（ADR-0030 §3.4）。

包装 WPS 命令行工具：word2pdf 转换 + pdfinfo 元数据（消费端分页/扫描证据）。
探测路径复用 docx_qa._find_wpscli（机器特异路径的既有单一真相）。
"""
from __future__ import annotations

from pathlib import Path

from .base import ConsumerResult, run_cmd


def find() -> str | None:
    """探测 wpscli.exe（复用 docx_qa 的既有路径探测）。"""
    from cli_anything.ffx.core.docx_qa import _find_wpscli

    return _find_wpscli()


def word2pdf(docx: str | Path, out_pdf: str | Path, timeout: int = 90) -> ConsumerResult:
    """wpscli word2pdf：真实 Office 兼容转换（消费端打开/转换证据）。

    产物 out_pdf 由调用方收集；本函数只返回归一化结果。
    """
    wpscli = find()
    if not wpscli:
        return ConsumerResult(
            exit_code=127,
            summary="wpscli not installed (consumer evidence gap — ENV_MISSING)",
            issues=[{"issue": "wpscli_missing", "detail": "wpscli not found"}],
        )
    rc, out, err = run_cmd(
        [wpscli, "word2pdf", str(docx), "--output", str(out_pdf), "--json"],
        timeout=timeout,
    )
    if rc == 0 and Path(out_pdf).is_file():
        return ConsumerResult(
            exit_code=0,
            summary=f"wps word2pdf ok → {Path(out_pdf).name}",
            raw=(out + err)[-300:],
        )
    return ConsumerResult(
        exit_code=rc,
        summary=f"wps word2pdf failed (rc={rc})",
        issues=[{"issue": "word2pdf_failed", "detail": (out + err)[-300:]}],
        raw=(out + err)[-500:],
    )


def pdfinfo(pdf: str | Path, timeout: int = 60) -> ConsumerResult:
    """wpscli pdfinfo：消费端 PDF 元数据（页数 / 扫描提示）。

    输出 JSON 行形如 {"type":"completed","page_count":1,...}。
    """
    wpscli = find()
    if not wpscli:
        return ConsumerResult(
            exit_code=127,
            summary="wpscli not installed (ENV_MISSING)",
            issues=[{"issue": "wpscli_missing", "detail": "wpscli not found"}],
        )
    rc, out, err = run_cmd(
        [wpscli, "pdfinfo", str(pdf), "--json"],
        timeout=timeout,
    )
    if rc != 0:
        return ConsumerResult(
            exit_code=rc,
            summary=f"wps pdfinfo failed (rc={rc})",
            issues=[{"issue": "pdfinfo_failed", "detail": (out + err)[-300:]}],
            raw=(out + err)[-500:],
        )
    return ConsumerResult(
        exit_code=0,
        summary=f"wps pdfinfo ok ({Path(pdf).name})",
        raw=(out + err)[-300:],
    )
