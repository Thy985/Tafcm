"""ADI (Agent Diagnostic Interface) wrapper — delegates to adi.dart.

The wrapper resolves the adi.dart entry point and runs it with the project
root as working directory, so `ffx adi *` reads the same `<root>/.adi` store
as the App, `dart run tools/adi/adi.dart` and the MCP server (issue #325).
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

    The command runs adi.dart; cwd is the project root, because adi.dart
    resolves its storage as Directory.current/.adi (issue #325). This matches
    the App, `dart run tools/adi/adi.dart` and the MCP server, which all read
    <root>/.adi. The script itself is still located via tools/adi/adi.dart,
    resolved relative to the wrapper's own location first (works when
    installed), then falling back to parent dirs.
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
            # Issue #325: run from the project root (NOT tools/adi) so that
            # Directory.current/.adi points at <root>/.adi like every other
            # ADI consumer. resolve() keeps the subprocess cwd deterministic
            # even when the caller passes a relative --root.
            return [dart_bin, "run", str(p / "adi.dart")], str(Path(base).resolve())

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

def _storage_candidates(root: str) -> dict[str, Any]:
    """Report the two historical .adi/ locations under the project root.

    Issue #325: older ffx versions pinned adi.dart's cwd to tools/adi/, so
    diagnostic data could diverge between <root>/.adi (App / dart run / MCP)
    and <root>/tools/adi/.adi (legacy ffx). Surfacing both locations makes
    such divergence visible; ffx never migrates data automatically.
    """
    root_p = Path(root)
    primary = root_p / ".adi"
    legacy = root_p / "tools" / "adi" / ".adi"
    primary_exists = primary.is_dir()
    legacy_exists = legacy.is_dir()
    hint: Optional[str] = None
    if not primary_exists and legacy_exists:
        hint = (
            f"No .adi/ found at project root ({primary}), but a legacy store "
            f"exists at {legacy}. Older ffx versions wrote diagnostics there; "
            "data is NOT migrated automatically — copy it to <root>/.adi "
            "manually if still needed."
        )
    return {
        "candidates": [
            {"label": "project_root", "path": str(primary), "exists": primary_exists},
            {"label": "tools/adi (legacy)", "path": str(legacy), "exists": legacy_exists},
        ],
        "migration_hint": hint,
    }


def doctor(cwd: Optional[str] = None) -> dict[str, Any]:
    """Run adi.dart doctor and augment it with .adi/ storage candidates.

    The augmentation lists both <root>/.adi and the legacy
    <root>/tools/adi/.adi (with exists markers) so divergent data stores are
    discoverable from `ffx adi doctor` output (issue #325).
    """
    result = _run_adi(["doctor"], cwd=cwd)
    _, root = _find_adi_cwd(cwd)  # resolved project root == subprocess cwd
    result["storage_candidates"] = _storage_candidates(root)
    return result


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
