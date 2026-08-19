"""Evidence Graph — 每 stage 证据的统一记录。

evidence = (stage, tool, exit_code, artifact, summary, detail)
FFX 只做证据收集与聚合；判定由 Capability Adapter.evaluate 对照契约完成。
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass
class Evidence:
    stage: str
    tool: str
    exit_code: int
    summary: str
    artifact: str | None = None
    detail: dict[str, Any] | None = None


class EvidenceGraph:
    """有序证据链；最终并入 Capability Report 与 Failure Record。"""

    def __init__(self) -> None:
        self._items: list[Evidence] = []

    def add(self, ev: Evidence) -> Evidence:
        self._items.append(ev)
        return ev

    def all(self) -> list[Evidence]:
        return list(self._items)

    def to_list(self) -> list[dict[str, Any]]:
        return [asdict(e) for e in self._items]

    def latest(self, stage: str) -> Evidence | None:
        for e in reversed(self._items):
            if e.stage == stage:
                return e
        return None
