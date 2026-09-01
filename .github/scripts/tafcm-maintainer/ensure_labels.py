#!/usr/bin/env python3
"""ensure_labels.py — 确保 Maintainer Agent Issue 标签存在（幂等）

创建 Issue 前必须存在的标签（SCHEMA.md §3）：
  - source:agent
  - type:bug / type:regression / type:test-gap / type:architecture / type:ecosystem
  - priority:P0 / priority:P1 / priority:P2 / priority:P3

已在仓库存在的标签不重复创建（复用仓库 label 约定）。
依赖：gh CLI（workflow runner 预装，GITHUB_TOKEN 注入）。
"""
from __future__ import annotations

import subprocess
import sys

REPO = "Thy985/Tafcm"

LABELS = [
    ("source:agent", "c2e0c6", "Maintainer Agent 自动创建"),
    ("type:bug", "d73a4a", "Agent: bug"),
    ("type:regression", "b60205", "Agent: 回归风险"),
    ("type:test-gap", "0e8a16", "Agent: 测试缺口"),
    ("type:architecture", "5319e7", "Agent: 架构漂移"),
    ("type:ecosystem", "1d76db", "Agent: 生态/依赖风险"),
    ("priority:P0", "b60205", "Agent: 阻塞/紧急"),
    ("priority:P1", "d93f0b", "Agent: 高优先级"),
    ("priority:P2", "fbca04", "Agent: 中优先级"),
    ("priority:P3", "c5def5", "Agent: 低优先级"),
]


def gh(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["gh", *args], capture_output=True, text=True)


def main() -> int:
    # 获取现有标签
    existing = gh("label", "list", "-R", REPO, "--json", "name", "--jq", ".[].name")
    if existing.returncode != 0:
        print(f"FAIL: gh label list 失败: {existing.stderr.strip()}", file=sys.stderr)
        return 1
    existing_names = set(existing.stdout.splitlines())

    created = 0
    for name, color, desc in LABELS:
        if name in existing_names:
            continue
        r = gh("label", "create", name, "-R", REPO,
               "--color", color, "--description", desc)
        if r.returncode != 0:
            print(f"WARN: 创建标签失败（可能并发已建）: {name}: {r.stderr.strip()}",
                  file=sys.stderr)
            continue
        created += 1
        print(f"✅ 创建标签: {name}")

    print(f"ensure_labels: 已有 {len(existing_names)} 个，新建 {created} 个")
    return 0


if __name__ == "__main__":
    sys.exit(main())
