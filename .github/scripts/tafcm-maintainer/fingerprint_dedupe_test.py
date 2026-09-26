#!/usr/bin/env python3
"""fingerprint_dedupe_test.py — Issue #289 注册表去重不变量守门

验证 fingerprint.py 的注册表写入（collapse_and_write）具备**整体去重 + 幂等**：
- 给定含大量重复行的注册表，重建后每个 fingerprint 恰好一行（无重复）
- 对同一 merged 状态重复重建，行数不变（幂等）
- schema（固定头）被正确抽取并保留，数据行被整体替换（非追加）
- 端到端：脏 FINDINGS + 有 finding 的 audit 跑 fingerprint.py，重复被清空

实现策略：纯 stdlib + tempfile，直接 import fingerprint.py 的目标函数；
端到端用 subprocess 调 CLI。CI 入口：
    python3 .github/scripts/tafcm-maintainer/fingerprint_dedupe_test.py
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import fingerprint as fp  # noqa: E402

REGISTRY_MARKER = fp.REGISTRY_MARKER

SCHEMA = (
    "# Tafcm Agent Finding Registry（机器维护，Agent 读取去重）\n\n"
    "> 每行 = 一个稳定 Finding 身份（fingerprint）\n\n"
    "| fingerprint | latest_id | category | evidence | status | issue | first_seen | last_seen |\n"
    "|-------------|-----------|----------|----------|--------|-------|------------|-----------|\n"
)


def row(fingerprint: str, latest_id: str) -> str:
    return ("| {} | {} | tech-debt | e.dart | NEW | N/A | 2026-09-26 | 2026-09-26 |"
            .format(fingerprint, latest_id))


def dirty_registry_rows() -> list[str]:
    """3 个唯一 fingerprint × 各重复 3 次 = 9 行数据（历史膨胀模拟）。"""
    uniq = [row("a1b2c3d4e5f60001", "F-1"),
            row("b2c3d4e5f6000102", "F-2"),
            row("c3d4e5f600010203", "F-3")]
    return uniq * 3


def write_dirty(path: Path) -> None:
    path.write_text(SCHEMA + "".join(r + "\n" for r in dirty_registry_rows())
                    + REGISTRY_MARKER + "\n", encoding="utf-8")


def data_row_count(reg_text: str) -> int:
    return len([l for l in reg_text.splitlines()
                if l.startswith("| ") and "fingerprint" not in l and "latest_id" not in l])


def unique_fingerprints(reg_text: str) -> set[str]:
    result: set[str] = set()
    for line in reg_text.splitlines():
        if not line.startswith("| ") or ("fingerprint" in line and "latest_id" in line):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) >= 8:
            result.add(cells[0])
    return result


def merged_from_rows(rows: list[str]) -> dict[str, dict]:
    merged: dict[str, dict] = {}
    for r in rows:
        cells = [c.strip() for c in r.strip("|").split("|")]
        merged[cells[0]] = {
            "fingerprint": cells[0], "latest_id": cells[1],
            "category": cells[2], "evidence": cells[3],
            "status": cells[4], "issue": cells[5],
            "first_seen": cells[6], "last_seen": cells[7],
        }
    return merged


def test_collapse_idempotent_schema() -> list[str]:
    """collapse_and_write：整体去重、保留 schema、幂等。"""
    errs: list[str] = []
    merged = merged_from_rows(dirty_registry_rows())
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "FINDINGS.md"
        write_dirty(p)
        fp.collapse_and_write(p, merged)
        after1 = p.read_text(encoding="utf-8")

        if data_row_count(after1) != 3:
            errs.append(f"collapse: 重建后数据行应为 3，实际 {data_row_count(after1)}")
        if len(unique_fingerprints(after1)) != 3:
            errs.append(f"collapse: 唯一 fingerprint 应 3，实际 {len(unique_fingerprints(after1))}")
        if "| fingerprint |" not in after1 or "|-------------|" not in after1:
            errs.append("collapse: 固定头（表头/分隔行）未保留")

        # 幂等
        fp.collapse_and_write(p, merged)
        after2 = p.read_text(encoding="utf-8")
        if data_row_count(after2) != 3 or unique_fingerprints(after2) != unique_fingerprints(after1):
            errs.append("collapse: 幂等性破坏（第二次运行改变行数/内容）")

    return errs


def test_end_to_end() -> list[str]:
    """CLI 端到端：脏 FINDINGS + 有 finding 的 audit → 去重且不膨胀。"""
    errs: list[str] = []
    with tempfile.TemporaryDirectory() as td:
        td_p = Path(td)
        reg = td_p / "FINDINGS.md"
        write_dirty(reg)
        audit = td_p / "2026-09-26-maintainer-audit.md"
        audit.write_text(
            "# Tafcm Daily Maintainer Audit\n"
            "## New Findings\n"
            "### F-2026-09-26-01\n"
            "Category: bug\nSeverity: P2\nConfidence: Medium\nStatus: NEW\n"
            "Summary: dedup e2e\nEvidence: e2e_test.dart\nImpact: low\n"
            "Recommendation: fix\nRelated Issue: N/A\n"
            "## Existing Issue Updates\nNone.\n"
            "## Ecosystem Findings\nNo significant ecosystem findings.\n"
            "## Pending Decisions\nNone.\n",
            encoding="utf-8",
        )
        env = dict(os.environ)
        env["PYTHONIOENCODING"] = "utf-8"
        r = subprocess.run(
            [sys.executable, str(HERE / "fingerprint.py"), str(audit), str(reg)],
            capture_output=True, text=True, env=env, timeout=60,
        )
        if r.returncode != 0:
            errs.append(f"end-to-end: fingerprint.py 退出 {r.returncode}: {r.stderr[:200]}")
            return errs
        final = reg.read_text(encoding="utf-8")
        # 3 初始唯一 + 1 新 finding = 4；若是"追加"语义会是 9+1
        if len(unique_fingerprints(final)) != 4:
            errs.append(f"end-to-end: 唯一 fingerprint 应 4，实际 {len(unique_fingerprints(final))}（重复未清空）")
    return errs


def main() -> int:
    errs: list[str] = []
    errs.extend(test_collapse_idempotent_schema())
    errs.extend(test_end_to_end())
    if errs:
        print("\n".join(errs))
        print(f"\n{len(errs)} fingerprint dedup test(s) failed")
        return 1
    print("OK: fingerprint registry dedup invariants satisfied (Issue #289)")
    return 0


if __name__ == "__main__":
    sys.exit(main())