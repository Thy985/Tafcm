"""Failure Record — 失败证据的持久化真相源。

ADR-0030 不变量：diagnostic_id 必须引用真实 Failure Record。
- trc_XXXX: 来自 ADI 既有 trace（运行时/链路失败）
- art_XXXX: 来自 FFX Artifact Failure Record（产物/验证失败，无 ADI trace）
禁止仅为报告生成虚拟 ID。
"""
from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path

from .contract import repo_root

_STATE_DIR = ".ffx"
_FAILURES_DIR = "failures"

_ID_RE = re.compile(r"^(trc|art)_(\d{4})$")


def failures_dir() -> Path:
    return repo_root() / _STATE_DIR / _FAILURES_DIR


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def next_artifact_id() -> str:
    """生成下一个 art_XXXX（扫描现有 Failure Records，取 max+1）。"""
    d = failures_dir()
    d.mkdir(parents=True, exist_ok=True)
    max_n = 0
    for f in d.glob("art_*.json"):
        m = _ID_RE.match(f.stem)
        if m and m.group(1) == "art":
            max_n = max(max_n, int(m.group(2)))
    return f"art_{max_n + 1:04d}"


def write_failure(record: dict) -> str:
    """持久化 Failure Record，返回其 id。record 必须含 'id'。"""
    fid = record.get("id")
    if not fid or not _ID_RE.match(fid):
        raise ValueError(f"invalid failure id: {fid!r}")
    d = failures_dir()
    d.mkdir(parents=True, exist_ok=True)
    record.setdefault("created_at", _now())
    (d / f"{fid}.json").write_text(
        json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return fid


def load_failure(failure_id: str) -> dict:
    """按 id 加载 Failure Record；不存在则抛 FileNotFoundError。"""
    if not _ID_RE.match(failure_id):
        raise FileNotFoundError(f"malformed failure id: {failure_id!r}")
    p = failures_dir() / f"{failure_id}.json"
    if not p.is_file():
        raise FileNotFoundError(f"failure record not found: {p}")
    return json.loads(p.read_text(encoding="utf-8"))


def list_failures() -> list[str]:
    d = failures_dir()
    if not d.is_dir():
        return []
    return sorted(f.stem for f in d.glob("*.json") if _ID_RE.match(f.stem))
