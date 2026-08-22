r"""RUN-016 结构模式测试——e8_structure 三态判定 + parser 矩阵修复 + corpus。

全部 hermetic：不依赖模拟器 / VLM 权重。corpus 用例只消费入库的
description.json（真实模型产出的固化描述）与 meta.json。
"""

from __future__ import annotations

import importlib
import json
from pathlib import Path

import pytest

from cli_anything.ffx.harness.e8_latex_ast import (
    ast_diff,
    canonicalize_expected,
    parse_latex,
)
from cli_anything.ffx.harness.e8_structure import (
    CoerceError,
    coerce_structure,
    evaluate_structure,
)

CORPUS_DIR = Path(__file__).resolve().parents[1] / "harness" / "vlm_corpus"


def _sym(v: str) -> dict:
    return {"type": "symbol", "value": v}


def _frac(num: str, den: str) -> dict:
    return {
        "type": "fraction",
        "numerator": _sym(num),
        "denominator": _sym(den),
    }


def _desc(structure, confidence=0.97, issues=None) -> dict:
    return {"confidence": confidence, "issues": issues or [], "structure": structure}


# ---------------------------------------------------------------------------
# parser 修复回归（RUN-016：amp 截断 / \begin{env} 环境名 / \\ 行分隔）
# ---------------------------------------------------------------------------


class TestParserMatrixFixes:
    def test_amp_no_longer_truncates(self):
        ast = parse_latex("a&b")
        assert ast == {
            "type": "seq",
            "items": [
                {"type": "sym", "value": "a"},
                {"type": "sym", "value": "&"},
                {"type": "sym", "value": "b"},
            ],
        }

    def test_env_name_parsed_from_braced_group(self):
        ast = parse_latex(r"\begin{pmatrix}x\end{pmatrix}")
        types = [n.get("type") for n in ast["items"]]
        assert types == ["env_begin", "sym", "env_end"]
        assert ast["items"][0]["env"] == "pmatrix"
        assert ast["items"][2]["env"] == "pmatrix"

    def test_row_separator_not_glued_to_next_cell(self):
        r"""\\c 曾被拆成空命令 + \c 命令（第二反斜杠与字母粘连）。"""
        ast = parse_latex(r"a\\c")
        values = [n.get("value") for n in ast["items"]]
        # 行分隔符被跳过，c 是普通符号而非 \c 命令
        assert values == ["a", "c"]

    def test_matrix_expected_ast_shape(self):
        ast = canonicalize_expected(
            parse_latex(r"\begin{pmatrix}a&b\\c&d\end{pmatrix}")
        )
        values = [
            n.get("value") if n.get("type") == "sym" else n.get("type")
            for n in ast["items"]
        ]
        assert values == [
            "env_begin",
            "a",
            "&",
            "b",
            "c",
            "&",
            "d",
            "env_end",
        ]

    def test_regression_emc2_unchanged(self):
        ast = parse_latex("E = mc^2")
        values = [
            n.get("value") if n.get("type") == "sym" else None
            for n in ast["items"]
        ]
        assert values == ["E", "=", "m", "c", None]
        assert ast["items"][4].get("type") == "sup"
        assert ast["items"][4]["value"] == {"type": "sym", "value": "2"}

    def test_frac_diff_inversion_still_works(self):
        exp = parse_latex(r"\frac{a}{b}")
        obs = parse_latex(r"\frac{b}{a}")
        diffs = ast_diff(exp, obs)
        assert any("inverted" in d for d in diffs)


# ---------------------------------------------------------------------------
# coerce：模型宽松 JSON → AST 词表
# ---------------------------------------------------------------------------


class TestCoerceStructure:
    def test_bare_string_is_symbol(self):
        assert coerce_structure("k") == {"type": "sym", "value": "k"}

    def test_fraction_aliases(self):
        node = coerce_structure({"type": "frac", "num": _sym("x"), "den": _sym("y")})
        assert node == {
            "type": "frac",
            "num": {"type": "sym", "value": "x"},
            "den": {"type": "sym", "value": "y"},
        }

    def test_script_without_base_is_positional(self):
        node = coerce_structure({"type": "superscript", "exponent": _sym("2")})
        assert node == {"type": "sup", "value": {"type": "sym", "value": "2"}}

    def test_script_with_base_expands_positionally(self):
        nodes = coerce_structure(
            {"type": "sequence", "items": [_sym("n"), {"type": "superscript", "base": _sym("n"), "exponent": _sym("2")}]}
        )
        # base 与前一元素相同 → 不重复发射
        assert nodes == {
            "type": "seq",
            "items": [
                {"type": "sym", "value": "n"},
                {"type": "sup", "value": {"type": "sym", "value": "2"}},
            ],
        }

    def test_double_script_shared_base_x_1_squared(self):
        """模型把 x_1^2 的两个脚标都挂在同一 base 上 → 位置约定对齐。"""
        model = {
            "type": "sequence",
            "items": [
                {"type": "subscript", "base": _sym("x"), "index": _sym("1")},
                {"type": "superscript", "base": _sym("x"), "exponent": _sym("2")},
            ],
        }
        obs = coerce_structure(model)
        exp = parse_latex("x_1^2")
        assert ast_diff(exp, obs) == []

    def test_matrix_within_row_amps_only(self):
        node = coerce_structure(
            {
                "type": "matrix",
                "environment": "bmatrix",
                "rows": [[_sym("a"), _sym("b")], [_sym("c"), _sym("d")]],
            }
        )
        kinds = [
            n.get("value") if n.get("type") == "sym" else n.get("type")
            for n in node["items"]
        ]
        assert kinds[0] == "env_begin"
        assert kinds[-1] == "env_end"
        assert node["items"][0]["env"] == "bmatrix"
        assert kinds.count("&") == 2  # 行内分隔；行间无标记

    def test_unknown_type_raises(self):
        with pytest.raises(CoerceError):
            coerce_structure({"type": "poem", "value": "roses"})

    def test_missing_fraction_part_raises(self):
        with pytest.raises(CoerceError):
            coerce_structure({"type": "fraction", "numerator": _sym("a")})

    def test_single_item_sequence_unwraps(self):
        assert coerce_structure({"type": "sequence", "items": [_sym("q")]}) == {
            "type": "sym",
            "value": "q",
        }


# ---------------------------------------------------------------------------
# evaluate_structure 三态判定
# ---------------------------------------------------------------------------


class TestEvaluateStructureThreeStates:
    def _run(self, expected: str, desc) -> dict:
        return json.loads(evaluate_structure(expected, desc))

    def test_pass_on_matching_fraction(self):
        result = self._run(r"\frac{a}{b}", _desc(_frac("a", "b")))
        assert result["status"] == "PASS"
        assert result["error_type"] == "NONE"
        assert result["observed_structure"]["type"] == "frac"

    def test_fail_semantic_swap_detected_as_inversion(self):
        result = self._run(r"\frac{a}{b}", _desc(_frac("b", "a")))
        assert result["status"] == "FAIL"
        assert result["error_type"] == "STRUCTURE_INVERSION"
        assert result["diff_details"]

    def test_fail_semantic_missing_element(self):
        emc2 = {
            "type": "sequence",
            "items": [_sym("E"), _sym("="), _sym("m"), _sym("c"),
                      {"type": "superscript", "base": _sym("c"), "exponent": _sym("2")}],
        }
        result = self._run("E = mc^2", _desc(emc2))
        # 描述完整 → PASS；期望缺 ^2 才是语义错误方向的反向用例在 corpus
        assert result["status"] == "PASS"

    def test_fail_wrong_exponent_value(self):
        sup2 = {
            "type": "sequence",
            "items": [_sym("x"),
                      {"type": "subscript", "index": _sym("1")},
                      {"type": "superscript", "exponent": _sym("2")}],
        }
        result = self._run("x_1^3", _desc(sup2))
        assert result["status"] == "FAIL"

    def test_inconclusive_low_confidence(self):
        result = self._run(r"\frac{a}{b}", _desc(_frac("a", "b"), confidence=0.3))
        assert result["status"] == "INCONCLUSIVE"
        assert result["error_type"] == "VISION_EXTRACTION_FAILED"

    def test_inconclusive_blocking_issue_beats_empty_diff(self):
        # 即使结构碰巧一致，截断类 issue 也必须 INCONCLUSIVE（不得 PASS）
        result = self._run(
            r"\frac{a}{b}",
            _desc(_frac("a", "b"), issues=["bottom edge cut off"]),
        )
        assert result["status"] == "INCONCLUSIVE"

    def test_inconclusive_when_structure_none(self):
        result = self._run(r"\frac{a}{b}", _desc(None))
        assert result["status"] == "INCONCLUSIVE"

    def test_inconclusive_no_description(self):
        assert self._run(r"\frac{a}{b}", None)["status"] == "INCONCLUSIVE"

    def test_inconclusive_garbage_structure(self):
        result = self._run(r"\frac{a}{b}", _desc({"type": "haiku"}))
        assert result["status"] == "INCONCLUSIVE"

    def test_error_parsing_bad_expected(self):
        result = self._run("", _desc(_frac("a", "b")))
        assert result["status"] == "ERROR"
        assert result["error_type"] == "PARSING_ERROR"

    def test_threshold_env_override(self, monkeypatch):
        monkeypatch.setenv("FFX_E8_VLM_CONF_MIN", "0.99")
        result = self._run(r"\frac{a}{b}", _desc(_frac("a", "b"), confidence=0.97))
        assert result["status"] == "INCONCLUSIVE"

    def test_nonstandard_confidence_value(self):
        result = self._run(r"\frac{a}{b}", {"confidence": "high", "structure": _frac("a", "b")})
        assert result["status"] == "INCONCLUSIVE"


# ---------------------------------------------------------------------------
# corpus 数据驱动（真实模型描述固化入库后，判定可离线回归）
# ---------------------------------------------------------------------------

_EXPECTED_CASE_STATUSES = {
    "p1_emc2": "PASS",
    "p2_frac": "PASS",
    "p3_subsup": "PASS",
    "p4_matrix": "PASS",
    "f1_swap": "FAIL",
    "f2_wrong_sup": "FAIL",
    "f3_missing": "FAIL",
    "f4_crop": "INCONCLUSIVE",
}


@pytest.mark.parametrize("case_dir", sorted(_EXPECTED_CASE_STATUSES))
class TestRun016Corpus:
    def test_case_verdict(self, case_dir):
        case_path = CORPUS_DIR / case_dir
        meta = json.loads((case_path / "meta.json").read_text(encoding="utf-8"))
        description_file = case_path / "description.json"
        if not description_file.exists():
            pytest.fail(
                f"{case_dir}/description.json missing —— 先跑 "
                f"scripts/run016_validate.py 用真实 VLM 生成描述"
            )
        description = json.loads(description_file.read_text(encoding="utf-8"))
        result = json.loads(evaluate_structure(meta["expected_latex"], description))
        assert result["status"] == meta["expect_status"], (
            f"{case_dir}: got {result['status']} ({result['error_type']}) "
            f"diff={result['diff_details']} note={result.get('note')}"
        )

    def test_meta_matches_registry(self, case_dir):
        meta = json.loads((CORPUS_DIR / case_dir / "meta.json").read_text(encoding="utf-8"))
        assert meta["expect_status"] == _EXPECTED_CASE_STATUSES[case_dir]

    def test_screenshot_present(self, case_dir):
        assert (CORPUS_DIR / case_dir / "screenshot.png").exists()


# ---------------------------------------------------------------------------
# e8_vlm 后端（hermetic：模型以 stub 注入，不下载权重）
# ---------------------------------------------------------------------------


class _FakeTensor:
    def __init__(self, n):
        self._n = n

    def __len__(self):
        return self._n

    def __getitem__(self, idx):
        # 序列协议迭代（zip）依赖 IndexError 终止——越界必须抛，
        # 否则 __getitem__ 恒返回 self 会让 zip 死循环
        if isinstance(idx, int) and idx >= self._n:
            raise IndexError(idx)
        return self


class _FakeInputs(dict):
    """同时支持 **inputs 解包（dict）与 .input_ids 属性访问。"""

    def __init__(self):
        super().__setitem__("input_ids", _FakeTensor(3))

    def __getattr__(self, name):
        try:
            return self[name]
        except KeyError:
            raise AttributeError(name) from None


class _FakeProcessor:
    def apply_chat_template(self, messages, tokenize=False, add_generation_prompt=True):
        return "<prompt>"

    def __call__(self, text, images, return_tensors):
        return _FakeInputs()

    def batch_decode(self, ids, skip_special_tokens=True):
        return [self.output]


class TestVlmBackend:
    @pytest.fixture()
    def vlm(self):
        mod = importlib.import_module("cli_anything.ffx.harness.e8_vlm")
        yield mod
        mod._qwen2vl_model = None
        mod._qwen2vl_processor = None

    def _inject(self, mod, output_text):
        proc = _FakeProcessor()
        proc.output = output_text

        class _FakeModel:
            def generate(self, **kwargs):
                return _FakeTensor(10)

        mod._qwen2vl_model = _FakeModel()
        mod._qwen2vl_processor = proc

    def test_backend_chain_default_and_forced(self, monkeypatch, vlm):
        monkeypatch.delenv("FFX_E8_VLM_BACKEND", raising=False)
        assert vlm.backend_chain() == ["qwen2vl-local"]
        monkeypatch.setenv("FFX_E8_VLM_BACKEND", "none")
        assert vlm.backend_chain() == []
        monkeypatch.setenv("FFX_E8_VLM_BACKEND", "openai,qwen2vl-local")
        assert vlm.backend_chain() == ["openai", "qwen2vl-local"]

    def test_extract_json_object_variants(self, vlm):
        assert vlm._extract_json_object('{"a": 1}') == {"a": 1}
        assert vlm._extract_json_object('```json\n{"a": 1}\n```') == {"a": 1}
        assert vlm._extract_json_object('Sure! {"a": {"b": 2}} hope that helps') == {"a": {"b": 2}}
        assert vlm._extract_json_object('{"a": "brace } inside"}') == {"a": "brace } inside"}
        assert vlm._extract_json_object("no json here") is None
        assert vlm._extract_json_object('{"broken": ') is None

    def test_describe_structure_parses_fenced_output(self, vlm, tmp_path):
        self._inject(
            vlm,
            '```json\n{"confidence": 0.9, "issues": [], "structure": '
            '{"type": "symbol", "value": "E"}}\n```',
        )
        png = tmp_path / "x.png"
        from PIL import Image

        Image.new("RGB", (16, 16), "white").save(png)
        desc = vlm.describe_structure(str(png))
        assert desc["backend"] == "qwen2vl-local"
        assert desc["confidence"] == 0.9
        assert desc["structure"] == {"type": "symbol", "value": "E"}

    def test_describe_structure_non_json_degrades(self, vlm, tmp_path):
        self._inject(vlm, "I see a formula but cannot comply.")
        png = tmp_path / "y.png"
        from PIL import Image

        Image.new("RGB", (16, 16), "white").save(png)
        desc = vlm.describe_structure(str(png))
        assert desc["confidence"] == 0
        assert desc["structure"] is None
        assert any("JSON" in i for i in desc["issues"])

    def test_describe_structure_backend_crash_degrades(self, vlm, tmp_path):
        class _Boom:
            def generate(self, **kwargs):
                raise RuntimeError("cuda oom")

        vlm._qwen2vl_model = _Boom()
        vlm._qwen2vl_processor = _FakeProcessor()
        png = tmp_path / "z.png"
        from PIL import Image

        Image.new("RGB", (16, 16), "white").save(png)
        desc = vlm.describe_structure(str(png))
        assert desc["confidence"] == 0
        assert any("vision backend error" in i for i in desc["issues"])
