"""Core session state for ffx-cli.

Manages an in-memory project with undo/redo and file-backed persistence.
"""
from __future__ import annotations

import json
import os
import time
import uuid
from pathlib import Path
from typing import Any, Optional


class SessionError(Exception):
    """Raised when a session-level invariant is violated."""


class ProjectSession:
    """In-memory project backed by an optional JSON file on disk.

    A *project* here is a lightweight representation of a Tafcm `.md`
    document plus its related assets. The session tracks modifications so
    that auto-save knows when to persist.
    """

    def __init__(self, project_path: Optional[str] = None) -> None:
        self._project_path = project_path
        self._modified = False
        self._history: list[dict[str, Any]] = []
        self._redo_stack: list[dict[str, Any]] = []
        self._project: dict[str, Any] = {}

        if project_path and Path(project_path).is_file():
            self._project = self._load_json(project_path)
            self._modified = False

    # ── properties ────────────────────────────────────────────────────

    @property
    def has_project(self) -> bool:
        return bool(self._project)

    @property
    def project_path(self) -> Optional[str]:
        return self._project_path

    @property
    def is_modified(self) -> bool:
        return self._modified

    @property
    def project(self) -> dict[str, Any]:
        return self._project

    # ── snapshot / restore (undo-redo) ────────────────────────────────

    def snapshot(self) -> None:
        """Push current project state onto the history stack."""
        self._history.append(json.loads(json.dumps(self._project)))
        self._redo_stack.clear()
        if len(self._history) > 100:
            self._history.pop(0)

    def undo(self) -> bool:
        if not self._history:
            return False
        self._redo_stack.append(self._project)
        self._project = self._history.pop()
        self._modified = True
        return True

    def redo(self) -> bool:
        if not self._redo_stack:
            return False
        self._history.append(self._project)
        self._project = self._redo_stack.pop()
        self._modified = True
        return True

    # ── mutation helpers ──────────────────────────────────────────────

    def mark_dirty(self) -> None:
        self._modified = True

    def set_field(self, key: str, value: Any) -> None:
        self._project[key] = value
        self._modified = True

    def delete_field(self, key: str) -> bool:
        if key not in self._project:
            return False
        del self._project[key]
        self._modified = True
        return True

    # ── persistence ───────────────────────────────────────────────────

    def save_session(self, path: Optional[str] = None) -> str:
        target = path or self._project_path
        if not target:
            raise SessionError("No project path to save to")
        data = {
            **self._project,
            "_meta": {
                "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "modified": True,
            },
        }
        self._atomic_write(target, data)
        self._modified = False
        return target

    def _atomic_write(self, path: str, data: dict[str, Any]) -> None:
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        tmp = str(p) + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.flush()
            os.fsync(f.fileno()) if hasattr(os, "fsync") else None
        Path(tmp).replace(p)

    @staticmethod
    def _load_json(path: str) -> dict[str, Any]:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
