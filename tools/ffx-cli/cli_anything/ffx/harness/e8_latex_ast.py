r"""E8 Evaluator — LaTeX → AST 解析器（Phase 3.11 RUN-014）。

容错递归下降解析：fraction / superscript / subscript / root / matrix /
括号 / 符号操作数。AST 节点统一 dict 结构，供 AST Diff 确定性比对。
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Token:
    kind: str  # 'cmd' | 'lbrace' | 'rbrace' | 'caret' | 'underscore' | 'sym' | 'amp' | 'row_sep' | 'env_begin' | 'env_end'
    value: str
    pos: int


def _tokenize(latex: str) -> list[Token]:
    r"""LaTeX 词法：\command / { } / ^ / _ / & / \\（行分隔）/ 普通符号。"""
    toks: list[Token] = []
    i = 0
    n = len(latex)
    while i < n:
        c = latex[i]
        if c == "\\":
            # \\ = 矩阵/对齐环境的行分隔符（必须先于单反斜杠命令判断，
            # 否则第二个反斜杠会和后续字母粘连成命令，如 \\c → \c）
            if i + 1 < n and latex[i + 1] == "\\":
                toks.append(Token("row_sep", "\\\\", i))
                i += 2
                continue
            # \command（字母序列）或 \frac 等
            j = i + 1
            while j < n and latex[j].isalpha():
                j += 1
            name = latex[i + 1 : j]
            toks.append(Token("cmd", name, i))
            i = j
        elif c == "{":
            toks.append(Token("lbrace", "{", i)); i += 1
        elif c == "}":
            toks.append(Token("rbrace", "}", i)); i += 1
        elif c == "^":
            toks.append(Token("caret", "^", i)); i += 1
        elif c == "_":
            toks.append(Token("underscore", "_", i)); i += 1
        elif c == "&":
            toks.append(Token("amp", "&", i)); i += 1
        elif c == " ":
            i += 1
        else:
            toks.append(Token("sym", c, i)); i += 1
    return toks


class _Parser:
    def __init__(self, toks: list[Token]):
        self.toks = toks
        self.i = 0

    def peek(self) -> Token | None:
        return self.toks[self.i] if self.i < len(self.toks) else None

    def next(self) -> Token | None:
        t = self.peek()
        if t is not None:
            self.i += 1
        return t

    def parse_seq(self) -> dict:
        """解析一个序列（隐式乘序）：如 'E = mc^2' 的顶层/括号内内容。"""
        items: list[dict] = []
        while True:
            t = self.peek()
            if t is None or t.kind == "rbrace":
                break
            if t.kind == "cmd":
                self.next()
                items.append(self._parse_command(t.value))
            elif t.kind == "lbrace":
                self.next()
                inner = self.parse_seq()
                self._expect("rbrace")
                items.append(inner)
            elif t.kind == "caret":
                self.next()
                items.append(self._parse_script("sup"))
            elif t.kind == "underscore":
                self.next()
                items.append(self._parse_script("sub"))
            elif t.kind == "sym":
                self.next()
                items.append({"type": "sym", "value": t.value})
            elif t.kind == "amp":
                # RUN-016：& 不再截断序列（原实现遇 & 直接 break，矩阵列
                # 内容全部丢失）——作为普通符号节点进入序列，供矩阵比对
                self.next()
                items.append({"type": "sym", "value": "&"})
            elif t.kind == "row_sep":
                # 行分隔符：结构比对两侧都不保留行边界信息，直接跳过
                self.next()
            else:
                self.next()  # 容错跳过未知 token
        if len(items) == 1:
            return items[0]
        return {"type": "seq", "items": items}

    def _parse_script(self, kind: str) -> dict:
        """^/_ 后跟单符号或 {组}——上标/下标归属（base 为前一个元素，由调用方合并）。"""
        t = self.next()
        if t is None:
            return {"type": kind, "value": {"type": "sym", "value": ""}}
        if t.kind == "lbrace":
            inner = self.parse_seq()
            self._expect("rbrace")
            return {"type": kind, "value": inner}
        if t.kind == "sym":
            return {"type": kind, "value": {"type": "sym", "value": t.value}}
        if t.kind == "cmd":
            return {"type": kind, "value": self._parse_command(t.value)}
        return {"type": kind, "value": {"type": "sym", "value": ""}}

    def _parse_command(self, name: str) -> dict:
        if name == "frac":
            num = self._parse_group_or_sym()
            den = self._parse_group_or_sym()
            return {"type": "frac", "num": num, "den": den}
        if name in ("sqrt",):
            index = None
            t = self.peek()
            if t is not None and t.kind == "lbrace":
                self.next()
                idx_inner = self.parse_seq()
                self._expect("rbrace")
                if self.peek() is not None and self.peek().kind == "lbrace":
                    # \sqrt[n]{x}
                    index = idx_inner
                    rad = self._parse_group_or_sym()
                    return {"type": "root", "index": index, "radicand": rad}
                # \sqrt{x}（无 index）——若刚才是 radicand
                return {"type": "root", "index": None, "radicand": idx_inner}
            rad = self._parse_group_or_sym()
            return {"type": "root", "index": index, "radicand": rad}
        if name in ("begin", "end"):
            # \begin{pmatrix}：环境名在花括号组内（tokenizer 把组拆成
            # lbrace + 符号序列 + rbrace），拼接符号还原环境名。
            # （RUN-016 修复：原实现直接 next() 取到的是 lbrace，env 恒为 '{'）
            env_chars: list[str] = []
            nxt = self.peek()
            if nxt is not None and nxt.kind == "lbrace":
                self.next()
                while True:
                    t2 = self.peek()
                    if t2 is None or t2.kind == "rbrace":
                        break
                    self.next()
                    if t2.kind == "sym":
                        env_chars.append(t2.value)
                    elif t2.kind == "cmd":
                        env_chars.append(f"\\{t2.value}")
                    else:
                        env_chars.append(t2.value)
                self._expect("rbrace")
            env_name = "".join(env_chars) or "?"
            if name == "begin":
                return {"type": "env_begin", "env": env_name}
            return {"type": "env_end", "env": env_name}
        # 其他命令（\alpha 等）：符号节点
        return {"type": "sym", "value": f"\\{name}"}

    def _parse_group_or_sym(self) -> dict:
        t = self.next()
        if t is None:
            return {"type": "sym", "value": ""}
        if t.kind == "lbrace":
            inner = self.parse_seq()
            self._expect("rbrace")
            return inner
        if t.kind == "sym":
            return {"type": "sym", "value": t.value}
        if t.kind == "cmd":
            return self._parse_command(t.value)
        return {"type": "sym", "value": ""}

    def _expect(self, kind: str) -> None:
        t = self.next()
        if t is None or t.kind != kind:
            # 容错：不抛异常，跳过
            return


def parse_latex(latex: str) -> dict:
    """LaTeX → AST（顶层序列）。解析异常时抛 ValueError（供 PARSING_ERROR 判定）。"""
    if not latex or not latex.strip():
        raise ValueError("empty latex")
    toks = _tokenize(latex)
    p = _Parser(toks)
    ast = p.parse_seq()
    if ast is None:
        raise ValueError("empty ast")
    return ast


def canonicalize_expected(ast: dict) -> dict:
    """规范化 parse_latex 输出，使其与视觉结构 coerce 表示逐点对齐。

    RUN-016：tokenizer 把矩阵换行符 \\\\ 解析为两个空命令（sym "\\"），
    而视觉侧的矩阵展开没有行分隔概念——比对前剥掉这些行分隔符节点，
    使 expected 与 coerce 的矩阵形状一致（行边界信息两侧都不保留，
    单元格仍按位置逐一比对）。
    """
    t = ast.get("type")
    if t == "seq":
        items = [canonicalize_expected(x) for x in ast.get("items", [])]
        items = [
            x
            for x in items
            if not (x.get("type") == "sym" and x.get("value") == "\\")
        ]
        return {"type": "seq", "items": items}
    if t == "frac":
        return {
            "type": t,
            "num": canonicalize_expected(ast.get("num", {})),
            "den": canonicalize_expected(ast.get("den", {})),
        }
    if t in ("sup", "sub"):
        return {"type": t, "value": canonicalize_expected(ast.get("value", {}))}
    if t == "root":
        index = ast.get("index")
        return {
            "type": t,
            "index": canonicalize_expected(index) if index else index,
            "radicand": canonicalize_expected(ast.get("radicand", {})),
        }
    return ast


# ---------------------------------------------------------------------------
# AST Diff（E8 Evaluator，Phase 3.11 RUN-014）：确定性结构比对
# ---------------------------------------------------------------------------

_STRUCT_INVERSION = "STRUCTURE_INVERSION"
_MISSING = "MISSING_ELEMENT"
_ORDER = "SYMBOL_ORDER"


def _norm_frac(node: dict) -> tuple[dict, dict]:
    """frac 的 num/den（规范化：直接取结构，供颠倒比对）。"""
    return node.get("num", {}), node.get("den", {})


def ast_diff(expected: dict, observed: dict, path: str = "root") -> list[str]:
    """两棵 AST 递归比对 → 差异描述列表（空 = 结构一致）。

    检查：frac 分子/分母颠倒、sup/sub 归属、缺失/多余元素、符号顺序。
    """
    diffs: list[str] = []

    def node_eq(a: dict, b: dict) -> bool:
        """结构相等（忽略 sym 的 value 顺序敏感性？不——sym 顺序是语义）。"""
        if a.get("type") != b.get("type"):
            return False
        t = a.get("type")
        if t == "frac":
            return node_eq(a.get("num", {}), b.get("num", {})) and node_eq(
                a.get("den", {}), b.get("den", {})
            )
        if t in ("sup", "sub"):
            return node_eq(a.get("value", {}), b.get("value", {}))
        if t == "root":
            return node_eq(a.get("index", {}) or {}, b.get("index", {}) or {}) and node_eq(
                a.get("radicand", {}), b.get("radicand", {})
            )
        if t == "seq":
            items_a, items_b = a.get("items", []), b.get("items", [])
            if len(items_a) != len(items_b):
                return False
            return all(node_eq(x, y) for x, y in zip(items_a, items_b))
        # sym
        return a.get("value") == b.get("value")

    def walk(a: dict, b: dict, p: str) -> None:
        if a.get("type") != b.get("type"):
            diffs.append(
                f"{p}: node type mismatch (expected {a.get('type')}, "
                f"observed {b.get('type')})"
            )
            return
        t = a.get("type")
        if t == "frac":
            na, da = _norm_frac(a)
            nb, db = _norm_frac(b)
            if node_eq(na, db) and node_eq(da, nb):
                diffs.append(f"{p}: Fraction numerator and denominator are inverted")
            else:
                if not node_eq(na, nb):
                    diffs.append(f"{p}: numerator mismatch")
                if not node_eq(da, db):
                    diffs.append(f"{p}: denominator mismatch")
        elif t in ("sup", "sub"):
            if not node_eq(a.get("value", {}), b.get("value", {})):
                diffs.append(
                    f"{p}: {'superscript' if t == 'sup' else 'subscript'} "
                    f"binding mismatch (归属错误)"
                )
        elif t == "root":
            ia, ib = a.get("index") or {}, b.get("index") or {}
            if not node_eq(ia, ib):
                diffs.append(f"{p}: root index mismatch")
            if not node_eq(a.get("radicand", {}), b.get("radicand", {})):
                diffs.append(f"{p}: radicand mismatch")
        elif t == "seq":
            items_a, items_b = a.get("items", []), b.get("items", [])
            if len(items_a) != len(items_b):
                diffs.append(
                    f"{p}: element count mismatch (expected {len(items_a)}, "
                    f"observed {len(items_b)})"
                )
            for i, (x, y) in enumerate(zip(items_a, items_b)):
                walk(x, y, f"{p}[{i}]")
            if len(items_a) > len(items_b):
                diffs.append(
                    f"{p}: MISSING_ELEMENT — expected {len(items_a) - len(items_b)} "
                    f"more element(s)"
                )
            elif len(items_b) > len(items_a):
                diffs.append(
                    f"{p}: extra element(s) — observed has "
                    f"{len(items_b) - len(items_a)} more"
                )
        elif t == "sym":
            if a.get("value") != b.get("value"):
                diffs.append(
                    f"{p}: symbol order/value mismatch "
                    f"(expected '{a.get('value')}', observed '{b.get('value')}')"
                )
        # 其他类型节点：类型已同，结构细项未覆盖则跳过

    walk(expected, observed, path)
    return diffs


def classify_error(diffs: list[str]) -> str:
    """diff 描述 → error_type（评审 Schema：STRUCTURE_INVERSION /
    MISSING_ELEMENT / OCR_HALLUCINATION / PARSING_ERROR / NONE）。"""
    if not diffs:
        return "NONE"
    joined = " ".join(diffs).lower()
    if "inverted" in joined or "numerator mismatch" in joined:
        return _STRUCT_INVERSION
    if "missing_element" in joined or "element count mismatch" in joined:
        return _MISSING
    return _STRUCT_INVERSION  # 默认结构类差异
