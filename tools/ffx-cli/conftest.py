"""pytest 全局配置（tools/ffx-cli 测试套件）。

test_full_e2e 以子进程调用 ffx CLI——中文 Windows 默认 GBK 管道编码会让
含非 GBK 字符（如 ↔）的 --help 输出抛 UnicodeEncodeError。这里统一给
子进程注入 UTF-8 环境，使验收命令
    cd tools/ffx-cli && python -m pytest cli_anything/ffx/tests/ -v
在任何控制台代码页下确定性地通过（仅作用于测试子进程，不改全局环境）。
"""

from __future__ import annotations

import os
import sys

os.environ.setdefault("PYTHONUTF8", "1")
os.environ.setdefault("PYTHONIOENCODING", "utf-8")

# 当前进程同样受 GBK 影响（pytest 捕获输出走本地编码）
if sys.stdout and getattr(sys.stdout, "encoding", "").lower().replace("-", "") != "utf8":
    try:
        sys.stdout.reconfigure(errors="replace")  # type: ignore[union-attr]
        sys.stderr.reconfigure(errors="replace")  # type: ignore[union-attr]
    except (AttributeError, ValueError):
        pass
