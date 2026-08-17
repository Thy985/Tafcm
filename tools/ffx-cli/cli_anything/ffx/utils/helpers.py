"""Utilities shared across ffx-cli commands."""
from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path
from typing import Any, Optional


def resolve_cli(name: str) -> list[str]:
    """Resolve installed CLI command; falls back to python -m for dev.

    Set env CLI_ANYTHING_FORCE_INSTALLED=1 to require the installed command.
    """
    force = os.environ.get("CLI_ANYTHING_FORCE_INSTALLED", "").strip() == "1"
    path = shutil.which(name)
    if path:
        return [path]
    if force:
        raise RuntimeError(f"{name} not found in PATH. Install with: pip install -e .")
    module = name.replace("cli-anything-", "cli_anything.") + "." + name.split("-")[-1] + "_cli"
    return [sys.executable, "-m", module]


def pretty_print(data: Any, use_json: bool) -> None:
    """Print data either as JSON or human-readable text."""
    if use_json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        _print_human(data)


def _print_human(data: Any) -> None:
    """Render a dict as key-value lines (simple but effective)."""
    if not isinstance(data, dict):
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return
    for k, v in data.items():
        if isinstance(v, dict):
            print(f"{k}:")
            for kk, vv in v.items():
                print(f"  {kk}: {vv}")
        elif isinstance(v, list):
            print(f"{k}: ({len(v)} items)")
            for item in v:
                print(f"  - {item}")
        else:
            print(f"{k}: {v}")


def find_flutter_root() -> Optional[str]:
    """Find the project root by looking for flutter_app/ or pubspec.yaml upward from cwd."""
    cwd = Path.cwd()
    # Walk up at most 5 levels (to avoid walking the whole filesystem)
    for i, parent in enumerate([cwd, *cwd.parents[:5]]):
        # Priority 1: flutter_app/ exists (strongest signal)
        if (parent / "flutter_app").is_dir():
            return str(parent)
        # Priority 2: pubspec.yaml in flutter_app/
        if (parent / "flutter_app" / "pubspec.yaml").is_file():
            return str(parent)
    return None
