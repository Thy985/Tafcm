"""Capability Contract 加载与校验。

contracts/*.json 是机器真相源（ADR-0030），Feature Capability Matrix 是其派生投影。
本模块按 capability 名扫描 contracts/ 目录并校验必填字段。
"""
from __future__ import annotations

import json
from pathlib import Path

_REQUIRED_KEYS = ("id", "capability", "required_checks", "completion_policy")


class ContractError(Exception):
    """契约缺失或非法。"""


def repo_root() -> Path:
    """从 cwd 向上找含 flutter_app/ 的仓库根（与 utils.helpers.find_flutter_root 一致）。

    R11 修复：不再硬编码向上 6 层——逐级向上直到文件系统根，
    深度克隆 / CI 深工作树也能定位。
    """
    cwd = Path.cwd()
    parent = cwd
    while True:
        if (parent / "flutter_app").is_dir():
            return parent
        if parent.parent == parent:  # 到达文件系统根
            break
        parent = parent.parent
    raise ContractError(f"repo root not found (flutter_app/ missing upward from {cwd})")


def contracts_dir() -> Path:
    return repo_root() / "contracts"


def load_contract(capability: str) -> dict:
    """按 capability 名扫描 contracts/*.json；匹配 capability 字段。"""
    d = contracts_dir()
    if not d.is_dir():
        raise ContractError(f"contracts dir missing: {d}")
    matched = []
    for f in sorted(d.glob("*.json")):
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        if data.get("capability") == capability:
            matched.append(data)
    if not matched:
        raise ContractError(
            f"no contract found for capability '{capability}' under {d}"
        )
    contract = matched[0]
    _validate(contract, capability)
    return contract


def _validate(contract: dict, capability: str) -> None:
    missing = [k for k in _REQUIRED_KEYS if k not in contract]
    if missing:
        raise ContractError(
            f"contract for '{capability}' missing required keys: {missing}"
        )
    policy = contract["completion_policy"]
    if not isinstance(policy, dict) or not policy:
        raise ContractError(f"contract for '{capability}' has empty completion_policy")
