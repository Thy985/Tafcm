r"""E8 Evaluator（Phase 3.11 RUN-014 / RUN-015 接线）——公式视觉语义验证主入口。

接收：Expected LaTeX + 截图（Observed）→ 视觉提取 → AST Diff →
输出严格 JSON（评审 Schema：status/expected_latex/observed_latex/
diff_details/error_type）。

vision_extract 为可插拔适配器（RUN-015 填实）：
- screenshot_path 提供时 → 真实视觉提取（e8_vision 后端链：
  pix2tex / paddleocr / tesseract，全部本地、无 API key）；
- 无截图时 known_latex 可作代理（E6 渲染公式 latex 已知——自洽验证，
  报告 §7 复跑命令路径）；
- 有截图但提取失败 → None → OCR_HALLUCINATION（不回退代理——
  防止「截图在但没看」被自洽 PASS 掩盖）。
"""

from __future__ import annotations

import json

from cli_anything.ffx.harness.e8_latex_ast import (
    ast_diff,
    classify_error,
    parse_latex,
)
from cli_anything.ffx.harness.e8_vision import extract_latex

_PARSING_ERROR = "PARSING_ERROR"
_OCR_HALLUCINATION = "OCR_HALLUCINATION"


def vision_extract(
    screenshot_path: str | None = None,
    known_latex: str | None = None,
) -> str | None:
    """视觉提取 LaTeX（适配器接口）。

    语义（RUN-015 收紧）：
    - screenshot_path 提供时：真实视觉提取（像素为真相源，后端链见
      e8_vision）。提取失败返回 None → OCR_HALLUCINATION——不回退
      known_latex 代理，保证 Observed 侧始终来自截图像素。
    - 无截图时：known_latex 提供则作为代理返回（自洽验证）。
    """
    if screenshot_path:
        return extract_latex(screenshot_path)
    if known_latex is not None:
        return known_latex
    return None


def evaluate(
    expected_latex: str,
    screenshot_path: str | None = None,
    known_latex: str | None = None,
    observed_latex: str | None = None,
) -> str:
    """E8 Evaluator 主入口 → 严格 JSON 字符串（评审 Schema）。

    observed_latex：可选直传——调用方已自行完成视觉提取（如
    FormulaAdapter.visual_check 需要 provenance 时）传入以避免二次
    推理；缺省走 vision_extract。
    """
    # 1. 解析基准（Expected AST）
    try:
        expected_ast = parse_latex(expected_latex)
    except ValueError as e:
        return json.dumps(
            {
                "status": "ERROR",
                "expected_latex": expected_latex,
                "observed_latex": None,
                "diff_details": [f"Expected LaTeX parse failed: {e}"],
                "error_type": _PARSING_ERROR,
            },
            ensure_ascii=False,
        )

    # 2. 视觉提取（Observed LaTeX）
    observed = (
        observed_latex
        if observed_latex is not None
        else vision_extract(screenshot_path, known_latex)
    )
    if observed is None:
        return json.dumps(
            {
                "status": "ERROR",
                "expected_latex": expected_latex,
                "observed_latex": None,
                "diff_details": ["Vision model failed to extract valid LaTeX"],
                "error_type": _OCR_HALLUCINATION,
            },
            ensure_ascii=False,
        )

    # 3. 结构转换（Observed AST）
    try:
        observed_ast = parse_latex(observed)
    except ValueError as e:
        return json.dumps(
            {
                "status": "ERROR",
                "expected_latex": expected_latex,
                "observed_latex": observed,
                "diff_details": [f"Observed LaTeX parse failed: {e}"],
                "error_type": _PARSING_ERROR,
            },
            ensure_ascii=False,
        )

    # 4. 语义对齐（AST Diff）
    diffs = ast_diff(expected_ast, observed_ast)

    # 5. 输出结论（严格 JSON）
    return json.dumps(
        {
            "status": "PASS" if not diffs else "FAIL",
            "expected_latex": expected_latex,
            "observed_latex": observed,
            "diff_details": diffs,
            "error_type": classify_error(diffs),
        },
        ensure_ascii=False,
    )
