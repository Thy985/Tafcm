r"""E8 VLM 后端——视觉语言模型从截图提取公式结构（RUN-016）。

与 e8_vision（OCR → LaTeX 字符串）不同，本模块走结构化路线：
模型只负责「从像素描述公式结构」，强制输出 e8_structure 约定的 JSON
schema（confidence / issues / structure），判定权在 evaluator。

后端：
  qwen2vl-local  本地 Qwen2-VL-2B-Instruct（transformers，CPU 可推理）
  none           禁用（视觉结构模式不可用）

环境变量：
  FFX_E8_VLM_BACKEND   强制后端（默认 auto：有 qwen2vl 用之）
  FFX_E8_VLM_CONF_MIN  confidence 阈值（默认 0.6，见 e8_structure）

模型集成细节：
  - 懒加载单例；加载日志走 logging
  - greedy 解码（do_sample=False）：同一截图 → 同一描述，验证可复现
  - 模型输出可能带 markdown 围栏/前导文字——提取首个平衡 JSON 对象
"""

from __future__ import annotations

import json
import logging
import os

logger = logging.getLogger(__name__)

_VLM_BACKEND_ENV = "FFX_E8_VLM_BACKEND"

_qwen2vl_model = None
_qwen2vl_processor = None

_PROMPT_TEMPLATE = (
    "You are a mathematical formula structure extractor. Look at the "
    "rendered formula in the image and describe EXACTLY what you see as "
    "strict JSON. Describe only the symbols and structure that are "
    "actually visible - never guess what the formula should be. If part "
    "of the image is cut off, blurry or unreadable, say so in \"issues\" "
    "and lower \"confidence\".\n"
    "Output ONLY valid JSON (no markdown fences, no explanation) matching:\n"
    '{"confidence": <float 0..1, how clearly you can read the formula>, '
    '"issues": ["<problems, e.g. bottom edge cut off>"], "structure": <node>}\n'
    "node is one of:\n"
    '{"type":"symbol","value":"<single character like a, b, +, =, or a '
    'latex command like \\\\alpha>"}\n'
    '{"type":"sequence","items":[node, ...]}\n'
    '{"type":"fraction","numerator":node,"denominator":node}\n'
    '{"type":"superscript","base":node,"exponent":node}  (base may be '
    "omitted when it is the preceding symbol)\n"
    '{"type":"subscript","base":node,"index":node}\n'
    '{"type":"root","index":node|null,"radicand":node}\n'
    '{"type":"matrix","environment":"pmatrix|bmatrix|matrix","rows":'
    "[[node, ...], ...]}\n"
    "Example E=mc^2 -> {\"type\":\"sequence\",\"items\":[{\"type\":"
    '"symbol","value":"E"},{"type":"symbol","value":"="},{"type":'
    '"symbol","value":"m"},{"type":"symbol","value":"c"},{"type":'
    '"superscript","base":{"type":"symbol","value":"c"},"exponent":'
    '{"type":"symbol","value":"2"}}]}\n'
    "Example a over b -> {\"type\":\"fraction\",\"numerator\":{\"type\":"
    '"symbol","value":"a"},"denominator":{"type":"symbol","value":"b"}}'
)


def backend_chain() -> list[str]:
    """可用 VLM 后端链（FFX_E8_VLM_BACKEND=none 禁用）。"""
    forced = os.environ.get(_VLM_BACKEND_ENV, "").strip().lower()
    if forced == "none":
        return []
    if forced:
        return [b.strip() for b in forced.split(",") if b.strip()]
    return ["qwen2vl-local"]


def _extract_json_object(text: str):
    """从模型输出提取首个平衡的 JSON 对象（容 markdown 围栏/前导文字）。"""
    start = text.find("{")
    if start < 0:
        return None
    depth = 0
    in_str = False
    escape = False
    for i in range(start, len(text)):
        ch = text[i]
        if in_str:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(text[start : i + 1])
                except json.JSONDecodeError:
                    return None
    return None


def _init_qwen2vl():
    """懒加载 Qwen2-VL-2B（transformers）。失败抛异常由调用方降级。"""
    import torch
    from transformers import AutoProcessor, Qwen2VLForConditionalGeneration

    model_id = "Qwen/Qwen2-VL-2B-Instruct"
    logger.info("e8_vlm: loading %s (cpu)", model_id)
    model = Qwen2VLForConditionalGeneration.from_pretrained(
        model_id, torch_dtype=torch.float32
    )
    model.eval()
    processor = AutoProcessor.from_pretrained(
        model_id, min_pixels=256 * 28 * 28, max_pixels=1280 * 28 * 28
    )
    return model, processor


def describe_structure(screenshot_path: str):
    """截图 → 结构化描述 dict（confidence/issues/structure/backend）。

    任何失败都返回 {"confidence": 0, "issues": [...], "structure": None,
    "backend": ...}，由 evaluator 判 INCONCLUSIVE——本模块不抛异常。
    """
    global _qwen2vl_model, _qwen2vl_processor
    from PIL import Image

    try:
        if _qwen2vl_model is None:
            _qwen2vl_model, _qwen2vl_processor = _init_qwen2vl()
            logger.info("e8_vlm: qwen2vl model ready")
        image = Image.open(screenshot_path).convert("RGB")
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "image", "image": "screenshot"},
                    {"type": "text", "text": _PROMPT_TEMPLATE},
                ],
            }
        ]
        prompt = _qwen2vl_processor.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True
        )
        inputs = _qwen2vl_processor(
            text=[prompt], images=[image], return_tensors="pt"
        )
        import torch

        with torch.no_grad():
            generated = _qwen2vl_model.generate(
                **inputs, max_new_tokens=512, do_sample=False
            )
        trimmed = [
            out_ids[len(in_ids) :]
            for in_ids, out_ids in zip(inputs.input_ids, generated)
        ]
        text = _qwen2vl_processor.batch_decode(
            trimmed, skip_special_tokens=True
        )[0]
        parsed = _extract_json_object(text)
        if not isinstance(parsed, dict):
            logger.warning(
                "e8_vlm: non-JSON model output for %s: %.200s",
                screenshot_path,
                text,
            )
            return {
                "confidence": 0,
                "issues": ["model output was not valid JSON"],
                "structure": None,
                "backend": "qwen2vl-local",
            }
        parsed.setdefault("confidence", 0)
        parsed.setdefault("issues", [])
        parsed.setdefault("structure", None)
        parsed["backend"] = "qwen2vl-local"
        return parsed
    except Exception as e:  # noqa: BLE001——视觉失败必须降级为 INCONCLUSIVE 而非崩溃
        logger.warning("e8_vlm: extraction failed for %s: %s", screenshot_path, e)
        return {
            "confidence": 0,
            "issues": [f"vision backend error: {e}"],
            "structure": None,
            "backend": "qwen2vl-local",
        }
