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
        root = repo_root()
        app = root / "flutter_app"
        files: list[str] = []
        total_cases = 0
        for glob in self.assets_globs:
            for f in sorted(app.glob(glob)):
                files.append(str(f.relative_to(app)))
                # 粗统计用例数（testWidgets/test/group 声明）
                try:
                    text = f.read_text(encoding="utf-8", errors="replace")
                    total_cases += len(
                        re.findall(r"\btest(?:Widgets)?\(|^\s*test\(|test\(", text)
                    )
                except OSError:
                    pass
        self._metrics = {
            "asset_files": files,
            "asset_count": len(files),
            "case_count_approx": total_cases,
        }
        graph.add(
            Evidence(
                stage="execute",
                tool="assets-scan",
                exit_code=0 if files else 1,
                summary=f"assets={len(files)} files, ~{total_cases} cases",
                detail={"capability": self.id, "assets": files[:8], "case_count": total_cases},
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

        asset_count = self._metrics.get("asset_count", 0)
        case_count = self._metrics.get("case_count_approx", 0)
        checks = {
            "test_assets_present": asset_count >= assets_min,
            "regression_assets_present": case_count > 0,
        }
        failed = [k for k, v in checks.items() if not v]
        declared = list(self.contract.get("s0_unsupported", []))
        unknown: list[str] = []
        if asset_count == 0:
            unknown.append("no test assets found (runner 未实现，仅资产引用)")

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
        if unknown:
            next_actions.append(
                f"evidence gap: {unknown} — 真实执行验证需 runner（后续轮）"
            )
        if declared:
            next_actions.append(f"decide S0 scope: {declared}")
        if status == "pass":
            next_actions.append("all checks passed; no action required")

        return {
            "status": status,
            "coverage": {
                "checks": checks,
                "asset_count": asset_count,
                "case_count_approx": case_count,
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
        "test/core/formula_pdf_renderer_test.dart",
        "test/formula_render_plan_test.dart",
    ]


class AutosaveAdapter(AssetsAdapter):
    id = "autosave"
    assets_globs = [
        "integration_test/phase34_autosave_test.dart",
        "integration_test/phase34_autosave_disk_test.dart",
    ]


class FileAdapter(AssetsAdapter):
    id = "file"
    assets_globs = [
        "test/file_service_import_test.dart",
        "test/file_service_decode_test.dart",
        "integration_test/phase34_file_tree_test.dart",
    ]


class ImeAdapter(AssetsAdapter):
    id = "ime"
    assets_globs = [
        "integration_test/cap_ime_composing_test.dart",
        "test/editing/*composing*",
        "test/editing/*ime*",
    ]


class ThemeAdapter(AssetsAdapter):
    id = "theme"
    assets_globs = [
        "test/golden/*_test.dart",
        "integration_test/phase34_theme_test.dart",
    ]


class BlockAdapter(AssetsAdapter):
    id = "block"
    assets_globs = [
        "test/editing/block_operation*_test.dart",
        "test/editing/block_editor_state_test.dart",
    ]
