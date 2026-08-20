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
    print(f"[runtime-bridge] runner ok ({timeout_s}s budget); stdout tail: {tail}")
    result_path = out_dir / "result.json"
    if not result_path.is_file():
        raise RuntimeBridgeError(1, "runner succeeded but result.json missing")
    return json.loads(result_path.read_text(encoding="utf-8"))
