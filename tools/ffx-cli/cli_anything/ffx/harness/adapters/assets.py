"""测试资产引用型 Capability Adapters — Full Capability Re-Audit（第 5-11 能力）。

这些能力（undo/pdf/autosave/file/ime/theme/block）复用既有测试资产
（test/editing、test/golden、integration_test 系列）作为 metrics 来源——
非独立 runner 实时执行；真实执行验证登记为后续轮（3.10.3 后）。

证据链：discover(资产根) → prepare(out_dir) → execute(统计测试资产
文件数+用例数) → collect_evidence → evaluate(资产完整 = pass/warn)。
"""

from __future__ import annotations

import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ..contract import repo_root
from ..evidence import Evidence, EvidenceGraph
from .base import CapabilityAdapter


class AssetsAdapter(CapabilityAdapter):
    """基类：按 capability 映射测试资产路径 globs，统计资产完整度。"""

    # 子类覆盖：id + 资产 globs（相对 flutter_app/）
    assets_globs: list[str] = []

    def __init__(self, contract: dict[str, Any]) -> None:
        super().__init__(contract)
        self._out_dir: Path | None = None
        self._metrics: dict[str, Any] = {}

    def discover(self, graph: EvidenceGraph) -> None:
        root = repo_root()
        app = root / "flutter_app"
        graph.add(
            Evidence(
                stage="discover",
                tool="ffx",
                exit_code=0,
                summary=f"flutter_app={'ok' if app.is_dir() else 'missing'}",
                detail={"flutter_app": str(app)},
            )
        )

    def prepare(self, graph: EvidenceGraph) -> None:
        root = repo_root()
        out = root / ".ffx" / "tmp" / "verify" / (
            f"{self.id}-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
        )
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
        # 3.11.1（2026-08-20）：真实 runner 执行——跑对应测试文件拿真实
        # pass/fail metrics（替代「测试资产存在」扫描）。
        from .. import runtime_bridge

        try:
            result = runtime_bridge.run_flutter_tests(self.assets_globs, self._out_dir)
            self._metrics = {
                "exit_code": result.get("exit_code"),
                "files": result.get("files", 0),
                "passed": result.get("passed", 0),
                "skipped": result.get("skipped", 0),
                "failed": result.get("failed", 0),
                "tail": result.get("tail", ""),
            }
        except Exception as e:  # noqa: BLE001 — runner 失败登记为 fail（真实结果）
            self._metrics = {"runner_error": str(e), "passed": 0, "failed": 1}
            graph.add(
                Evidence(
                    stage="execute",
                    tool="flutter-test",
                    exit_code=1,
                    summary=f"runner error: {e}",
                    detail={"capability": self.id, "error": str(e)},
                )
            )
            return
        graph.add(
            Evidence(
                stage="execute",
                tool="flutter-test",
                exit_code=self._metrics.get("exit_code", 1),
                summary=(
                    f"{self._metrics.get('passed', 0)} passed / "
                    f"{self._metrics.get('failed', 0)} failed / "
                    f"{self._metrics.get('skipped', 0)} skipped "
                    f"({self._metrics.get('files', 0)} files)"
                ),
                artifact=str(self._out_dir),
                detail={"capability": self.id, "metrics": self._metrics},
            )
        )

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
        assets_min = int(policy.get("test_assets_min", 1))

        # 3.11.1：真实 runner metrics（passed/failed/files）替代资产计数
        passed = int(self._metrics.get("passed", 0))
        failed = int(self._metrics.get("failed", 0))
        files = int(self._metrics.get("files", 0))
        runner_error = "runner_error" in self._metrics
        checks = {
            "tests_executed": files >= assets_min,
            "no_failures": failed == 0,
        }
        failed_checks = [k for k, v in checks.items() if not v]
        declared = list(self.contract.get("s0_unsupported", []))
        unknown: list[str] = []
        if files == 0 and not runner_error:
            unknown.append("no test files matched (runner 无可用测试：需模拟器/golden 环境)")

        status = "pass"
        if not self._metrics:
            status = "inconclusive"
        elif runner_error or (failed_checks and files > 0):
            # 真实失败（有测试但 fail）或 runner 错误 → fail；
            # 空 globs（无测试可跑）→ warn（证据缺口，非能力失败）
            status = "fail"
        elif unknown:
            status = "warn"  # 证据缺口（G3 修正：declared s0 只记录不降级）

        next_actions: list[str] = []
        if failed_checks:
            next_actions.append(f"failed checks: {failed_checks}")
        if failed > 0:
            next_actions.append(f"真实测试失败 {failed} 项（3.11 加固循环入口）")
        if unknown:
            next_actions.append(f"evidence gap: {unknown}")
        if declared:
            next_actions.append(f"decide S0 scope: {declared}")
        if status == "pass":
            next_actions.append("all checks passed; no action required")

        return {
            "status": status,
            "coverage": {
                "checks": checks,
                "passed": passed,
                "failed": failed,
                "skipped": int(self._metrics.get("skipped", 0)),
                "files": files,
            },
            # 3.11 证据层明示（防证据层级偷换）：flutter test 真实执行
            # 但非生产运行时——production_runtime=false（测试层证据）
            "execution": {
                "runner": "flutter_test",
                "real_execution": True,
                "production_runtime": False,
            },
            "declared_boundaries": declared,
            "unknown": unknown,
            "next_actions": next_actions,
        }


class UndoAdapter(AssetsAdapter):
    id = "undo"
    assets_globs = [
        "test/editing/*undo*",
        "test/editing/cap_beh_audit_test.dart",
    ]


class PdfAdapter(AssetsAdapter):
    id = "pdf"
    assets_globs = [
        "test/export_integration_test.dart",
        "test/formula_render_plan_test.dart",
    ]


class AutosaveAdapter(AssetsAdapter):
    id = "autosave"
    # 3.11.1：autosave 仅 integration_test（需模拟器）→ 无 test/ 独立 runner，
    # globs 留空 → execute 报 no test files matched → warn（诚实登记需模拟器）
    assets_globs: list[str] = []


class FileAdapter(AssetsAdapter):
    id = "file"
    assets_globs = [
        "test/file_service_import_test.dart",
        "test/file_service_decode_test.dart",
    ]


class ImeAdapter(AssetsAdapter):
    id = "ime"
    assets_globs = [
        "test/editing/*composing*",
        "test/editing/*ime*",
    ]


class ThemeAdapter(AssetsAdapter):
    id = "theme"
    # 3.11.1：theme 仅 golden（预存环境失败，§13.2）与 integration_test（需模拟器）
    # → 无 test/ 独立 runner，globs 留空 → warn（诚实登记）
    assets_globs: list[str] = []


class BlockAdapter(AssetsAdapter):
    id = "block"
    assets_globs = [
        "test/editing/block_operation*_test.dart",
        "test/editing/block_editor_state_test.dart",
    ]
