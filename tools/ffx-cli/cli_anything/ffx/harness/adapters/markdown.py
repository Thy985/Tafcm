"""Markdown Capability Adapter — P0.1。

证据链：discover(flutter 可用) → prepare(corpus/out) → execute(Runtime Bridge →
真实 MarkdownParser/Serializer round-trip) → collect → evaluate(对照契约)。
"""
from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .. import runtime_bridge
from ..contract import repo_root
from ..evidence import Evidence, EvidenceGraph
from .base import CapabilityAdapter


class MarkdownAdapter(CapabilityAdapter):
    id = "markdown"

    def __init__(self, contract: dict[str, Any]) -> None:
        super().__init__(contract)
        self._corpus_dir: str | None = None
        self._out_dir: Path | None = None
        self._metrics: dict[str, Any] = {}
        self._runner_result: dict[str, Any] = {}

    def discover(self, graph: EvidenceGraph) -> None:
        root = repo_root()
        runner = root / "flutter_app" / "tool" / "capability_runner" / "capability_runner_test.dart"
        if not runner.is_file():
            graph.add(Evidence(
                "discover", "ffx", 127,
                f"runner missing: {runner}", artifact=str(runner),
            ))
            raise EnvironmentError(f"runner missing: {runner}")
        graph.add(Evidence("discover", "ffx", 0, f"repo root={root}; runner present"))

    def prepare(self, graph: EvidenceGraph) -> None:
        ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        root = repo_root()
        self._out_dir = root / ".ffx" / "tmp" / "verify" / f"markdown-{ts}"
        self._out_dir.mkdir(parents=True, exist_ok=True)
        corpus = root / ".ffx" / "corpus" / "markdown"
        if corpus.is_dir() and any(corpus.glob("*.md")):
            self._corpus_dir = str(corpus)
            graph.add(Evidence("prepare", "ffx", 0, f"corpus={corpus}", artifact=str(corpus)))
        else:
            graph.add(Evidence("prepare", "ffx", 0, "corpus absent → built-in corpus"))
        graph.add(Evidence("prepare", "ffx", 0, f"out_dir={self._out_dir}", artifact=str(self._out_dir)))

    def execute(self, graph: EvidenceGraph) -> None:
        result = runtime_bridge.run_markdown(self._corpus_dir, self._out_dir)  # type: ignore[arg-type]
        self._runner_result = result
        self._metrics = result.get("metrics", {})
        graph.add(Evidence(
            "execute", "dart-runner", 0,
            f"files={self._metrics.get('files')} roundtrip_conv={self._metrics.get('roundtrip_convergence')}",
            artifact=str(self._out_dir / "result.json"),
            detail=result,
        ))

    def collect_evidence(self, graph: EvidenceGraph) -> None:
        # execute 已写入 graph；此处补充契约相关元信息
        policy = self.contract.get("completion_policy", {})
        graph.add(Evidence(
            "collect", "ffx", 0,
            f"policy={policy}; s0={self.contract.get('s0_unsupported')}",
            detail={"policy": policy, "s0_unsupported": self.contract.get("s0_unsupported")},
        ))

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

        # R4 修复：required_checks 声明 4 项（parse/serialize/roundtrip/
        # no_parse_error），此前 serialize 被遗漏。
        # serialize 指标：runner 无独立计数，用 roundtrip_converged > 0
        # 作为「serialize 至少执行成功一次」的代理（round-trip 流程内含
        # MarkdownSerializer.serialize，抛异常则整体失败）。
        checks = {
            "parse": files > 0 and int(self._metrics.get("parse_ok", 0)) == files,
            "serialize": converged > 0,
            "roundtrip": conv >= conv_min,
            "no_parse_error": line_errors <= err_max,
        }
        failed = [k for k, v in checks.items() if not v]
        # R6 修复：区分「声明边界」（s0_unsupported，产品明确不支持的语法）
        # 与「证据缺口」（unknown，运行时未能产生证据的真实缺口）。
        # 此前 unknown = s0 无条件赋值，命名误导——真证据缺口与声明边界混为一谈。
        declared = list(self.contract.get("s0_unsupported", []))
        unknown: list[str] = []
        if not self._metrics:
            unknown.append("no runner metrics (evidence gap)")
        elif files == 0:
            unknown.append("runner reported 0 files (evidence gap)")

        # R3 修复：契约级 unknown 控制
        #   blocking_unknown 命中 → 阻断（fail）
        #   unknown 数超 unknown_max → 溢出（fail）
        blocked = [u for u in declared + unknown if u in blocking_unknown]
        overflow = len(declared) + len(unknown) > unknown_max

        status = "pass"
        if not self._metrics or files == 0:
            status = "inconclusive"  # 证据不足/未判定（真机缺失、视觉未判等 → ADR-0030 exit 3）
        elif failed or blocked or overflow:
            status = "fail"
        elif declared or unknown:
            status = "warn"  # 达标但有非阻断 Unknown（S0 边界 / 证据缺口）

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
        # R14 修复：pass 时 next_actions 非空——Agent 调用方不应把
        # 「空任务列表」误判为「无需跟进」，显式声明无需动作。
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
