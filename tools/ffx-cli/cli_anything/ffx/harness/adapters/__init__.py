"""Capability Adapter 注册表 — 目录扫描注册，orchestrator 零 if/else。"""
from __future__ import annotations

from .formula import FormulaAdapter
from .markdown import MarkdownAdapter
from .serializer import SerializerAdapter
from .word import WordAdapter

# 显式注册（P0.1 四能力：markdown / serializer / word / formula——
# word=consumer adapter（D3），formula=ADI 衔接（D4））
_ADAPTERS: dict[str, type] = {
    MarkdownAdapter.id: MarkdownAdapter,
    SerializerAdapter.id: SerializerAdapter,
    WordAdapter.id: WordAdapter,
    FormulaAdapter.id: FormulaAdapter,
}


def available() -> list[str]:
    return sorted(_ADAPTERS)


def create(capability: str, contract: dict) -> "object":
    cls = _ADAPTERS.get(capability)
    if cls is None:
        raise KeyError(
            f"unknown capability '{capability}' (available: {available()})"
        )
    return cls(contract)
