r"""Visual Receiver — FFX verify 视觉检查请求接收器（E8 接线层）。

接收 visual check 请求（evidence_profile + formula + 截图路径）→
调用 E8 Evaluator（e8_evaluator.evaluate）→ 返回严格 JSON 结果。

RUN-015：call_e8_evaluator 由模拟 result 替换为真实调用——
evaluate(expected_latex, screenshot_path) → 真实视觉提取（e8_vision
后端链）→ AST Diff → {status, expected_latex, observed_latex,
diff_details, error_type}。
"""

from __future__ import annotations

import json
import logging
from typing import Any, Dict

logger = logging.getLogger(__name__)


def visual_check_handler(
    evidence_profile: Dict[str, Any],
    formula_content: str,
    visual_check: bool,
    target_visual: str,
) -> Dict[str, Any]:
    """处理 FFX verify 的视觉检查请求。

    - visual_check=False → 直接返回禁用结果（不调用 E8）
    - evidence_profile 缺必需字段 → error（visual_checker / visual_check_level）
    - 成功 → result.details = E8 严格 JSON dict
    """
    if not visual_check:
        return {
            "status": "success",
            "result": {
                "visual_check": False,
                "message": "视觉检查已禁用",
            },
        }

    required_fields = ["visual_checker", "visual_check_level"]
    for field in required_fields:
        if field not in evidence_profile:
            return {
                "status": "error",
                "message": f"缺少必需字段: {field}",
            }

    try:
        result = call_e8_evaluator(formula_content, target_visual)
        return {
            "status": "success",
            "result": {
                "visual_check": True,
                "checker": evidence_profile["visual_checker"],
                "check_level": evidence_profile["visual_check_level"],
                "details": result,
            },
        }
    except Exception as e:  # noqa: BLE001 — 请求层兜底：错误打包返回不外抛
        logger.warning("visual_receiver: e8 evaluate failed: %s", e)
        return {
            "status": "error",
            "message": f"视觉检查失败: {e}",
        }


def call_e8_evaluator(formula_content: str, target_visual: str) -> Dict[str, Any]:
    """调用 E8 Evaluator（真实视觉语义验证，非模拟）→ 严格 JSON dict。"""
    from .e8_evaluator import evaluate  # 延迟导入：避免包初始化顺序问题

    raw = evaluate(expected_latex=formula_content, screenshot_path=target_visual)
    return json.loads(raw)
