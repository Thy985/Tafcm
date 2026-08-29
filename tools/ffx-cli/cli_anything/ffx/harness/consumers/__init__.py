"""harness/consumers 包：外部 CLI 消费端薄封装（ADR-0030 §3.4）。

统一归一化输出 {exit_code, summary, issues}，不重实现引擎。
"""
from .base import ConsumerResult, run_cmd

__all__ = ["ConsumerResult", "run_cmd"]
