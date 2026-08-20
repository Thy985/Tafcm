"""Word Capability Adapter — P0.1 第 3 个能力（consumer adapter 扩展 D3）。

证据链：discover(工具探测) → prepare(out_dir) → execute(docx_qa audit：
真实 WPS/OfficeCLI consumer 验证产物) → collect_evidence → evaluate。

复用 docx_qa.audit_docx（ffx analyze audit 核心）作为 metrics 来源：
- artifact_integrity（OOXML/rels/semantic）
- wps_compatibility（word2pdf/pdfinfo/pdf2txt）
- wps_semantic_text.formula_fidelity（公式内容保真，DOGFOOD-RUN-004 修复）
- officecli_issues（结构化问题）

注意：word capability 验证需真实 docx 产物——本轮用 D:/Temp/word_consumer
下的既有产物（cap_word_fix.docx 等）作为 corpus；完整「输入 md → 导出 →
消费端验证」链路需 WordExporter runner（3.10.3 后续轮）。
"""
from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ..contract import repo_root
from ..evidence import Evidence, EvidenceGraph
from .base import CapabilityAdapter

# word corpus：既有真实导出产物（DOGFOOD-RUN-004 等已生成）
_CORPUS_CANDIDATES = [
    "D:/Temp/word_consumer/cap_word_fix.docx",
    "D:/Temp/word_consumer/cap_word_f_visual.docx",
]


class WordAdapter(CapabilityAdapter):
    id = "word"

    def __init__(self, contract: dict[str, Any]) -> None:
        super().__init__(contract)
        self._out_dir: Path | None = None
        self._metrics: dict[str, Any] = {}
        self._audit: dict[str, Any] = {}

    def discover(self, graph: EvidenceGraph) -> None:
        from cli_anything.ffx.core import docx_qa

        wps = docx_qa._find_wpscli()
        officecli = docx_qa._find_officecli()
        graph.add(
            Evidence(
                stage="discover",
                tool="ffx",
                exit_code=0,
                summary=f"wpscli={'ok' if wps else 'missing'}; officecli={'ok' if officecli else 'missing'}",
                detail={"wpscli": bool(wps), "officecli": bool(officecli)},
            )
        )

    def prepare(self, graph: EvidenceGraph) -> None:
        root = repo_root()
        out = root / ".ffx" / "tmp" / "verify" / f"word-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
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
        from cli_anything.ffx.core import docx_qa

        # ENV_MISSING（G4.4，2026-08-20）：wpscli 未安装 = 环境缺失（exit 127），
        # 非能力 FAIL——orchestrator 捕获 EnvironmentError → status=env_missing。
        # （wps consumer 验证（word2pdf/pdf2txt）必须真实调用 wpscli，缺则无法执行）
        wpscli = docx_qa._find_wpscli()
        if wpscli is None:
            raise EnvironmentError(
                "wpscli not installed (word consumer verification requires it: "
                "word2pdf/pdfinfo/pdf2txt) — ENV_MISSING, not a capability failure"
            )

        # 取第一个可用的 corpus 产物（真实 docx）
        corpus = next((p for p in _CORPUS_CANDIDATES if Path(p).is_file()), None)
        if corpus is None:
            graph.add(
                Evidence(
                    stage="execute",
                    tool="docx-qa",
                    exit_code=127,
                    summary="no word corpus available",
                    detail={"corpus": None},
                )
            )
            self._metrics = {"corpus_missing": True}
            return

        audit = docx_qa.audit_docx(Path(corpus))
        self._audit = audit
        st = audit.get("details", {}).get("wps_semantic_text", {})
        ff = st.get("formula_fidelity", {})
        self._metrics = {
            "corpus": corpus,
            "artifact_integrity": audit.get("artifact_integrity", "fail"),
            "semantic_fidelity": audit.get("semantic_fidelity", "fail"),
            "wps_compatibility": audit.get("wps_compatibility", "unknown"),
            "formula_fidelity_ok": ff.get("ok", False),
            "formula_missing": ff.get("missing_in_consumer", []),
            "consumer_text_status": st.get("status", "unknown"),
            "officecli_issue_count": audit.get("details", {}).get("officecli_issues", {}).get("issue_count", 0),
        }
        graph.add(
            Evidence(
                stage="execute",
                tool="docx-qa",
                exit_code=0,
                summary=f"corpus={corpus} wps={audit.get('wps_compatibility')} formula_ok={ff.get('ok')}",
                artifact=str(Path(corpus)),
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
        wps_required = bool(policy.get("wps_consumer_required", True))
        formula_required = bool(policy.get("formula_fidelity_required", True))

        if self._metrics.get("corpus_missing"):
            return {
                "status": "inconclusive",
                "coverage": {"checks": {"corpus": False}},
                "declared_boundaries": self.contract.get("s0_unsupported", []),
                "unknown": ["no word corpus available (D:/Temp/word_consumer)"],
                "next_actions": ["provide docx corpus (e.g. cap_word_fix.docx) and re-run"],
            }

        checks = {
            "artifact_integrity": self._metrics.get("artifact_integrity") == "pass",
            "wps_consumer": (
                not wps_required
                or self._metrics.get("wps_compatibility") == "pass"
            ),
            "formula_fidelity": (
                not formula_required
                or self._metrics.get("formula_fidelity_ok") is True
            ),
            "no_consumer_error": (
                self._metrics.get("consumer_text_status") != "fail"
            ),
        }
        failed = [k for k, v in checks.items() if not v]
        declared = list(self.contract.get("s0_unsupported", []))
        unknown: list[str] = []
        if self._metrics.get("wps_compatibility") == "unknown":
            unknown.append("wps not installed (consumer evidence gap)")
        if self._metrics.get("officecli_issue_count", 0) > 0:
            unknown.append(
                f"officecli issues: {self._metrics.get('officecli_issue_count')}"
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
                "wps_compatibility": self._metrics.get("wps_compatibility"),
                "formula_fidelity": self._metrics.get("formula_fidelity_ok"),
                "officecli_issues": self._metrics.get("officecli_issue_count"),
            },
            "declared_boundaries": declared,
            "unknown": unknown,
            "next_actions": next_actions,
        }
