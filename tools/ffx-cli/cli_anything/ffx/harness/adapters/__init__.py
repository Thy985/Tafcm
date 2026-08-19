"""Capability Adapter 注册表 — 目录扫描注册，orchestrator 零 if/else。"""
from __future__ import annotations

from .markdown import MarkdownAdapter
from .serializer import SerializerAdapter

# 显式注册（P0.1 双能力：markdown + serializer——serializer 提供跨能力
# 回归对比的第 2 个 capability，REGRESSION path 前置）
_ADAPTERS: dict[str, type] = {
    MarkdownAdapter.id: MarkdownAdapter,
    SerializerAdapter.id: SerializerAdapter,
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
