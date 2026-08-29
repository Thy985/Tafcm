"""pdfinfo 消费端薄封装（ADR-0030 §3.4）。

包装 PDF 元数据工具：优先 poppler pdfinfo（shutil.which），
回退 wpscli pdfinfo（WPS 自带）。只读元数据，不重实现 PDF 引擎。
"""
from __future__ import annotations

import shutil
from pathlib import Path

from .base import ConsumerResult, run_cmd


def find() -> str | None:
    """探测 pdfinfo：poppler pdfinfo 优先，回退 wpscli pdfinfo。"""
    poppler = shutil.which("pdfinfo") or shutil.which("pdfinfo.exe")
    if poppler:
        return poppler
    from cli_anything.ffx.core.docx_qa import _find_wpscli

    wpscli = _find_wpscli()
    if wpscli:
        return wpscli  # wpscli 自带 pdfinfo 子命令
    return None


def info(pdf: str | Path, timeout: int = 60) -> ConsumerResult:
    """读 PDF 元数据（页数 / 扫描提示）。poppler 或 wpscli 任一路径。"""
    tool = find()
    if not tool:
        return ConsumerResult(
            exit_code=127,
            summary="pdfinfo not available (neither poppler pdfinfo nor wpscli)",
            issues=[{"issue": "pdfinfo_missing", "detail": "no pdfinfo tool found"}],
        )
    is_wps = tool.lower().endswith("wpscli.exe") or "wps" in tool.lower()
    cmd = [tool, "pdfinfo", str(pdf), "--json"] if is_wps else [tool, str(pdf)]
    rc, out, err = run_cmd(cmd, timeout=timeout)
    if rc != 0:
        return ConsumerResult(
            exit_code=rc,
            summary=f"pdfinfo failed (rc={rc})",
            issues=[{"issue": "pdfinfo_failed", "detail": (out + err)[-300:]}],
            raw=(out + err)[-500:],
        )
    return ConsumerResult(
        exit_code=0,
        summary=f"pdfinfo ok ({Path(pdf).name})",
        raw=(out + err)[-300:],
    )
