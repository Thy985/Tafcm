"""Capability Adapter 注册表 — 目录扫描注册，orchestrator 零 if/else。"""
from __future__ import annotations

from .markdown import MarkdownAdapter

# 显式注册（P0.1 单能力；后续可按目录扫描自动发现，核心逻辑不变）
_ADAPTERS: dict[str, type] = {
    MarkdownAdapter.id: MarkdownAdapter,
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
