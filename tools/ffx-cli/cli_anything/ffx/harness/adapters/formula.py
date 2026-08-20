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
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ..contract import repo_root
from ..evidence import Evidence, EvidenceGraph
from .base import CapabilityAdapter

# RenderOverflow 等渲染失败观察的 ADI 存储
ADI_OBSERVATIONS = ".adi/observations"
_RENDER_ERROR_KEYWORDS = ("RenderOverflow", "RenderFlex", "overflowed")


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
        graph.add(
            Evidence(
                stage="execute",
                tool="adi",
                exit_code=0 if not render_failures else 1,
                summary=f"render_failures={len(render_failures)} latest={latest_obs.get('id') if latest_obs else None}",
                detail={
                    "capability": self.id,
                    "render_failures": render_failures[:5],
                },
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
        render_error_max = int(policy.get("render_error_max", 0))
        adi_required = bool(policy.get("adi_binding_required", True))

        failures = self._metrics.get("render_failures", [])
        checks = {
            "no_adi_render_failure": len(failures) <= render_error_max,
            "render_observable": (
                not adi_required
                or self._metrics.get("latest_observation") is not None
            ),
        }
        failed = [k for k, v in checks.items() if not v]
        declared = list(self.contract.get("s0_unsupported", []))
        unknown: list[str] = []
        if self._metrics.get("latest_observation") is None:
            unknown.append("no ADI observation available (evidence gap)")

        status = "pass"
        if not self._metrics:
            status = "inconclusive"
        elif failed:
            status = "fail"
        elif declared or unknown:
            status = "warn"

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
                    self._metrics.get("latest_observation", {}).get("id")
                ),
            },
            "declared_boundaries": declared,
            "unknown": unknown,
            "next_actions": next_actions,
        }
