r"""E8 Evaluator（Phase 3.11 RUN-014）——公式视觉语义验证主入口。

接收：Expected LaTeX + 截图（Observed）→ 视觉提取 → AST Diff →
输出严格 JSON（评审 Schema：status/expected_latex/observed_latex/
diff_details/error_type）。

vision_extract 为可插拔适配器：
- known_latex 提供时（自洽/代理：E6 模拟器渲染公式的 latex 已知）直接返回；
- 否则尝试 OCR（tesseract 等，当前环境未接入视觉模型 → None → OCR_HALLUCINATION）。
"""

from __future__ import annotations

import json

from cli_anything.ffx.harness.e8_latex_ast import (
    ast_diff,
    classify_error,
    parse_latex,
)

_PARSING_ERROR = "PARSING_ERROR"
_OCR_HALLUCINATION = "OCR_HALLUCINATION"


def vision_extract(
    screenshot_path: str | None = None,
    known_latex: str | None = None,
) -> str | None:
    """视觉提取 LaTeX（适配器接口）。

    当前环境无视觉模型 API：known_latex 提供时作为视觉提取的代理
    （E6 模拟器渲染公式的 latex 已知——自洽验证）；否则尝试 OCR，
    不可用则返回 None（→ OCR_HALLUCINATION）。
    """
    if known_latex is not None:
        return known_latex
    if screenshot_path:
        # OCR 留接口：未来接入视觉模型（如 tesseract 公式识别 / vision API）
        pass
    return None


def evaluate(
    expected_latex: str,
    screenshot_path: str | None = None,
    known_latex: str | None = None,
) -> str:
    """E8 Evaluator 主入口 → 严格 JSON 字符串（评审 Schema）。"""
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
    observed = vision_extract(screenshot_path, known_latex)
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
