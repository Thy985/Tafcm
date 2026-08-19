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

        files = int(self._metrics.get("files", 0))
        conv = float(self._metrics.get("roundtrip_convergence", 0.0))
        line_errors = int(self._metrics.get("line_errors", -1))

        checks = {
            "parse": files > 0 and int(self._metrics.get("parse_ok", 0)) == files,
            "roundtrip": conv >= conv_min,
            "no_parse_error": line_errors <= err_max,
        }
        failed = [k for k, v in checks.items() if not v]
        s0 = list(self.contract.get("s0_unsupported", []))
        unknown = s0  # S0 能力 = 明确的宣称边界（非阻断）

        status = "pass"
        if not self._metrics or files == 0:
            status = "inconclusive"  # 证据不足/未判定（真机缺失、视觉未判等 → ADR-0030 exit 3）
        elif failed:
            status = "fail"
        elif unknown:
            status = "warn"  # 达标但有非阻断 Unknown（S0 边界）

        next_actions: list[str] = []
        if failed:
            next_actions.append(f"failed checks: {failed}")
        if s0:
            next_actions.append(f"decide S0 scope: {s0}")

        return {
            "status": status,
            "coverage": {"roundtrip_convergence": conv, "checks": checks},
            "unknown": unknown,
            "next_actions": next_actions,
        }
