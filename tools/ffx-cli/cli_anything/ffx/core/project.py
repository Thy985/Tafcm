"""Core project operations: create, open, info, analyze markdown."""
from __future__ import annotations

import json
import os
import re
import uuid
from pathlib import Path
from typing import Any, Optional


def create_project(out_path: str, name: str = "Untitled", title: str = "") -> dict[str, Any]:
    """Create a new blank project file."""
    project: dict[str, Any] = {
        "id": _generate_id(),
        "name": name,
        "title": title,
        "content": "",
        "metadata": {},
        "created_at": _now_iso(),
        "updated_at": _now_iso(),
    }
    _atomic_write(out_path, project)
    return project


def open_project(path: str) -> dict[str, Any]:
    """Load a project from disk."""
    p = Path(path)
    if not p.is_file():
        raise FileNotFoundError(f"Project not found: {path}")
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def info_project(project: dict[str, Any]) -> dict[str, Any]:
    """Return a read-only summary of a project."""
    content = project.get("content", "")
    stats = _analyze_content(content)
    meta = project.get("metadata", {})
    return {
        "id": project.get("id"),
        "name": project.get("name", "Untitled"),
        "title": project.get("title", ""),
        "word_count": stats["word_count"],
        "char_count": stats["char_count"],
        "heading_count": stats["heading_count"],
        "formula_count": stats["formula_count"],
        "mermaid_count": stats["mermaid_count"],
        "code_block_count": stats["code_block_count"],
        "list_item_count": stats["list_item_count"],
        "table_count": stats["table_count"],
        "image_count": stats["image_count"],
        "content_length": len(content),
        "updated_at": project.get("updated_at"),
        "metadata": meta,
    }


def analyze_markdown(content: str) -> dict[str, Any]:
    """Static analysis of raw markdown content (no project required)."""
    return _analyze_content(content)


def inject_formula(content: str, latex: str, display: bool = True) -> str:
    """Append a display or inline formula block to content."""
    marker = "\n$$\n" if display else " $"
    terminator = "\n$$\n" if display else " $\n"
    return content.rstrip() + marker + latex + terminator


def inject_heading(content: str, text: str, level: int = 1) -> str:
    """Append a heading to content."""
    prefix = "#" * min(max(level, 1), 6) + " "
    return content.rstrip() + "\n\n" + prefix + text + "\n"


def inject_paragraph(content: str, text: str) -> str:
    """Append a paragraph to content."""
    return content.rstrip() + "\n\n" + text + "\n"


def inject_code_block(content: str, code: str, language: str = "") -> str:
    """Append a fenced code block."""
    lang = language or ""
    return content.rstrip() + f"\n\n```{lang}\n{code}\n```\n"


def inject_mermaid(content: str, diagram: str) -> str:
    """Append a Mermaid block."""
    return content.rstrip() + f"\n\n```mermaid\n{diagram}\n```\n"


def inject_table(content: str, headers: list[str], rows: list[list[str]]) -> str:
    """Append a markdown table."""
    max_header = max((len(h) for h in headers), default=0)
    max_cell = max((len(c) for row in rows for c in row), default=0)
    col_width = max(max_header, max_cell, 1)
    sep = "| " + " | ".join("-" * col_width for _ in headers) + " |"
    pad = lambda s: s.ljust(col_width)
    lines = ["| " + " | ".join(pad(h) for h in headers) + " |", sep]
    for row in rows:
        lines.append("| " + " | ".join(pad(c) for c in row) + " |")
    return content.rstrip() + "\n" + "\n".join(lines) + "\n"


def inject_image(content: str, alt: str, url: str) -> str:
    """Append an image reference."""
    return content.rstrip() + f"\n\n![{alt}]({url})\n"


# ── internals ───────────────────────────────────────────────────────

_FORMULA_RE = re.compile(r"\$\$[^$]*\$\$|\$[^$\n]+\$", re.DOTALL)
_MERMAID_RE = re.compile(r"```mermaid\s*\n.*?\n```", re.DOTALL)
_CODE_RE = re.compile(r"```[^`]*\n.*?\n```", re.DOTALL)
_HEAD_RE = re.compile(r"^#{1,6}\s+.+", re.MULTILINE)
_LIST_RE = re.compile(r"^[\s]*[-*+]\s", re.MULTILINE)
_TASK_RE = re.compile(r"^[\s]*[-*+]\s+\[[ xX]\]\s", re.MULTILINE)
_TABLE_RE = re.compile(r"\|[^\n]+\|\n\|[-:| ]+\|\n\|[^\n]+\|", re.MULTILINE)
_IMG_RE = re.compile(r"!\[[^\]]*\]\([^)]+\)")


def _analyze_content(content: str) -> dict[str, Any]:
    headings = _HEAD_RE.findall(content)
    formula_blocks = _FORMULA_RE.findall(content)
    mermaid_blocks = _MERMAID_RE.findall(content)
    code_blocks = _CODE_RE.findall(content)
    list_items = _LIST_RE.findall(content)
    task_items = _TASK_RE.findall(content)
    tables = _TABLE_RE.findall(content)
    images = _IMG_RE.findall(content)
    words = content.split()
    return {
        "word_count": len(words),
        "char_count": len(content),
        "heading_count": len(headings),
        "formula_count": len(formula_blocks),
        "mermaid_count": len(mermaid_blocks),
        "code_block_count": len(code_blocks),
        "list_item_count": len(list_items),
        "task_item_count": len(task_items),
        "table_count": len(tables),
        "image_count": len(images),
    }


def _generate_id() -> str:
    return uuid.uuid4().hex[:12]


def _now_iso() -> str:
    import datetime
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _atomic_write(path: str, data: dict[str, Any]) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = str(p) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.flush()
        if hasattr(os, "fsync"):
            os.fsync(f.fileno())
    Path(tmp).replace(p)
