"""Runtime Bridge — FFX 调用真实 FormulaFix production path 的唯一通道。

禁止 Python 侧重实现解析/导出逻辑；本模块只做 subprocess 编排：
  flutter test tool/capability_runner/capability_runner_test.dart
（block_serializer → block_types 链依赖 Flutter foundation/dart:ui，
 必须跑在 Flutter 运行时，故用 flutter test 环境承载。）

退出码语义（ADR-0030）：环境缺失 → RuntimeBridgeError(127)；
runner 自身失败 → RuntimeBridgeError(1)。
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from .contract import repo_root

_RUNNER = "tool/capability_runner/capability_runner_test.dart"
# R8 修复：timeout 可配置（env FFX_RUNNER_TIMEOUT_S 覆盖；corpus 增长时无需改代码）
_DEFAULT_TIMEOUT_S = 300


def _runner_timeout() -> int:
    raw = os.environ.get("FFX_RUNNER_TIMEOUT_S", str(_DEFAULT_TIMEOUT_S))
    try:
        return max(30, int(raw))
    except ValueError:
        return _DEFAULT_TIMEOUT_S


class RuntimeBridgeError(Exception):
    """运行时桥接失败。code: 1 = runner 失败, 127 = 环境缺失。"""

    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code


def _flutter() -> str:
    exe = shutil.which("flutter")
    if exe is None:
        raise RuntimeBridgeError(127, "flutter not found on PATH (ENV_MISSING)")
    return exe


def run_markdown(corpus_dir: str | None, out_dir: Path) -> dict:
    """调用真实 MarkdownParser/Serializer，返回 result.json 内容。"""
    root = repo_root()
    flutter_app = root / "flutter_app"
    if not (flutter_app / _RUNNER).is_file():
        raise RuntimeBridgeError(1, f"runner missing: {flutter_app / _RUNNER}")

    out_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    if corpus_dir:
        env["FFX_CORPUS_DIR"] = corpus_dir
    env["FFX_OUT_DIR"] = str(out_dir)

    # G7（2026-08-20）：regression cases 自动挂载——内置/显式 corpus 之外，
    # 追加 tests/verification_cases/<cap>/corpus/ 的 Golden Failure 触发输入。
    regression_dir = root / "tests" / "verification_cases" / "markdown" / "corpus"
    if regression_dir.is_dir():
        env["FFX_REGRESSION_DIR"] = str(regression_dir)

    cmd = [_flutter(), "test", _RUNNER]
    timeout_s = _runner_timeout()
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(flutter_app),
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout_s,
        )
    except subprocess.TimeoutExpired:
        raise RuntimeBridgeError(1, f"runner timed out after {timeout_s}s") from None

    # R9 修复：失败时保留尾部上下文；成功路径也输出简短摘要（调试可观测）
    if proc.returncode != 0:
        raise RuntimeBridgeError(
            1, f"runner exited {proc.returncode}\n{proc.stdout[-2000:]}{proc.stderr[-2000:]}"
        )
    tail = (proc.stdout or "")[-500:].strip().replace("\n", " | ")
    # R9 修复：可观测输出走 stderr——不污染 stdout（--json 管道纯净）
    print(f"[runtime-bridge] runner ok ({timeout_s}s budget); stdout tail: {tail}", file=sys.stderr)
    result_path = out_dir / "result.json"
    if not result_path.is_file():
        raise RuntimeBridgeError(1, "runner succeeded but result.json missing")
    return json.loads(result_path.read_text(encoding="utf-8"))


def run_flutter_tests(test_globs: list[str], out_dir: Path) -> dict:
    """跑指定 Flutter 测试文件 → 真实 pass/fail metrics（3.11.1：替代资产扫描）。

    Phase 3.11 独立 runner 化：metrics 来自真实 `flutter test <files>` 执行
    （非「测试资产存在」）——每个能力跑对应测试文件，聚合真实通过/失败数。
    返回 {exit_code, files, passed, skipped, failed, tail}。
    """
    import re

    root = repo_root()
    flutter_app = root / "flutter_app"
    out_dir.mkdir(parents=True, exist_ok=True)

    # 解析 globs → 实际测试文件（相对 flutter_app/，去重保序）
    test_files: list[str] = []
    for g in test_globs:
        for m in sorted(flutter_app.glob(g)):
            if m.is_file() and m.suffix == ".dart":
                rel = str(m.relative_to(flutter_app)).replace("\\", "/")
                if rel not in test_files:
                    test_files.append(rel)
    if not test_files:
        # 3.11.1：空匹配（无 test/ 可跑文件，如 autosave/theme 仅 integration_test/
        # golden）不抛异常——返回 files=0，由 adapter 判 warn（证据缺口）而非 fail。
        return {
            "exit_code": 0,
            "files": 0,
            "passed": 0,
            "skipped": 0,
            "failed": 0,
            "artifact": str(out_dir),
            "tail": "no test files matched",
        }

    env = os.environ.copy()
    env["FFX_OUT_DIR"] = str(out_dir)
    cmd = [_flutter(), "test", *test_files, "--reporter", "compact"]
    # encoding 显式 UTF-8：中文 Windows 默认 GBK 解码 flutter 输出会在读线程
    # 抛 UnicodeDecodeError → stdout 整体丢失（metrics 全 0 的静默盲跑）
    timeout_s = _runner_timeout()
    try:
        proc = subprocess.run(
            cmd, cwd=str(flutter_app), env=env,
            capture_output=True, text=True,
            encoding="utf-8", errors="replace",
            timeout=timeout_s,
        )
    except subprocess.TimeoutExpired:
        raise RuntimeBridgeError(1, f"tests timed out after {timeout_s}s") from None

    out = proc.stdout or ""
    # compact reporter 多文件输出：每个文件一行 '+N ~M -K:'，
    # 最后一行是总汇总——取 findall 的最后一个（3.11.1 修复：
    # 原 re.search 取第一个可能命中中间状态或非汇总行 → passed=0）。
    matches = re.findall(r"\+(\d+)(?:\s~(\d+))?(?:\s-(\d+))?", out)
    if matches:
        m = matches[-1]
        passed = int(m[0])
        skipped = int(m[1]) if m[1] else 0
        failed = int(m[2]) if m[2] else 0
    else:
        passed = 0
        skipped = 0
        failed = 1 if proc.returncode != 0 else 0

    result = {
        "exit_code": proc.returncode,
        "files": len(test_files),
        "passed": passed,
        "skipped": skipped,
        "failed": failed,
        "artifact": str(out_dir),
        "tail": out[-300:].strip(),
    }
    print(
        f"[runtime-bridge] tests ok: {passed} passed / {failed} failed / "
        f"{skipped} skipped ({len(test_files)} files)",
        file=sys.stderr,
    )
    return result
