r"""E8 Vision Backends — 截图 → LaTeX 真实视觉提取（Phase 3.11 RUN-015）。

vision_extract 的可插拔后端层（全部本地推理，无 API key、无硬编码密钥）：

  pix2tex     LaTeX-OCR（torch，公式结构感知——自动链首选）
  paddleocr   PaddleOCR 公式识别管线（安装 paddleocr 后可用；本环境未安装，
              分支按官方 3.x 用法编写且未经实测——异常由后端链捕获降级）
  tesseract   pytesseract + 公式预处理（线性文本兜底，结构信息有限——
              frac/sup 会被拍平，AST Diff 会如实报告结构差异）

后端选择：
  - 环境变量 FFX_E8_VISION_BACKEND 强制指定（支持逗号链：`pix2tex,tesseract`；
    `none` 表示禁用真实提取）
  - 未设置 → 按上表顺序自动探测（import 失败 / 执行异常 → 记日志跳下一个）
所有后端失败/不可用 → 返回 None（调用方判 OCR_HALLUCINATION），本层不抛异常。

注意（pix2tex 集成细节，源码 cli.py 实测）：
  - LatexOCR.__init__ 会把 root logger 级别设为 FATAL——初始化后恢复，
    避免 FFX 进程内其余 logging 被静音（项目规则：可观测性走 logging）
  - torch>=2.6 的 torch.load 默认 weights_only=True 会拒载 pix2tex 的
    本地 checkpoint——仅在本初始化窗口内临时 shim 关闭（本地受信权重，
    加载完即还原 torch.load）
"""

from __future__ import annotations

import logging
import os
import re
from pathlib import Path
from typing import Callable

logger = logging.getLogger(__name__)

Extractor = Callable[[str], str]

_FORCED_ENV = "FFX_E8_VISION_BACKEND"
_AUTO_ORDER: tuple[str, ...] = ("pix2tex", "paddleocr", "tesseract")

# OCR 输出清理：换行/制表/多空白折叠为单空格
_OCR_NOISE = re.compile(r"[\r\n\t]+|\s{2,}")


# ---------------------------------------------------------------------------
# 后端实现（全部延迟导入：未安装的依赖在 import 时抛错 → 后端链跳过）
# ---------------------------------------------------------------------------

_pix2tex_model: object | None = None  # lazy singleton（权重下载一次 + 秒级加载）


def _init_pix2tex(latex_ocr_cls: type) -> object:
    """初始化 pix2tex 模型：恢复被静音的 root logger + torch.load shim。"""
    root = logging.getLogger()
    prev_level = root.level
    try:
        try:
            return latex_ocr_cls()
        except Exception:
            # torch>=2.6：weights_only 默认 True 拒载 pix2tex 本地 checkpoint
            # ——仅在本初始化窗口内临时关闭（本地受信权重），加载完即还原。
            import torch

            orig_load = torch.load

            def _load_trusted(*args: object, **kwargs: object) -> object:
                kwargs.setdefault("weights_only", False)
                return orig_load(*args, **kwargs)  # type: ignore[arg-type]

            torch.load = _load_trusted  # type: ignore[assignment]
            try:
                return latex_ocr_cls()
            finally:
                torch.load = orig_load  # type: ignore[assignment]
    finally:
        # pix2tex cli.py __init__ 将 root logger 设为 FATAL——还原，
        # 避免 FFX 进程内其余 logging 被静音。
        root.setLevel(prev_level)


def _load_preprocessed(screenshot_path: str):
    """加载截图并做白边自动裁剪（纯规范化，不注入信息）。

    E6 截图的 RepaintBoundary 可能是大画布（displayMode 公式横向撑满），
    字形只占中间一小块——OCR 模型在小字形上误读率显著升高（RUN-015 实测
    \frac{a}{b} 被读成 \frac{Q}{\bar J}）。裁掉纯白边距让字形占满画布；
    深色背景自动反转判断。
    """
    from PIL import Image, ImageOps

    img = Image.open(screenshot_path)
    gray = img.convert("L")
    # 深色背景（均值偏暗）先反转，统一为「浅底深字」再找内容边界
    hist = gray.histogram()
    total = sum(hist) or 1
    mean = sum(i * c for i, c in enumerate(hist)) / total
    if mean < 128:
        gray = ImageOps.invert(gray)
    # 内容 = 非纯白像素；getbbox 返回非零（内容）边界
    bbox = gray.point(lambda p: 255 if p < 250 else 0).getbbox()
    if bbox:
        pad = 8
        left = max(0, bbox[0] - pad)
        top = max(0, bbox[1] - pad)
        right = min(img.width, bbox[2] + pad)
        bottom = min(img.height, bbox[3] + pad)
        if right - left > 2 and bottom - top > 2:
            img = img.crop((left, top, right, bottom))
    return img


def _extract_pix2tex(screenshot_path: str) -> str:
    """LaTeX-OCR（pix2tex）：公式结构感知的图像 → LaTeX。"""
    global _pix2tex_model
    from pix2tex.cli import LatexOCR  # 未安装 → ImportError → 后端链跳过

    if _pix2tex_model is None:
        _pix2tex_model = _init_pix2tex(LatexOCR)
        # temperature 调低至近 0：提取确定化（同截图 → 同 LaTeX），验证门
        # 可复现；默认 0.33 的采样随机性会让同一证据产出不同判定。
        setattr(_pix2tex_model.args, "temperature", 0.01 + 1e-8)
        logger.info("e8_vision: pix2tex model initialized")
    return str(_pix2tex_model(_load_preprocessed(screenshot_path)))


_paddle_pipeline: object | None = None


def _extract_paddleocr(screenshot_path: str) -> str:
    """PaddleOCR 公式识别（PP-StructureV3 管线，PaddleOCR >= 3.0）。

    ⚠️ 本环境未安装 paddleocr——此分支按官方 3.x 用法编写、未经本地实测；
    结果字段按 dict / 对象两种形态 duck-typing 兼容，识别不到公式区域时
    抛 RuntimeError，由后端链记日志降级（不会静默产出错误结果）。
    """
    global _paddle_pipeline
    from paddleocr import PPStructureV3  # 未安装 → ImportError → 跳过

    if _paddle_pipeline is None:
        _paddle_pipeline = PPStructureV3()
    results = _paddle_pipeline.predict(screenshot_path)
    chunks: list[str] = []
    for res in results:
        if isinstance(res, dict):
            fields = [res.get("formula_latex"), res.get("formula_reses")]
        else:
            fields = [getattr(res, "formula_latex", None)]
        for field in fields:
            if isinstance(field, str) and field.strip():
                chunks.append(field.strip())
            elif isinstance(field, (list, tuple)):
                chunks.extend(str(x) for x in field if str(x).strip())
    if not chunks:
        raise RuntimeError("paddleocr: no formula region recognized")
    return " ".join(chunks)


def _extract_tesseract(screenshot_path: str) -> str:
    """tesseract OCR + 公式预处理（线性文本兜底）。

    结构信息有限（frac/sup 被拍平为线性文本）——仅作为前两个后端均不可用
    时的降级；AST Diff 会如实报告结构差异（不因 OCR 能力弱而伪造 PASS）。
    """
    import pytesseract  # 未安装 → ImportError → 跳过
    from PIL import ImageOps

    pytesseract.get_tesseract_version()  # 二进制缺失 → TesseractNotFoundError
    img = _load_preprocessed(screenshot_path).convert("L")
    # 公式预处理：放大 2x + 自动对比度 + 二值化（浅底深字）
    img = ImageOps.autocontrast(img)
    img = img.resize((img.width * 2, img.height * 2))
    img = img.point(lambda p: 255 if p > 160 else 0)
    return pytesseract.image_to_string(img, config="--psm 6")


_BACKENDS: dict[str, Extractor] = {
    "pix2tex": _extract_pix2tex,
    "paddleocr": _extract_paddleocr,
    "tesseract": _extract_tesseract,
}


# ---------------------------------------------------------------------------
# 后端链编排
# ---------------------------------------------------------------------------

def register_backend(name: str, fn: Extractor | None) -> None:
    """注册/注销后端（测试与工具注入点；fn=None 注销）。

    自定义后端不在 _AUTO_ORDER 中，需经 FFX_E8_VISION_BACKEND 指定启用。
    """
    if fn is None:
        _BACKENDS.pop(name, None)
    else:
        _BACKENDS[name] = fn


def backend_chain() -> list[str]:
    """当前生效的后端顺序（env 强制 > 自动探测；none → 空链）。

    自动模式：_AUTO_ORDER 中已注册者保持声明优先级在前，注册表中的
    其余自定义/注入后端（如测试 fake）按注册表顺序追加在后。
    """
    forced = os.environ.get(_FORCED_ENV, "").strip().lower()
    if forced == "none":
        return []
    if forced:
        return [n.strip() for n in forced.split(",") if n.strip()]
    auto = [n for n in _AUTO_ORDER if n in _BACKENDS]
    extra = [n for n in _BACKENDS if n not in _AUTO_ORDER]
    return auto + extra


def _normalize_ocr_latex(raw: str | None) -> str | None:
    """OCR 输出清理：去 $ 包裹、折叠空白；空结果归一为 None。"""
    if raw is None:
        return None
    latex = raw.strip()
    if len(latex) >= 2 and latex.startswith("$") and latex.endswith("$"):
        latex = latex[1:-1].strip()
    latex = _OCR_NOISE.sub(" ", latex).strip()
    return latex or None


def extract_with_provenance(
    screenshot_path: str | None,
) -> tuple[str | None, str | None]:
    """截图 → (LaTeX, 后端名)。全链失败返回 (None, None)，不抛异常。"""
    if not screenshot_path:
        return None, None
    path = Path(screenshot_path)
    if not path.is_file():
        logger.warning("e8_vision: screenshot not found: %s", screenshot_path)
        return None, None
    for name in backend_chain():
        fn = _BACKENDS.get(name)
        if fn is None:
            logger.warning("e8_vision: unknown backend requested: %s", name)
            continue
        try:
            latex = _normalize_ocr_latex(fn(str(path)))
        except Exception as e:  # noqa: BLE001 — 后端隔离：失败降级不中断
            logger.warning(
                "e8_vision: backend %s failed: %s: %s", name, type(e).__name__, e
            )
            continue
        if latex:
            logger.info("e8_vision: %s extracted: %s", name, latex)
            return latex, name
    logger.warning("e8_vision: no backend produced LaTeX for %s", screenshot_path)
    return None, None


def extract_latex(screenshot_path: str | None) -> str | None:
    """截图 → LaTeX（无 provenance 的便捷入口）。"""
    return extract_with_provenance(screenshot_path)[0]
