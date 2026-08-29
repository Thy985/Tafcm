"""Consumer 统一归一化输出（ADR-0030 §3.4）。

consumers/ 是**薄封装**：调用真实外部 CLI（wpscli / officecli / pdfinfo），
输出统一归一化为 {exit_code, summary, issues}，**不重实现** WPS/Office/PDF 引擎。
"""
from __future__ import annotations

import subprocess
from dataclasses import dataclass, field
from typing import Any


@dataclass
class ConsumerResult:
    """归一化消费端结果（所有 consumer 统一形状）。

    - exit_code：CLI 退出码（127 = 工具缺失，非产品失败）
    - summary：一行人类可读摘要
    - issues：结构化问题列表（[{issue, detail}]，空 = 无问题）
    - raw：原始 stdout/stderr 尾部（诊断用，不直接展示给用户）
    """

    exit_code: int
    summary: str
    issues: list[dict[str, Any]] = field(default_factory=list)
    raw: str = ""


def run_cmd(
    cmd: list[str],
    timeout: int = 90,
    cwd: str | None = None,
) -> tuple[int, str, str]:
    """跑外部 CLI，返回 (exit_code, stdout, stderr)。捕获异常 → 127。"""
    try:
        r = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=cwd,
        )
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return 127, "", f"timeout after {timeout}s: {' '.join(cmd[:3])}..."
    except Exception as e:  # noqa: BLE001
        return 127, "", f"run error: {e}"
