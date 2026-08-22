r"""E8 vision_extract / FFX verify 接线单元测试（Phase 3.11 RUN-015）。

覆盖：
- e8_vision 后端链：强制指定（含逗号链）/ 自动探测 / 失败降级 / 输出归一化
- e8_evaluator.vision_extract 语义收紧：有截图走真实提取（不回退代理）
- visual_receiver.call_e8_evaluator：真实 E8 严格 JSON（非模拟 result）
- FormulaAdapter.visual_check：逐公式聚合判定 + evaluate checks 接线
- _parse_e6_captures：新旧截图回传标记解析（含 latex 字段）

全部 hermetic：不依赖模拟器 / flutter / 真实 OCR 模型——后端经
register_backend 注入 fake，截图用 tmp_path 占位文件。
"""

from __future__ import annotations

import base64
import json
from pathlib import Path

import pytest

from cli_anything.ffx.harness import e8_evaluator, e8_vision
from cli_anything.ffx.harness.adapters.formula import (
    FormulaAdapter,
    _parse_e6_captures,
)
from cli_anything.ffx.harness.visual_receiver import (
    call_e8_evaluator,
    visual_check_handler,
)

CONTRACT_PATH = Path(__file__).resolve().parents[5] / "contracts" / "formula.json"


@pytest.fixture(autouse=True)
def _isolate_backends(monkeypatch):
    """清空后端注册表与强制环境变量——测试互不影响、不触真实模型。"""
    monkeypatch.setattr(e8_vision, "_BACKENDS", {})
    monkeypatch.delenv(e8_vision._FORCED_ENV, raising=False)


def _png(tmp_path: Path) -> str:
    """占位截图文件（fake 后端不解码像素，仅要求路径存在）。"""
    p = tmp_path / "shot.png"
    p.write_bytes(b"\x89PNG\r\n\x1a\nfake-bytes")
    return str(p)


def _ok_backend(expected: str) -> staticmethod:
    def _extract(_screenshot: str) -> str:
        return expected

    return _extract  # type: ignore[return-value]


# ── e8_vision 后端链 ─────────────────────────────────────────────────


class TestBackendChain:
    def test_forced_single_backend(self, monkeypatch) -> None:
        e8_vision.register_backend("fake", lambda p: "x")
        monkeypatch.setenv(e8_vision._FORCED_ENV, "fake")
        assert e8_vision.backend_chain() == ["fake"]

    def test_forced_comma_chain(self, monkeypatch) -> None:
        monkeypatch.setenv(e8_vision._FORCED_ENV, "a, b ,c")
        assert e8_vision.backend_chain() == ["a", "b", "c"]

    def test_forced_none_disables(self, monkeypatch) -> None:
        monkeypatch.setenv(e8_vision._FORCED_ENV, "none")
        assert e8_vision.backend_chain() == []

    def test_auto_order_keeps_registered_only(self, monkeypatch) -> None:
        # 注册真实自动链中的两个后端名 → 保持声明顺序过滤
        e8_vision.register_backend("tesseract", lambda p: "x")
        e8_vision.register_backend("pix2tex", lambda p: "y")
        assert e8_vision.backend_chain() == ["pix2tex", "tesseract"]

    def test_unregister(self) -> None:
        e8_vision.register_backend("tmp", lambda p: "x")
        e8_vision.register_backend("tmp", None)
        assert "tmp" not in e8_vision._BACKENDS


class TestExtractWithProvenance:
    def test_first_success_wins(self, tmp_path) -> None:
        def _boom(_p: str) -> str:
            raise RuntimeError("backend down")

        e8_vision.register_backend("boom", _boom)
        e8_vision.register_backend("good", _ok_backend(r"\frac{a}{b}"))
        latex, backend = e8_vision.extract_with_provenance(_png(tmp_path))
        assert latex == r"\frac{a}{b}"
        assert backend == "good"

    def test_chain_order_respected(self, tmp_path, monkeypatch) -> None:
        monkeypatch.setenv(e8_vision._FORCED_ENV, "second,first")
        calls: list[str] = []

        def _mk(name: str, out: str):
            def _extract(_p: str) -> str:
                calls.append(name)
                return out

            return _extract

        e8_vision.register_backend("first", _mk("first", r"a"))
        e8_vision.register_backend("second", _mk("second", r"b"))
        latex, backend = e8_vision.extract_with_provenance(_png(tmp_path))
        assert (latex, backend) == ("b", "second")
        assert calls == ["second"]  # 首个成功即停，不再调用后续

    def test_all_fail_returns_none_tuple(self, tmp_path) -> None:
        def _boom(_p: str) -> str:
            raise ValueError("nope")

        e8_vision.register_backend("boom", _boom)
        assert e8_vision.extract_with_provenance(_png(tmp_path)) == (None, None)

    def test_missing_screenshot_returns_none(self, tmp_path) -> None:
        e8_vision.register_backend("good", _ok_backend("x"))
        missing = str(tmp_path / "nope.png")
        assert e8_vision.extract_with_provenance(missing) == (None, None)

    def test_empty_result_treated_as_failure(self, tmp_path) -> None:
        e8_vision.register_backend("empty", lambda p: "   ")
        assert e8_vision.extract_with_provenance(_png(tmp_path)) == (None, None)


class TestNormalizeOcrLatex:
    def test_strips_dollar_wrap(self) -> None:
        assert e8_vision._normalize_ocr_latex(r"$\frac{a}{b}$") == r"\frac{a}{b}"

    def test_folds_whitespace(self) -> None:
        assert e8_vision._normalize_ocr_latex("E =\n\tmc^2") == "E = mc^2"

    def test_blank_becomes_none(self) -> None:
        assert e8_vision._normalize_ocr_latex(None) is None
        assert e8_vision._normalize_ocr_latex("") is None


# ── e8_evaluator.vision_extract 语义收紧 ────────────────────────────


class TestVisionExtractSemantics:
    def test_screenshot_prefers_real_extraction_over_proxy(
        self, tmp_path
    ) -> None:
        e8_vision.register_backend("fake", _ok_backend(r"\frac{a}{b}"))
        # known_latex 与截图内容不同——必须返回像素提取结果而非代理
        got = e8_evaluator.vision_extract(_png(tmp_path), r"E = mc^2")
        assert got == r"\frac{a}{b}"

    def test_no_screenshot_proxy_still_works(self) -> None:
        assert e8_evaluator.vision_extract(None, r"E = mc^2") == r"E = mc^2"

    def test_no_inputs_returns_none(self) -> None:
        assert e8_evaluator.vision_extract() is None


class TestEvaluateWithVision:
    def test_pass_with_real_backend(self, tmp_path) -> None:
        e8_vision.register_backend("fake", _ok_backend(r"\frac{a}{b}"))
        raw = e8_evaluator.evaluate(r"\frac{a}{b}", screenshot_path=_png(tmp_path))
        data = json.loads(raw)
        assert data["status"] == "PASS"
        assert data["error_type"] == "NONE"
        assert data["observed_latex"] == r"\frac{a}{b}"

    def test_fail_structure_inversion_from_pixels(self, tmp_path) -> None:
        e8_vision.register_backend("fake", _ok_backend(r"\frac{b}{a}"))
        raw = e8_evaluator.evaluate(r"\frac{a}{b}", screenshot_path=_png(tmp_path))
        data = json.loads(raw)
        assert data["status"] == "FAIL"
        assert data["error_type"] == "STRUCTURE_INVERSION"
        assert any("inverted" in d.lower() for d in data["diff_details"])

    def test_no_backend_yields_ocr_hallucination_not_proxy(
        self, tmp_path, monkeypatch
    ) -> None:
        monkeypatch.setenv(e8_vision._FORCED_ENV, "none")
        raw = e8_evaluator.evaluate(
            r"\frac{a}{b}",
            screenshot_path=_png(tmp_path),
            known_latex=r"\frac{a}{b}",  # 有代理也不得回退——截图在就必须看
        )
        data = json.loads(raw)
        assert data["status"] == "ERROR"
        assert data["error_type"] == "OCR_HALLUCINATION"
        assert data["observed_latex"] is None

    def test_observed_latex_passthrough_skips_extraction(
        self, tmp_path
    ) -> None:
        # 无任何后端可用，observed 直传 → 不做视觉提取直接进入 AST Diff
        raw = e8_evaluator.evaluate(
            r"\frac{a}{b}",
            screenshot_path=_png(tmp_path),
            observed_latex=r"\frac{a}{b}",
        )
        data = json.loads(raw)
        assert data["status"] == "PASS"


# ── visual_receiver（FFX verify 视觉检查请求层）─────────────────────


class TestVisualReceiver:
    def test_call_e8_returns_strict_schema(self, tmp_path) -> None:
        e8_vision.register_backend("fake", _ok_backend(r"\frac{a}{b}"))
        data = call_e8_evaluator(r"\frac{a}{b}", _png(tmp_path))
        assert set(data) >= {
            "status",
            "expected_latex",
            "observed_latex",
            "diff_details",
            "error_type",
        }
        assert data["status"] == "PASS"

    def test_handler_disabled_short_circuits(self) -> None:
        out = visual_check_handler({}, r"\frac{a}{b}", False, "x.png")
        assert out["status"] == "success"
        assert out["result"]["visual_check"] is False

    @pytest.mark.parametrize("field", ["visual_checker", "visual_check_level"])
    def test_handler_requires_profile_fields(self, field) -> None:
        profile = {"visual_checker": "paddleocr", "visual_check_level": "high"}
        del profile[field]
        out = visual_check_handler(profile, r"\frac{a}{b}", True, "x.png")
        assert out["status"] == "error"
        assert field in out["message"]

    def test_handler_success_wraps_details(self, tmp_path) -> None:
        e8_vision.register_backend("fake", _ok_backend(r"\frac{a}{b}"))
        profile = {"visual_checker": "pix2tex", "visual_check_level": "high"}
        out = visual_check_handler(
            profile, r"\frac{a}{b}", True, _png(tmp_path)
        )
        assert out["status"] == "success"
        assert out["result"]["checker"] == "pix2tex"
        assert out["result"]["details"]["status"] == "PASS"


# ── E6 截图回传解析（块协议 stdout-b64 / 旧单行标记兜底）────────────


def _fake_png(size: int = 300) -> bytes:
    """合成 PNG 字节流（含多行 base64 分块所需的足够长度）。"""
    return b"\x89PNG\r\n\x1a\n" + bytes(range(256)) * ((size // 256) + 1)


def _block_output(png: bytes, latex: str = r"\frac{a}{b}") -> str:
    """构造与 cap_e6_physical_render_test.dart 一致的块协议输出。"""
    b64 = base64.b64encode(png).decode("ascii")
    chunks = "\n".join(b64[i : i + 76] for i in range(0, len(b64), 76))
    return (
        "E8_PNG_BEGIN\n"
        "name=e6_formula_frac.png\n"
        f"bytes={len(png)}\n"
        "w=412\n"
        "h=160\n"
        f"latex={latex}\n"
        "b64_begin\n"
        f"{chunks}\n"
        "b64_end\n"
        "E8_PNG_END"
    )


class TestParseE6Captures:
    def test_block_marker_full_fields(self) -> None:
        png = _fake_png()
        caps = _parse_e6_captures(
            f"03:04 +1: stuff\n{_block_output(png)}\ndone."
        )
        assert len(caps) == 1
        c = caps[0]
        assert c["file_name"] == "e6_formula_frac.png"
        assert c["bytes"] == len(png)
        assert c["width"] == 412
        assert c["height"] == 160
        assert c["expected_latex"] == r"\frac{a}{b}"
        assert base64.b64decode(c["png_b64"]) == png
        assert c["device_path"] is None

    def test_block_multiline_b64_reassembled_in_order(self) -> None:
        # 76 字符分块 × 多行——重组后必须与原始字节一致（防折行截断设计）
        png = _fake_png(1200)
        caps = _parse_e6_captures(_block_output(png))
        assert base64.b64decode(caps[0]["png_b64"]) == png

    def test_multiple_blocks(self) -> None:
        out = f"{_block_output(b'aa')}\nlog line\n{_block_output(b'bbb', 'x')}"
        caps = _parse_e6_captures(out)
        assert len(caps) == 2
        assert [c["bytes"] for c in caps] == [2, 3]

    def test_no_match_returns_empty(self) -> None:
        assert _parse_e6_captures("nothing here") == []
        assert _parse_e6_captures("") == []

    LEGACY_LINE = "E6_PHYSICAL_PNG /data/user/0/x/code_cache/e6.png bytes=4910"

    def test_legacy_marker_without_latex(self) -> None:
        caps = _parse_e6_captures(self.LEGACY_LINE)
        assert len(caps) == 1
        assert caps[0]["device_path"].endswith("e6.png")
        assert caps[0]["expected_latex"] is None
        assert caps[0]["png_b64"] is None

    def test_legacy_flat_info_line_with_latex(self) -> None:
        line = (
            "E8_PNG_INFO path=/data/data/p/files/e6_formula_emc2.png "
            "bytes=2386 w=123 h=24 latex=E = mc^2"
        )
        caps = _parse_e6_captures(line)
        assert len(caps) == 1
        assert caps[0]["expected_latex"] == "E = mc^2"


# ── 截图落盘（stdout-b64 解码 / adb 兜底）+ 完整性校验 ──────────────


class TestMaterializeScreenshot:
    def _adapter(self, tmp_path: Path) -> FormulaAdapter:
        a = _mk_adapter({})
        a._out_dir = tmp_path
        return a

    def test_b64_materializes_with_integrity(self, tmp_path) -> None:
        png = _fake_png()
        a = self._adapter(tmp_path)
        entry = a._materialize_e6_screenshot(
            {
                "file_name": "e6_formula_frac.png",
                "bytes": len(png),
                "png_b64": base64.b64encode(png).decode("ascii"),
            }
        )
        assert entry["source"] == "stdout-b64"
        assert entry["integrity_ok"] is True
        assert Path(entry["local_path"]).read_bytes() == png

    def test_size_mismatch_blocks_local_path(self, tmp_path) -> None:
        png = _fake_png()
        a = self._adapter(tmp_path)
        entry = a._materialize_e6_screenshot(
            {
                "file_name": "x.png",
                "bytes": len(png) + 99,  # 与解码结果不一致 → 残缺嫌疑
                "png_b64": base64.b64encode(png).decode("ascii"),
            }
        )
        assert entry["integrity_ok"] is False
        assert entry["local_path"] is None

    def test_invalid_b64_is_evidence_gap(self, tmp_path) -> None:
        a = self._adapter(tmp_path)
        entry = a._materialize_e6_screenshot(
            {"file_name": "x.png", "bytes": 10, "png_b64": "!!!not-b64!!!"}
        )
        assert entry["integrity_ok"] is False
        assert entry["local_path"] is None

    def test_legacy_device_path_without_adb_is_gap(
        self, tmp_path, monkeypatch
    ) -> None:
        monkeypatch.setattr("shutil.which", lambda name: None)
        a = self._adapter(tmp_path)
        entry = a._materialize_e6_screenshot(
            {"file_name": None, "bytes": 4910, "device_path": "/data/x/e6.png"}
        )
        assert entry["source"] == "adb"
        assert entry["integrity_ok"] is False
        assert entry["local_path"] is None


# ── FormulaAdapter.visual_check + evaluate 接线 ─────────────────────


def _mk_adapter(metrics: dict | None = None) -> FormulaAdapter:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    a = FormulaAdapter(contract)
    a._metrics = metrics or {}
    return a


class TestFormulaAdapterVisualCheck:
    def test_pass_single_formula(self, tmp_path) -> None:
        a = _mk_adapter(
            {
                "e6_screenshots": [
                    {
                        "local_path": _png(tmp_path),
                        "expected_latex": r"\frac{a}{b}",
                    }
                ]
            }
        )
        e8_vision.register_backend("fake", _ok_backend(r"\frac{a}{b}"))
        verdict = a.visual_check()
        assert verdict is not None
        assert verdict["mode"] == "real_vision"
        assert verdict["backend"] == "fake"
        assert verdict["status"] == "PASS"
        assert verdict["screenshot_count"] == 1
        item = verdict["results"][0]
        assert set(item) >= {
            "status",
            "expected_latex",
            "observed_latex",
            "diff_details",
            "error_type",
        }

    def test_aggregate_takes_worst(self, tmp_path) -> None:
        a = _mk_adapter(
            {
                "e6_screenshots": [
                    {"local_path": _png(tmp_path), "expected_latex": r"x"},
                    {"local_path": _png(tmp_path), "expected_latex": r"\frac{a}{b}"},
                ]
            }
        )

        responses = iter([r"x", r"\frac{b}{a}"])  # 第二个公式颠倒

        def _flaky(_p: str) -> str:
            return next(responses)

        e8_vision.register_backend("fake", _flaky)
        verdict = a.visual_check()
        assert verdict["status"] == "FAIL"
        assert verdict["error_type"] == "STRUCTURE_INVERSION"

    def test_none_without_screenshots(self) -> None:
        assert _mk_adapter({}).visual_check() is None

    def test_none_when_expected_missing(self, tmp_path) -> None:
        a = _mk_adapter(
            {"e6_screenshots": [{"local_path": _png(tmp_path), "expected_latex": None}]}
        )
        e8_vision.register_backend("fake", _ok_backend("x"))
        assert a.visual_check() is None

    def test_explicit_args_override_metrics(self, tmp_path) -> None:
        a = _mk_adapter({})
        e8_vision.register_backend("fake", _ok_backend(r"E = mc^2"))
        verdict = a.visual_check(r"E = mc^2", _png(tmp_path))
        assert verdict is not None
        assert verdict["status"] == "PASS"


class TestFormulaAdapterEvaluateChecks:
    def _base_metrics(self, e8_eval: dict) -> dict:
        return {
            "render_failures": [],
            "render_test_failed": 0,
            "latest_observation": {"id": "obs_x"},
            "e8_eval": e8_eval,
        }

    def test_e8_fail_makes_verify_fail(self) -> None:
        a = _mk_adapter(
            self._base_metrics({"status": "FAIL", "error_type": "STRUCTURE_INVERSION"})
        )
        r = a.evaluate(None)
        assert r["status"] == "fail"
        assert r["coverage"]["checks"]["e8_visual_semantic_pass"] is False
        assert any("E8 visual semantic mismatch" in x for x in r["next_actions"])

    def test_e8_error_is_inconclusive_not_fail(self) -> None:
        a = _mk_adapter(
            self._base_metrics({"status": "ERROR", "error_type": "OCR_HALLUCINATION"})
        )
        r = a.evaluate(None)
        assert r["status"] == "warn"
        assert r["coverage"]["checks"]["e8_visual_semantic_pass"] is True
        assert any("inconclusive" in x for x in r["unknown"])

    def test_e8_pass_verdict_recorded(self) -> None:
        a = _mk_adapter(
            self._base_metrics(
                {"status": "PASS", "error_type": "NONE", "backend": "fake"}
            )
        )
        r = a.evaluate(None)
        assert r["status"] in ("pass", "warn")
        cov = r["coverage"]["e8_visual_semantic"]
        assert cov["status"] == "PASS"
        assert cov["backend"] == "fake"

    def test_no_e8_evidence_does_not_fail(self) -> None:
        m = self._base_metrics({})
        m["e8_eval"] = None
        r = _mk_adapter(m).evaluate(None)
        assert r["coverage"]["checks"]["e8_visual_semantic_pass"] is True
