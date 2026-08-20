"""Capability Adapter 注册表 — 目录扫描注册，orchestrator 零 if/else。"""
from __future__ import annotations

from .assets import (
    AutosaveAdapter,
    BlockAdapter,
    FileAdapter,
    ImeAdapter,
    PdfAdapter,
    ThemeAdapter,
    UndoAdapter,
)
from .formula import FormulaAdapter
from .markdown import MarkdownAdapter
from .serializer import SerializerAdapter
from .word import WordAdapter

# 显式注册（P0.1 十一能力：markdown/serializer/word/formula 独立 runner，
# undo/pdf/autosave/file/ime/theme/block 为测试资产引用型——Full Capability Re-Audit）
_ADAPTERS: dict[str, type] = {
    MarkdownAdapter.id: MarkdownAdapter,
    SerializerAdapter.id: SerializerAdapter,
    WordAdapter.id: WordAdapter,
    FormulaAdapter.id: FormulaAdapter,
    UndoAdapter.id: UndoAdapter,
    PdfAdapter.id: PdfAdapter,
    AutosaveAdapter.id: AutosaveAdapter,
    FileAdapter.id: FileAdapter,
    ImeAdapter.id: ImeAdapter,
    ThemeAdapter.id: ThemeAdapter,
    BlockAdapter.id: BlockAdapter,
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
