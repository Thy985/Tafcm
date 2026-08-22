r"""RUN-016 验证 harness——VLM 结构化描述 → 确定性三态判定。

用法（在 tools/ffx-cli 下）：
  # 为 corpus 中缺 description.json 的 case 生成描述（需本地 Qwen2-VL）
  python scripts/run016_validate.py --describe

  # 只跑判定表（离线，消费已入库描述）
  python scripts/run016_validate.py

  # 强制重新生成全部描述
  python scripts/run016_validate.py --describe --refresh
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HARNESS_DIR = Path(__file__).resolve().parents[1] / "cli_anything" / "ffx" / "harness"
sys.path.insert(0, str(HARNESS_DIR.parent.parent.parent))

from cli_anything.ffx.harness.e8_structure import evaluate_structure  # noqa: E402
from cli_anything.ffx.harness.e8_vlm import describe_structure  # noqa: E402

CORPUS_DIR = HARNESS_DIR / "vlm_corpus"


def _cases() -> list[Path]:
    return sorted(p for p in CORPUS_DIR.iterdir() if p.is_dir())


def cmd_describe(refresh: bool) -> None:
    for case in _cases():
        screenshot = case / "screenshot.png"
        desc_file = case / "description.json"
        if desc_file.exists() and not refresh:
            print(f"[skip] {case.name} (description exists)")
            continue
        if not screenshot.exists():
            print(f"[miss] {case.name}: no screenshot.png")
            continue
        print(f"[vlm] {case.name}: describing {screenshot.name} ...", flush=True)
        desc = describe_structure(str(screenshot))
        desc_file.write_text(
            json.dumps(desc, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(
            f"       confidence={desc.get('confidence')} "
            f"issues={desc.get('issues')}"
        )


def cmd_verify() -> int:
    failures = 0
    rows = []
    for case in _cases():
        meta_file = case / "meta.json"
        desc_file = case / "description.json"
        if not meta_file.exists():
            continue
        meta = json.loads(meta_file.read_text(encoding="utf-8"))
        if not desc_file.exists():
            rows.append((case.name, meta["expect_status"], "—", "NO DESCRIPTION"))
            failures += 1
            continue
        desc = json.loads(desc_file.read_text(encoding="utf-8"))
        result = json.loads(
            evaluate_structure(meta["expected_latex"], desc)
        )
        ok = result["status"] == meta["expect_status"]
        if not ok:
            failures += 1
        detail = result.get("note") or "; ".join(result["diff_details"][:2])
        rows.append(
            (
                case.name,
                meta["expect_status"],
                result["status"],
                ("OK" if ok else "MISMATCH") + f" ({result['error_type']}) {detail}"[:110],
            )
        )
    width = max(len(r[0]) for r in rows) + 2
    print(f"{'case':<{width}}{'expected':<15}{'got':<15}detail")
    print("-" * (width + 100))
    for name, expect, got, detail in rows:
        print(f"{name:<{width}}{expect:<15}{got:<15}{detail}")
    print("-" * (width + 100))
    total = len(rows)
    print(f"{total - failures}/{total} cases match expected verdict")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--describe", action="store_true", help="生成缺失的描述")
    parser.add_argument("--refresh", action="store_true", help="强制重新生成描述")
    args = parser.parse_args()
    if args.describe or args.refresh:
        cmd_describe(args.refresh)
        print()
    return cmd_verify()


if __name__ == "__main__":
    raise SystemExit(main())
