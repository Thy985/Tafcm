r"""E8 Structure Mode（RUN-016）——视觉模型结构化描述 → 确定性三态判定。

分工边界（评审定调）：视觉模型只负责「从像素描述公式结构」（强制 JSON
schema 输出），不判定产品是否通过；PASS / FAIL / INCONCLUSIVE 由本模块对
observed_structure vs Expected AST 做确定性比对（ast_diff）得出。

三态语义：
  PASS          结构一致（diff 为空 + confidence 达阈值 + 无截断类 issue）
  FAIL          语义错误——结构被高置信度地确证为不一致
  INCONCLUSIVE  视觉提取失败——描述缺失/不可解析 / confidence 低于阈值 /
                模型报告截断、模糊等图像完整性问题（此时即使 diff 恰好为空
                也不得 PASS）

模型输出 schema（coerce 前接受宽松别名；只描述所见，不给结论）：
{
  "confidence": 0.97,
  "issues": ["bottom edge truncated"],   // 无问题则空数组
  "structure": <node>
}
node :=
  {"type":"symbol","value":"a"}
  | {"type":"sequence","items":[node,...]}
  | {"type":"fraction","numerator":n,"denominator":n}
  | {"type":"superscript","base":n,"exponent":n}     // base 可省略
  | {"type":"subscript","base":n,"index":n}          // base 可省略
  | {"type":"root","radicand":n,"index":n|null}
  | {"type":"matrix","environment":"pmatrix","rows":[[n,...],...]}

coerce 目标词表 = e8_latex_ast 的节点词表（sym/seq/sup/sub/frac/root/
env_begin/env_end）。sup/sub 按 parse_latex 的位置约定展开：
superscript{base,exp} → [base 节点, {"type":"sup","value":exp}]；
矩阵展开为 [env_begin{env}, cell(& 分隔), ..., env_end{env}]，与
parse_latex(\begin{pmatrix}..&..\\..\end{pmatrix}) 经 canonicalize_expected
规整后的形状逐点对齐。
"""

from __future__ import annotations

import json
import os

from cli_anything.ffx.harness.e8_latex_ast import (
    ast_diff,
    canonicalize_expected,
    classify_error,
    parse_latex,
)

_CONF_THRESHOLD_DEFAULT = 0.6
_CONF_THRESHOLD_ENV = "FFX_E8_VLM_CONF_MIN"
# 图像完整性类 issue 关键词：命中则视为视觉提取不可信（→ INCONCLUSIVE）
_BLOCKING_ISSUE_KEYWORDS = (
    "cut",
    "truncat",
    "crop",
    "clip",
    "blur",
    "unreadable",
    "illegible",
    "partial",
    "out of frame",
    "cut off",
)

_STATUS_PASS = "PASS"
_STATUS_FAIL = "FAIL"
_STATUS_INCONCLUSIVE = "INCONCLUSIVE"
_ERROR_NONE = "NONE"
_ERROR_VISION_FAILED = "VISION_EXTRACTION_FAILED"
_ERROR_PARSING = "PARSING_ERROR"


class CoerceError(ValueError):
    """视觉模型的结构化输出无法映射到 AST 词表。"""


def _conf_threshold() -> float:
    raw = os.environ.get(_CONF_THRESHOLD_ENV, "").strip()
    if not raw:
        return _CONF_THRESHOLD_DEFAULT
    try:
        return min(1.0, max(0.0, float(raw)))
    except ValueError:
        return _CONF_THRESHOLD_DEFAULT


def _is_blocking_issue(issue: str) -> bool:
    low = issue.lower()
    return any(k in low for k in _BLOCKING_ISSUE_KEYWORDS)


# ---------------------------------------------------------------------------
# coerce：模型宽松 JSON → e8_latex_ast 词表
# ---------------------------------------------------------------------------

_FRACTION_NUM_KEYS = ("numerator", "num", "top")
_FRACTION_DEN_KEYS = ("denominator", "den", "bottom")


def _coerce_symbol(obj: dict) -> dict:
    value = obj.get("value")
    if value is None:
        raise CoerceError("symbol node missing 'value'")
    if isinstance(value, bool):
        raise CoerceError("symbol value must be a character/command, got bool")
    if isinstance(value, (int, float)):
        value = str(value)
    if not isinstance(value, str):
        raise CoerceError(f"symbol value must be a string, got {type(value).__name__}")
    return {"type": "sym", "value": value.strip()}


def _first_key(obj: dict, keys: tuple[str, ...]):
    for k in keys:
        if k in obj:
            return obj[k]
    return None


def _coerce_script(obj: dict, kind: str, script_keys: tuple[str, ...]) -> list[dict]:
    """superscript/subscript → [base?, script 节点]（位置约定展开）。"""
    script_value = _first_key(obj, script_keys)
    if script_value is None:
        raise CoerceError(f"{obj.get('type')} node missing {script_keys[0]}")
    script_node: dict = {"type": kind, "value": _coerce(script_value)}
    base = obj.get("base")
    if base is None:
        return [script_node]
    expanded = _coerce(base)
    # base 可能本身展开为多个节点（如嵌套 script）——保持顺序整体前置
    nodes = expanded if isinstance(expanded, list) else [expanded]
    return [*nodes, script_node]


def _coerce_matrix(obj: dict) -> dict:
    env = str(obj.get("environment") or obj.get("env") or "matrix").strip()
    rows = obj.get("rows")
    if not isinstance(rows, list):
        raise CoerceError("matrix node requires 'rows' as list of rows")
    items: list[dict] = [{"type": "env_begin", "env": env}]
    for row in rows:
        if not isinstance(row, list):
            raise CoerceError("matrix rows must be lists of cells")
        for col_i, cell in enumerate(row):
            if col_i > 0:
                # 列分隔符只在行内；行边界两侧都不保留标记
                # （expected 侧由 canonicalize_expected 剥掉 \\ 产物）
                items.append({"type": "sym", "value": "&"})
            coerced = _coerce(cell)
            items.extend(coerced if isinstance(coerced, list) else [coerced])
    items.append({"type": "env_end", "env": env})
    return {"type": "seq", "items": items}


def _nodes_equal(a: dict, b: dict) -> bool:
    """结构相等（镜像 ast_diff.node_eq 的比较语义）。"""
    if a.get("type") != b.get("type"):
        return False
    t = a.get("type")
    if t == "frac":
        return _nodes_equal(a.get("num", {}), b.get("num", {})) and _nodes_equal(
            a.get("den", {}), b.get("den", {})
        )
    if t in ("sup", "sub"):
        return _nodes_equal(a.get("value", {}), b.get("value", {}))
    if t == "root":
        return _nodes_equal(a.get("index") or {}, b.get("index") or {}) and (
            _nodes_equal(a.get("radicand", {}), b.get("radicand", {}))
        )
    if t == "seq":
        ia, ib = a.get("items", []), b.get("items", [])
        return len(ia) == len(ib) and all(
            _nodes_equal(x, y) for x, y in zip(ia, ib)
        )
    if t in ("env_begin", "env_end"):
        return a.get("env") == b.get("env")
    return a.get("value") == b.get("value")


def _coerce(obj) -> dict | list[dict]:
    """单节点 coerce；sup/sub 展开时返回节点列表（调用方拍平）。"""
    if isinstance(obj, str):
        return _coerce_symbol({"value": obj})
    if isinstance(obj, (int, float)) and not isinstance(obj, bool):
        return _coerce_symbol({"value": obj})
    if not isinstance(obj, dict):
        raise CoerceError(f"structure node must be object/string, got {type(obj).__name__}")
    ntype = str(obj.get("type") or "").strip().lower()
    if ntype in ("symbol", "sym", "char"):
        return _coerce_symbol(obj)
    if ntype in ("sequence", "seq"):
        raw_items = obj.get("items")
        if not isinstance(raw_items, list):
            raise CoerceError("sequence node requires 'items'")
        items: list[dict] = []
        # 最近一个「非脚标」已发射节点：模型描述 x_1^2 常把两个脚标都挂在
        # 同一 base 上（seq[x, sub{base:x}, sup{base:x}]），而 parse_latex
        # 的位置约定是 seq[x, sub{1}, sup{2}]——base 与已有元素重复时不再发射
        last_base_candidate: dict | None = None
        for item in raw_items:
            coerced = _coerce(item)
            nodes = coerced if isinstance(coerced, list) else [coerced]
            if (
                len(nodes) > 1
                and last_base_candidate is not None
                and _nodes_equal(nodes[0], last_base_candidate)
            ):
                nodes = nodes[1:]
            items.extend(nodes)
            for n in reversed(items):
                if n.get("type") not in ("sup", "sub"):
                    last_base_candidate = n
                    break
        if len(items) == 1:
            return items[0]
        return {"type": "seq", "items": items}
    if ntype in ("fraction", "frac"):
        num = _first_key(obj, _FRACTION_NUM_KEYS)
        den = _first_key(obj, _FRACTION_DEN_KEYS)
        if num is None or den is None:
            raise CoerceError("fraction node requires numerator and denominator")
        return {
            "type": "frac",
            "num": _coerce(num),
            "den": _coerce(den),
        }
    if ntype == "superscript":
        return _coerce_script(obj, "sup", ("exponent", "exp", "power"))
    if ntype == "subscript":
        return _coerce_script(obj, "sub", ("index", "sub", "subscript"))
    if ntype == "root":
        radicand = obj.get("radicand")
        if radicand is None:
            raise CoerceError("root node requires 'radicand'")
        index = obj.get("index")
        return {
            "type": "root",
            "index": _coerce(index) if index is not None else None,
            "radicand": _coerce(radicand),
        }
    if ntype in ("matrix", "grid"):
        return _coerce_matrix(obj)
    raise CoerceError(f"unknown structure node type: {ntype!r}")


def coerce_structure(structure) -> dict:
    """structure 字段 → 单根 AST 节点（顶层展开列表时包一层 seq）。"""
    coerced = _coerce(structure)
    if isinstance(coerced, list):
        if len(coerced) == 1:
            return coerced[0]
        return {"type": "seq", "items": coerced}
    return coerced


# ---------------------------------------------------------------------------
# 三态判定主入口
# ---------------------------------------------------------------------------

def evaluate_structure(expected_latex: str, description) -> str:
    """结构模式主入口 → 严格 JSON 字符串。

    description：视觉模型的结构化输出 dict（schema 见模块 docstring），
    None/非法形态按「视觉提取失败」处理。返回 status ∈
    PASS / FAIL / INCONCLUSIVE（expected LaTeX 本身解析失败属 harness
    缺陷，返回 ERROR/PARSING_ERROR，不落入三态）。
    """
    # 1. Expected AST（与 coerce 表示对齐的规范化）
    try:
        expected_ast = canonicalize_expected(parse_latex(expected_latex))
    except ValueError as e:
        return json.dumps(
            {
                "check": "e8_visual_semantic_structure",
                "status": "ERROR",
                "error_type": _ERROR_PARSING,
                "expected_latex": expected_latex,
                "observed_structure": None,
                "confidence": None,
                "issues": [],
                "diff_details": [f"Expected LaTeX parse failed: {e}"],
                "backend": (description or {}).get("backend") if isinstance(description, dict) else None,
            },
            ensure_ascii=False,
        )

    def _emit(status: str, error_type: str, observed, conf, issues, diffs, note: str | None = None):
        payload = {
            "check": "e8_visual_semantic_structure",
            "status": status,
            "error_type": error_type,
            "expected_latex": expected_latex,
            "observed_structure": observed,
            "confidence": conf,
            "issues": issues,
            "diff_details": diffs,
            "backend": description.get("backend") if isinstance(description, dict) else None,
        }
        if note:
            payload["note"] = note
        return json.dumps(payload, ensure_ascii=False)

    def _inconclusive(reason: str, conf, issues) -> str:
        return _emit(
            _STATUS_INCONCLUSIVE,
            _ERROR_VISION_FAILED,
            None,
            conf,
            issues,
            [],
            note=reason,
        )

    # 2. 视觉描述有效性（提取失败优先于任何比对结论）
    if not isinstance(description, dict):
        return _inconclusive("no vision description available", None, [])
    conf = description.get("confidence")
    issues = [str(i) for i in (description.get("issues") or [])]
    try:
        conf_value = float(conf) if conf is not None else -1.0
    except (TypeError, ValueError):
        return _inconclusive(f"invalid confidence value: {conf!r}", conf, issues)
    if conf_value < _conf_threshold():
        return _inconclusive(
            f"confidence {conf_value:.2f} below threshold {_conf_threshold():.2f}",
            conf,
            issues,
        )
    try:
        observed_ast = coerce_structure(description.get("structure"))
    except CoerceError as e:
        return _inconclusive(f"vision description failed to coerce: {e}", conf, issues)

    blocking_issues = [i for i in issues if _is_blocking_issue(i)]
    if blocking_issues:
        # 图像完整性问题（截断/模糊等）——提取不可信，不得给出 PASS/FAIL 结论
        return _inconclusive(
            f"image integrity issues reported: {blocking_issues}", conf, issues
        )

    # 3. 确定性比对（判定权在 evaluator，不在视觉模型）
    diffs = ast_diff(expected_ast, observed_ast)
    if not diffs:
        return _emit(
            _STATUS_PASS, _ERROR_NONE, observed_ast, conf_value, issues, []
        )
    return _emit(
        _STATUS_FAIL,
        classify_error(diffs),
        observed_ast,
        conf_value,
        issues,
        diffs,
    )
