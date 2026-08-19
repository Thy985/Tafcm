"""Capability Adapter 统一契约（ADR-0030 五方法）。

orchestrator 核心能力无关：只调用这些方法 + 聚合 Evidence Graph。
新 capability = 新 Adapter 文件，核心零改动（杜绝巨型 if/else）。
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

from ..evidence import EvidenceGraph


class CapabilityAdapter(ABC):
    id: str = ""

    def __init__(self, contract: dict[str, Any]) -> None:
        self.contract = contract

    @abstractmethod
    def discover(self, graph: EvidenceGraph) -> None:
        """环境探测：工具/运行时是否可用（缺失 → 抛 EnvironmentError → 127）。"""

    @abstractmethod
    def prepare(self, graph: EvidenceGraph) -> None:
        """准备 corpus / 输出目录（只读，不写仓库源码）。"""

    @abstractmethod
    def execute(self, graph: EvidenceGraph) -> None:
        """跑真实生产路径（经 Runtime Bridge / Producer Bridge）。"""

    @abstractmethod
    def collect_evidence(self, graph: EvidenceGraph) -> None:
        """聚合所有 stage 证据到 graph。"""

    @abstractmethod
    def evaluate(self, graph: EvidenceGraph) -> dict[str, Any]:
        """对照 contract 判定 → {status, coverage, unknown, next_actions}。"""
