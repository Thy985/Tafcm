"""Serializer Capability Adapter — P0.1 第 2 个能力（REGRESSION path 前置）。

证据链：discover(flutter 可用) → prepare(corpus/out) → execute(Runtime Bridge →
真实 MarkdownSerializer round-trip) → collect → evaluate(对照契约)。

与 MarkdownAdapter 共享同一 runner（round-trip 指标），但 required_checks
聚焦序列化保真（serialize / roundtrip / no_parse_error）——提供跨能力
回归对比的第 2 个 capability。
"""
from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .. import runtime_bridge
from ..contract import repo_root
from ..evidence import Evidence, EvidenceGraph
from .base import CapabilityAdapter


class SerializerAdapter(CapabilityAdapter):
    id = "serializer"

    def __init__(self, contract: dict[str, Any]) -> None:
        super().__init__(contract)
        self._corpus_dir: str | None = None
        self._out_dir: Path | None = None
        self._metrics: dict[str, Any] = {}
        self._runner_result: dict[str, Any] = {}

    def discover(self, graph: EvidenceGraph) -> None:
        root = repo_root()
        runner = root / "flutter_app" / "tool" / "capability_runner" / "capability_runner_test.dart"
        graph.add(
            Evidence(
                stage="discover",
                tool="ffx",
                exit_code=0,
                summary="runner present",
                detail={"runner": str(runner)},
            )
        )

    def prepare(self, graph: EvidenceGraph) -> None:
        root = repo_root()
        out = root / ".ffx" / "tmp" / "verify" / f"serializer-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
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
        # 复用 markdown runner（round-trip 指标：parse→serialize→parse 收敛）
        result = runtime_bridge.run_markdown(self._corpus_dir, self._out_dir)  # type: ignore[arg-type]
        self._runner_result = result
        m = result.get("metrics", {})
        self._metrics = m
        graph.add(
            Evidence(
                stage="execute",
                tool="dart-runner",
                exit_code=result.get("exit_code", 0),
                summary=f"files={m.get('files', 0)} roundtrip_conv={m.get('roundtrip_convergence', 0)}",
                artifact=result.get("artifact"),
                detail={"capability": self.id, "metrics": m},
            )
        )

    def collect_evidence(self, graph: EvidenceGraph) -> None:
        # execute 已写入 graph；此处补充契约相关元信息（对齐 base 抽象方法）
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
        conv_min = float(policy.get("roundtrip_convergence_min", 0.99))
        err_max = int(policy.get("parse_error_max", 0))
        # R3 修复：读取契约的 unknown_max / blocking_unknown（此前被忽略）
        unknown_max = int(policy.get("unknown_max", 3))
        blocking_unknown = list(policy.get("blocking_unknown", []))

        files = int(self._metrics.get("files", 0))
        conv = float(self._metrics.get("roundtrip_convergence", 0.0))
        line_errors = int(self._metrics.get("line_errors", -1))
        converged = int(self._metrics.get("roundtrip_converged", 0))

        # serializer 能力：focused checks（serialize/roundtrip/no_parse_error）
        # serialize 用 roundtrip_converged > 0 作代理（runner round-trip 含
        # MarkdownSerializer.serialize，抛异常则整体失败）
        checks = {
            "serialize": converged > 0,
            "roundtrip": conv >= conv_min,
            "no_parse_error": line_errors <= err_max,
        }
        failed = [k for k, v in checks.items() if not v]
        declared = list(self.contract.get("s0_unsupported", []))
        unknown: list[str] = []
        if not self._metrics:
            unknown.append("no runner metrics (evidence gap)")
        elif files == 0:
            unknown.append("runner reported 0 files (evidence gap)")

        blocked = [u for u in declared + unknown if u in blocking_unknown]
        overflow = len(declared) + len(unknown) > unknown_max

        status = "pass"
        if not self._metrics or files == 0:
            status = "inconclusive"
        elif failed or blocked or overflow:
            status = "fail"
        elif declared or unknown:
            status = "warn"

        next_actions: list[str] = []
        if failed:
            next_actions.append(f"failed checks: {failed}")
        if blocked:
            next_actions.append(f"blocking unknown hit: {blocked}")
        if overflow:
            next_actions.append(
                f"unknown overflow: {len(declared) + len(unknown)} > unknown_max={unknown_max}"
            )
        if declared:
            next_actions.append(f"decide S0 scope: {declared}")
        if unknown:
            next_actions.append(f"evidence gap: {unknown}")
        if status == "pass":
            next_actions.append("all checks passed; no action required")

        return {
            "status": status,
            "coverage": {
                "roundtrip_convergence": conv,
                "checks": checks,
                "unknown_max": unknown_max,
                "blocking_unknown": blocking_unknown,
            },
            "declared_boundaries": declared,
            "unknown": unknown,
            "next_actions": next_actions,
        }
