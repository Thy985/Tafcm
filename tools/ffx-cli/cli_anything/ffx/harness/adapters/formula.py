"""Formula Capability Adapter — P0.1 第 4 个能力（D4：ADI 衔接最小版）。

证据链：discover(ADI 存储探测) → prepare(out_dir) → execute(读 .adi/ 观察：
RenderOverflow 等失败 → ADI 证据可用性) → collect_evidence → evaluate。

最小版目标：验证 FFX 能把产品失败（RenderOverflow）连接到 ADI 证据链
（latest-error → trace-show → replay）——verify formula 不误报 PASS
当 ADI 存在未解决的渲染失败观察。

完整公式渲染 corpus 验证（输入 md → 渲染 → 视觉断言）需 render runner，
属 3.10.3 后续轮——本 adapter 聚焦 ADI 衔接契约。
"""
from __future__ import annotations

import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ..contract import repo_root
from ..e8_evaluator import evaluate as e8_evaluate
from ..e8_structure import evaluate_structure as e8_evaluate_structure
from ..e8_vision import extract_with_provenance
from ..e8_vlm import backend_chain as vlm_backend_chain
from ..e8_vlm import describe_structure as vlm_describe_structure
from ..evidence import Evidence, EvidenceGraph
from .base import CapabilityAdapter

# RenderOverflow 等渲染失败观察的 ADI 存储
ADI_OBSERVATIONS = ".adi/observations"
# 3.11.4 扩展：覆盖 Formula 渲染失败类（评审 §2 failure_class 区分）——
# RenderOverflow（布局）/ SvgParse（SVG 解析）/ FormulaSvgException（公式 SVG）
_RENDER_ERROR_KEYWORDS = ("RenderOverflow", "RenderFlex", "overflowed", "SvgParse", "FormulaSvg", "svg")

# RUN-015（E8 接线）：E6 runner 截图回传——块协议（当前，cap_e6_physical_render_test.dart）：
#   E8_PNG_BEGIN / name= / bytes= / w= / h= / latex= / b64_begin … b64_end / E8_PNG_END
# PNG 以 base64 分块（≤76 字符/行）走 stdout 直传——flutter test 结束即卸载
# app，应用私有目录无法事后拉取（run-as unknown package 实测）；分块短行
# 防 compact reporter 折行截断（单行超 ~120 列实测被折，latex 残缺）。
# 兼容旧单行标记（RUN-012/014 期 runner，走 adb 拉取兜底）：
#   `E8_PNG_INFO path=<path> bytes=N … latex=…` / `E6_PHYSICAL_PNG <path> bytes=N`
_E6_BLOCK_RE = re.compile(r"E8_PNG_BEGIN\s*\n(?P<body>.*?)\nE8_PNG_END", re.DOTALL)
_E6_CAPTURE_RE = re.compile(
    r"(?:E6_PHYSICAL_PNG\s+(?P<legacy_path>\S+)"
    r"|E8_PNG_INFO\s+path=(?P<path>\S+))"
    r"\s+bytes=(?P<bytes>\d+)"
    r"(?:\s+w=(?P<width>\d+)\s+h=(?P<height>\d+))?"
    r"(?:\s+latex=(?P<latex>.*))?$",
    re.MULTILINE,
)
# 设备端 Tafcm debug 包名（旧格式 run-as 拉取应用私有目录截图用）
_E6_APP_PACKAGE = "com.tafcm.app"


def _parse_e6_captures(run_output: str) -> list[dict[str, Any]]:
    """解析 E6 runner 输出的截图捕获（块协议优先，旧单行标记兜底）。"""
    text = (run_output or "").replace("\r\n", "\n").replace("\r", "\n")
    captures: list[dict[str, Any]] = []
    for m in _E6_BLOCK_RE.finditer(text):
        fields: dict[str, str] = {}
        b64_chunks: list[str] = []
        in_b64 = False
        for line in m.group("body").split("\n"):
            stripped = line.strip()
            if stripped == "b64_begin":
                in_b64 = True
                continue
            if stripped == "b64_end":
                in_b64 = False
                continue
            if in_b64:
                if stripped:
                    b64_chunks.append(stripped)
                continue
            key, sep, value = stripped.partition("=")
            if sep and value:
                fields[key.strip()] = value
        captures.append(
            {
                "file_name": fields.get("name"),
                "bytes": int(fields["bytes"]) if fields.get("bytes") else 0,
                "width": int(fields["w"]) if fields.get("w") else None,
                "height": int(fields["h"]) if fields.get("h") else None,
                "expected_latex": fields.get("latex") or None,
                "png_b64": "".join(b64_chunks) or None,
                # 块协议经 stdout 直传，无设备端路径
                "device_path": None,
            }
        )
    if captures:
        return captures
    # 旧格式兜底：单行标记（RUN-012/014 期 runner 输出）
    for m in _E6_CAPTURE_RE.finditer(text):
        captures.append(
            {
                "device_path": m.group("path") or m.group("legacy_path"),
                "bytes": int(m.group("bytes")),
                "width": int(m.group("width")) if m.group("width") else None,
                "height": int(m.group("height")) if m.group("height") else None,
                "expected_latex": (m.group("latex") or "").strip() or None,
                "png_b64": None,
                "file_name": None,
            }
        )
    return captures


class FormulaAdapter(CapabilityAdapter):
    id = "formula"

    def __init__(self, contract: dict[str, Any]) -> None:
        super().__init__(contract)
        self._out_dir: Path | None = None
        self._metrics: dict[str, Any] = {}

    def discover(self, graph: EvidenceGraph) -> None:
        root = repo_root()
        obs_dir = root / ADI_OBSERVATIONS
        graph.add(
            Evidence(
                stage="discover",
                tool="ffx",
                exit_code=0,
                summary=f"adi_observations_dir={'ok' if obs_dir.is_dir() else 'missing'}",
                detail={"adi_dir": str(obs_dir)},
            )
        )

    def prepare(self, graph: EvidenceGraph) -> None:
        root = repo_root()
        out = root / ".ffx" / "tmp" / "verify" / f"formula-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
        out.mkdir(parents=True, exist_ok=True)
        self._out_dir = out
        graph.add(
            Evidence(
                stage="prepare",
                tool="ffx",
                exit_code=0,
                summary=f"out_dir={out}",
                artifact=str(out),
            )
        )

    def execute(self, graph: EvidenceGraph) -> None:
        root = repo_root()
        obs_dir = root / ADI_OBSERVATIONS
        render_failures: list[dict[str, Any]] = []
        latest_obs: dict[str, Any] | None = None
        if obs_dir.is_dir():
            # 读最新观察（按文件名时间戳倒序，取最新 err_*.json）
            obs_files = sorted(obs_dir.glob("err_*.json"), reverse=True)
            if obs_files:
                try:
                    latest_obs = json.loads(obs_files[0].read_text(encoding="utf-8"))
                except (json.JSONDecodeError, OSError):
                    latest_obs = None
            # 收集所有渲染失败观察
            for f in obs_files[:10]:
                try:
                    data = json.loads(f.read_text(encoding="utf-8"))
                except (json.JSONDecodeError, OSError):
                    continue
                msg = str(data.get("message", ""))
                err_type = str(data.get("error_type", ""))
                if any(k in msg or k in err_type for k in _RENDER_ERROR_KEYWORDS):
                    render_failures.append(
                        {"id": data.get("id"), "type": err_type, "message": msg[:120]}
                    )
        self._metrics = {
            "latest_observation": latest_obs,
            "render_failures": render_failures,
            "render_failure_count": len(render_failures),
        }

        # 3.11 F3 Runtime Real Defect Loop（2026-08-21）：除 ADI 观察外，
        # 增加真实渲染测试执行（flutter test formula 相关）——回退真实渲染
        # 产品代码（formula_renderer 等）→ 测试失败 → verify formula FAIL
        # （Runtime evidence：非注入观察，Controlled Real Defect Reproduction）。
        from .. import runtime_bridge

        try:
            rt = runtime_bridge.run_flutter_tests(
                [
                    "test/formula_extractor_test.dart",
                    "test/formula_render_plan_test.dart",
                ],
                self._out_dir,
            )
            self._metrics["render_test_passed"] = rt.get("passed", 0)
            self._metrics["render_test_failed"] = rt.get("failed", 0)
            self._metrics["render_test_files"] = rt.get("files", 0)
        except Exception as e:  # noqa: BLE001 — 测试执行失败登记 fail
            self._metrics["render_test_failed"] = 1
            self._metrics["render_test_error"] = str(e)

        # E6 Physical Runtime（2026-08-21，评审冻结顺序第 4 步）：模拟器真实
        # Flutter runtime 渲染 FormulaRenderer → 结构断言 + 截图 PNG
        # （integration_test，virtual_device_runtime 证据——非 headless 单测；
        # 真机 physical_device_runtime Release Gate 仍登记）。
        # RUN-015：runner 逐公式导出 PNG 并回传 latex（E8_PNG_INFO 行）→
        # adb 拉取到 host → visual_check() 做 E8 视觉语义验证。
        try:
            import subprocess as _sp

            device = os.environ.get("FFX_E6_DEVICE_SERIAL", "emulator-5554")
            # encoding 显式 UTF-8：GBK 控制台下 text=True 解码失败会丢失全部
            # stdout（E8_PNG 块/compact 汇总都拿不到，见 runtime_bridge 同注）
            e6_proc = _sp.run(
                [
                    runtime_bridge._flutter(),
                    "test",
                    "integration_test/cap_e6_physical_render_test.dart",
                    "-d",
                    device,
                    "--reporter",
                    "compact",
                ],
                cwd=str(root / "flutter_app"),
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=240,
            )
            e6_out = (e6_proc.stdout or "") + (e6_proc.stderr or "")
            captures = _parse_e6_captures(e6_out)
            shots = [self._materialize_e6_screenshot(c) for c in captures]
            self._metrics["e6_screenshots"] = shots
            # 兼容旧字段：host 侧可读路径（None=无捕获或落盘失败）
            self._metrics["e6_screenshot"] = next(
                (p["local_path"] for p in shots if p.get("local_path")), None
            )
            self._metrics["e6_physical_render_ok"] = (
                e6_proc.returncode == 0 and bool(captures)
            )
            self._metrics["e6_structural_ok"] = e6_proc.returncode == 0
        except Exception as e:  # noqa: BLE001 — E6 环境不可用登记 evidence gap
            self._metrics["e6_physical_render_ok"] = False
            self._metrics["e6_error"] = str(e)

        # E8 视觉语义验证（RUN-015）：E6 截图 + Expected LaTeX → 真实视觉
        # 提取（e8_vision 后端链）→ AST Diff → 严格 JSON 并入 metrics/
        # evidence（评审建议完整闭环：Observed 来自截图像素而非代理）。
        try:
            self._metrics["e8_eval"] = self.visual_check()
        except Exception as e:  # noqa: BLE001 — E8 失败登记不中断 verify
            self._metrics["e8_eval"] = None
            self._metrics["e8_eval_error"] = str(e)

        graph.add(
            Evidence(
                stage="execute",
                tool="adi+flutter-test",
                exit_code=0 if not render_failures else 1,
                summary=(
                    f"render_failures={len(render_failures)} "
                    f"latest={latest_obs.get('id') if latest_obs else None} "
                    f"render_tests_passed={self._metrics.get('render_test_passed', 0)} "
                    f"failed={self._metrics.get('render_test_failed', 0)} "
                    f"e8={(self._metrics.get('e8_eval') or {}).get('status')}"
                ),
                detail={
                    "capability": self.id,
                    "render_failures": render_failures[:5],
                    "render_tests": {
                        "passed": self._metrics.get("render_test_passed", 0),
                        "failed": self._metrics.get("render_test_failed", 0),
                    },
                    # E6 Physical Runtime evidence（模拟器真实渲染截图）
                    "e6_physical_render": {
                        "ok": self._metrics.get("e6_physical_render_ok", False),
                        "screenshot": self._metrics.get("e6_screenshot"),
                        "structural_ok": self._metrics.get("e6_structural_ok", False),
                    },
                    # E8 视觉语义验证严格 JSON（RUN-015：真实提取 + AST Diff）
                    "e8_visual_semantic": self._metrics.get("e8_eval"),
                },
            )
        )

    def _materialize_e6_screenshot(
        self, capture: dict[str, Any]
    ) -> dict[str, Any]:
        """把回传的截图落到 host 文件（stdout base64 → 旧格式 adb 拉取兜底）。

        完整性校验（E8.1）：解码字节数与 runner 报告一致才视为有效——
        不一致/解码失败 → local_path=None（evidence gap，不喂残缺图给 E8）。
        """
        import base64 as _b64

        entry = dict(capture)
        entry["local_path"] = None
        entry["integrity_ok"] = False
        data: bytes | None = None
        if entry.get("png_b64"):
            try:
                data = _b64.b64decode(entry["png_b64"], validate=True)
            except Exception:  # noqa: BLE001 — 解码失败按 evidence gap 处理
                data = None
            entry["source"] = "stdout-b64"
        elif entry.get("device_path"):
            data = self._adb_pull_bytes(entry["device_path"])
            entry["source"] = "adb"
        if not data or self._out_dir is None:
            return entry

        expected_size = int(entry.get("bytes") or 0)
        entry["integrity_ok"] = expected_size == 0 or len(data) == expected_size
        name = entry.get("file_name") or "e6_formula.png"
        local = self._out_dir / f"e6-{name}"
        local.write_bytes(data)
        entry["local_path"] = (
            str(local) if entry["integrity_ok"] and local.stat().st_size > 0 else None
        )
        return entry

    def _adb_pull_bytes(self, remote: str | None) -> bytes | None:
        """旧格式兼容：adb 拉取设备端截图字节（run-as cat → pull 兜底）。"""
        import shutil as _shutil
        import subprocess as _sp

        if not remote:
            return None
        adb = _shutil.which("adb")
        device = os.environ.get("FFX_E6_DEVICE_SERIAL", "emulator-5554")
        if not adb:
            return None
        proc = _sp.run(
            [adb, "-s", device, "exec-out", "run-as", _E6_APP_PACKAGE, "cat", remote],
            capture_output=True,
            timeout=60,
        )
        if proc.returncode == 0 and proc.stdout:
            return proc.stdout
        if self._out_dir is None:
            return None
        tmp = self._out_dir / Path(remote).name
        proc = _sp.run(
            [adb, "-s", device, "pull", remote, str(tmp)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=60,
        )
        if proc.returncode == 0 and tmp.is_file():
            data = tmp.read_bytes()
            tmp.unlink(missing_ok=True)
            return data or None
        return None

    def _structure_check(self, screenshot: str, expected: str) -> tuple[dict[str, Any], bool]:
        """RUN-016 结构模式：VLM 结构化描述 → 确定性三态判定。

        返回 (result, infra_failure)。infra_failure=True 仅表示 VLM 后端
        本身不可用（加载失败/异常）——调用方回退 OCR 链；感知性
        INCONCLUSIVE（低置信/截断/非 JSON 输出）不是基础设施故障，
        保持诚实不回退。
        """
        desc = vlm_describe_structure(screenshot)
        result = json.loads(e8_evaluate_structure(expected, desc))
        result["mode"] = "vlm_structure"
        issues = [str(i) for i in (desc.get("issues") or [])]
        infra = any(i.startswith("vision backend error") for i in issues)
        return result, infra

    def visual_check(
        self,
        expected_latex: str | list[str] | None = None,
        screenshot_path: str | None = None,
    ) -> dict[str, Any] | None:
        """E8 视觉语义验证（RUN-015 接线 / RUN-016 结构模式优先）。

        优先走 VLM 结构化路线（模型描述结构 → evaluator 确定性三态，
        模型只感知不判定）；VLM 被禁用或基础设施故障时回退 OCR 链
        （pix2tex → LaTeX 字符串 → AST Diff）。聚合逐公式判定：

            {status, error_type, backend, mode, screenshot_count, results}

        - expected_latex 缺省取 E6 runner 回传的逐公式 latex（与
          cap_e6_physical_render_test.dart 单一真相源）；
        - screenshot_path 缺省取 metrics.e6_screenshots（host PNG）；
        - 前置缺失（无截图 / 无 latex）返回 None——登记 evidence gap，
          不伪造判定；FAIL → verify fail；ERROR / INCONCLUSIVE → unknown →
          warn（ADR-0030 视觉未判定语义，非产品失败）。
        """
        shots = self._metrics.get("e6_screenshots") or []
        if screenshot_path is not None:
            shots = [{"local_path": screenshot_path, "expected_latex": None}]
        if not shots:
            return None

        expected = expected_latex
        if expected is None:
            expected = [s.get("expected_latex") for s in shots]
        elif isinstance(expected, str):
            expected = [expected]

        results: list[dict[str, Any]] = []
        backend: str | None = None
        vlm_enabled = bool(vlm_backend_chain())
        for shot, exp in zip(shots, expected):
            local = shot.get("local_path") if isinstance(shot, dict) else shot
            if not exp or not local:
                continue  # 前置缺失 → evidence gap（不伪造该公式判定）
            item: dict[str, Any] | None = None
            if vlm_enabled:
                item, infra = self._structure_check(str(local), str(exp))
                if infra:
                    # 后端不可用 → OCR 兜底；在结果里如实登记降级路径
                    item = {
                        "status": "INCONCLUSIVE",
                        "error_type": "VISION_EXTRACTION_FAILED",
                        "note": "vlm backend unavailable, fell back to OCR chain",
                        "mode": "ocr_fallback_from_vlm_infra",
                    }
            if item is not None and item.get("mode") == "ocr_fallback_from_vlm_infra":
                observed, backend_name = extract_with_provenance(str(local))
                backend = backend or backend_name
                raw = e8_evaluate(
                    expected_latex=str(exp),
                    screenshot_path=str(local),
                    observed_latex=observed,
                )
                ocr_item = json.loads(raw)
                ocr_item["mode"] = "real_vision_ocr_fallback"
                ocr_item["vlm_infra_note"] = item.get("note")
                item = ocr_item
            elif item is None:
                # VLM 被禁用（FFX_E8_VLM_BACKEND=none）→ 直接 OCR 链
                observed, backend_name = extract_with_provenance(str(local))
                backend = backend or backend_name
                raw = e8_evaluate(
                    expected_latex=str(exp),
                    screenshot_path=str(local),
                    observed_latex=observed,
                )
                item = json.loads(raw)
                item["mode"] = "real_vision"
            backend = backend or item.get("backend")
            item["screenshot"] = str(local)
            results.append(item)

        if not results:
            return None

        rank = {"PASS": 0, "FAIL": 1, "ERROR": 2, "INCONCLUSIVE": 2}
        worst = max(results, key=lambda r: rank.get(r.get("status", "ERROR"), 2))
        return {
            "capability": self.id,
            "check": "e8_visual_semantic",
            "mode": worst.get("mode", "vlm_structure"),
            "backend": backend or worst.get("backend"),
            "status": worst.get("status"),
            "error_type": worst.get("error_type"),
            "screenshot_count": len(results),
            "results": results,
        }

    def collect_evidence(self, graph: EvidenceGraph) -> None:
        policy = self.contract.get("completion_policy", {})
        s0 = self.contract.get("s0_unsupported", [])
        graph.add(
            Evidence(
                stage="collect",
                tool="ffx",
                exit_code=0,
                summary=f"policy={policy}; s0={s0}",
                detail={"policy": policy, "s0_unsupported": s0},
            )
        )

    def evaluate(self, graph: EvidenceGraph) -> dict[str, Any]:
        policy = self.contract.get("completion_policy", {})
        render_error_max = int(policy.get("render_error_max", 0))
        adi_required = bool(policy.get("adi_binding_required", True))

        failures = self._metrics.get("render_failures", [])
        # 3.11 F3 Runtime：渲染测试 check（真实代码缺陷检测——flutter test
        # formula 相关失败 → fail，Runtime evidence 非注入观察）
        render_test_failed = int(self._metrics.get("render_test_failed", 0))
        # E8 视觉语义（RUN-015）：FAIL = 公式结构与截图不符 → verify fail；
        # 无证据 / ERROR（视觉未判定）不在 checks 里 fail——走 unknown →
        # warn（ADR-0030：INCONCLUSIVE 覆盖「视觉未判定」，非产品失败）。
        e8_eval = self._metrics.get("e8_eval") or {}
        e8_status = str(e8_eval.get("status") or "")
        checks = {
            "no_adi_render_failure": len(failures) <= render_error_max,
            "no_render_test_failures": render_test_failed == 0,
            "render_observable": (
                not adi_required
                or self._metrics.get("latest_observation") is not None
            ),
            "e8_visual_semantic_pass": e8_status != "FAIL",
        }
        failed = [k for k, v in checks.items() if not v]
        declared = list(self.contract.get("s0_unsupported", []))
        unknown: list[str] = []
        if self._metrics.get("latest_observation") is None:
            unknown.append("no ADI observation available (evidence gap)")
        if e8_status == "ERROR":
            unknown.append(
                f"E8 visual semantic inconclusive ({e8_eval.get('error_type')})"
            )

        status = "pass"
        if not self._metrics:
            status = "inconclusive"
        elif failed:
            status = "fail"
        elif unknown:
            status = "warn"  # 证据缺口（G3 修正：declared s0 只记录不降级）

        next_actions: list[str] = []
        if failed:
            next_actions.append(f"failed checks: {failed}")
        if failures:
            next_actions.append(
                f"render failures detected: {[f['id'] for f in failures[:5]]} "
                f"→ adi trace-show / replay 诊断"
            )
        if unknown:
            next_actions.append(f"evidence gap: {unknown}")
        if e8_status == "FAIL":
            next_actions.append(
                "E8 visual semantic mismatch — inspect evidence detail "
                "e8_visual_semantic.results[].diff_details"
            )
        if declared:
            next_actions.append(f"decide S0 scope: {declared}")
        if status == "pass":
            next_actions.append("all checks passed; no action required")

        return {
            "status": status,
            "coverage": {
                "checks": checks,
                "render_failure_count": len(failures),
                "adi_latest_observation": (
                    # or {} 兜底：key 存在但为 None（无 ADI 观察）时不崩
                    (self._metrics.get("latest_observation") or {}).get("id")
                ),
                # E8 视觉语义验证摘要（严格 JSON 全文见 execute evidence
                # detail 的 e8_visual_semantic 字段）
                "e8_visual_semantic": {
                    "status": e8_status or None,
                    "error_type": e8_eval.get("error_type"),
                    "backend": e8_eval.get("backend"),
                    "screenshots": e8_eval.get("screenshot_count", 0),
                },
            },
            "declared_boundaries": declared,
            "unknown": unknown,
            "next_actions": next_actions,
        }
