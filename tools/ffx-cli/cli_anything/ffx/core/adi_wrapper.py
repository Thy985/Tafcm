"""ADI (Agent Diagnostic Interface) wrapper — delegates to adi.dart.

The wrapper resolves the adi.dart entry point and runs it with the correct
working directory so that `.adi/` is always found regardless of where the
caller invokes `ffx` from.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any, Optional


def _find_adi_cwd(root: Optional[str] = None) -> tuple[list[str], str]:
    """Locate adi.dart and return (command, cwd).

    The .adi/ storage lives in tools/adi/.adi, so adi.dart must run with
    cwd = tools/adi/ directory. We resolve relative to the script's own
    location first (works when installed), then fall back to parent dirs.
    """
    dart_bin = shutil.which("dart")
    if not dart_bin:
        raise RuntimeError(
            "dart not found in PATH. Install Flutter/Dart SDK.\n"
            "  https://docs.flutter.dev/get-dart"
        )

    script_dir = Path(__file__).resolve().parents[3]  # tools/ffx-cli/
    candidates: list[Path] = []

    # 1. Explicit root provided
    if root:
        candidates.append(Path(root))
    # 2. Relative to script location (installed package)
    candidates.append(script_dir.parent.parent)  # math2/
    # 3. Current working directory
    candidates.append(Path.cwd())
    # 4. Parent of cwd (when running from tools/ffx-cli/)
    candidates.append(Path.cwd().parent)
    # 5. Parent of script dir
    candidates.append(script_dir.parent)

    for base in candidates:
        p = Path(base) / "tools" / "adi"
        if p.is_dir() and (p / "adi.dart").is_file():
            return [dart_bin, "run", str(p / "adi.dart")], str(p)

    raise RuntimeError(
        "tools/adi/adi.dart not found. Run ffx from the project root.\n"
        "Expected at: <project-root>/tools/adi/adi.dart"
    )


def _run_adi(args: list[str], cwd: Optional[str] = None) -> dict[str, Any]:
    """Run an adi sub-command and return structured output."""
    cmd, adi_cwd = _find_adi_cwd(cwd)
    result = subprocess.run(
        cmd + args + ["--json"],
        capture_output=True,
        text=True,
        cwd=adi_cwd,
    )
    if result.returncode != 0:
        return {"status": "error", "stderr": result.stderr.strip(), "exit_code": result.returncode}
    try:
        return json.loads(result.stdout.strip())
    except json.JSONDecodeError:
        return {"status": "error", "raw_output": result.stdout.strip()}


# ── public API ─────────────────────────────────────────────────────────

def doctor(cwd: Optional[str] = None) -> dict[str, Any]:
    return _run_adi(["doctor"], cwd=cwd)


def latest_error(cwd: Optional[str] = None) -> dict[str, Any]:
    return _run_adi(["latest-error"], cwd=cwd)


def trace_show(trace_id: str, cwd: Optional[str] = None) -> dict[str, Any]:
    return _run_adi(["trace", "show", trace_id], cwd=cwd)


def replay(session_id: str, cwd: Optional[str] = None) -> dict[str, Any]:
    return _run_adi(["replay", session_id], cwd=cwd)


def agent_context(cwd: Optional[str] = None) -> dict[str, Any]:
    return _run_adi(["agent-context"], cwd=cwd)


def failures_list(cwd: Optional[str] = None) -> dict[str, Any]:
    return _run_adi(["failures"], cwd=cwd)


def failure_show(failure_id: str, cwd: Optional[str] = None) -> dict[str, Any]:
    return _run_adi(["failure", "show", failure_id], cwd=cwd)


def validate_after_fix(session_id: str, cwd: Optional[str] = None) -> dict[str, Any]:
    return _run_adi(["validate", "--after-fix", session_id], cwd=cwd)


def aggregate_failures(cwd: Optional[str] = None) -> dict[str, Any]:
    return _run_adi(["failures", "aggregate"], cwd=cwd)


def import_zip(source: str, output_dir: Optional[str] = None, cwd: Optional[str] = None) -> dict[str, Any]:
    args = ["import", source]
    if output_dir:
        args += ["--out", output_dir]
    return _run_adi(args, cwd=cwd)


def list_traces(cwd: Optional[str] = None) -> dict[str, Any]:
    """List trace IDs in .adi/traces/ without reading each file."""
    adir = _find_adi_cwd(cwd)[1]
    traces_dir = Path(adir) / ".adi" / "traces"
    if not traces_dir.is_dir():
        return {"status": "empty", "traces": []}
    traces = []
    for f in sorted(traces_dir.glob("*.json")):
        tid = f.stem  # e.g. "trc_5b98ca4687546592"
        traces.append(tid)
    return {"status": "ok", "count": len(traces), "traces": traces}


def list_sessions(cwd: Optional[str] = None) -> dict[str, Any]:
    """List session IDs in .adi/sessions/."""
    adir = _find_adi_cwd(cwd)[1]
    sessions_dir = Path(adir) / ".adi" / "sessions"
    if not sessions_dir.is_dir():
        return {"status": "empty", "sessions": []}
    sessions = []
    for d in sorted(sessions_dir.iterdir()):
        if d.is_dir():
            sessions.append(d.name)
    return {"status": "ok", "count": len(sessions), "sessions": sessions}
