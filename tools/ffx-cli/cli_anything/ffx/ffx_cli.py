"""Tafcm CLI — diagnostic and document analysis tool for Tafcm projects."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import click

from cli_anything.ffx.core import project as proj_mod
from cli_anything.ffx.core import session as sess_mod
from cli_anything.ffx.core import adi_wrapper as adi_mod
from cli_anything.ffx.harness import orchestrator
from cli_anything.ffx.utils.helpers import find_flutter_root, pretty_print


# ── helpers ───────────────────────────────────────────────────────────

def _effective_json(ctx: click.Context) -> bool:
    """Return True if --json was set on this command or any parent."""
    c = ctx
    while c:
        if c.obj and c.obj.get("use_json"):
            return True
        c = c.parent
    return False


# ── main group ────────────────────────────────────────────────────────

@click.group(invoke_without_command=True)
@click.option("--json", "use_json", is_flag=True, help="Output as JSON")
@click.option("--project", "project_path", type=click.Path(dir_okay=False, allow_dash=False), default=None,
              help="Path to project JSON file")
@click.option("--dry-run", "dry_run", is_flag=True, default=False,
              help="Run command without saving changes to disk")
@click.option("--root", "project_root", type=click.Path(exists=False), default=None,
              help="Project root (defaults to cwd or nearest pubspec.yaml)")
@click.pass_context
def cli(ctx, use_json, project_path, dry_run, project_root):
    """ffx — Tafcm diagnostic and document analysis CLI."""
    ctx.ensure_object(dict)
    ctx.obj["use_json"] = use_json
    ctx.obj["project_path"] = project_path
    ctx.obj["dry_run"] = dry_run
    ctx.obj["project_root"] = project_root

    if ctx.invoked_subcommand is None:
        _print_help(ctx, use_json)


@cli.result_callback()
def auto_save_on_exit(result, use_json, project_path, dry_run, **kwargs):
    """Auto-save project after one-shot commands if state was modified."""
    if dry_run:
        return


# ── project group ─────────────────────────────────────────────────────

@cli.group()
def project():
    """Project management: create, open, info, inject content."""


@project.command()
@click.option("-o", "--output", "out_path", required=True, help="Output path (.json)")
@click.option("-n", "--name", default="Untitled", help="Project name")
@click.option("-t", "--title", default="", help="Document title")
@click.pass_context
def create(ctx, out_path, name, title):
    """Create a new blank project."""
    try:
        p = proj_mod.create_project(out_path, name=name, title=title)
        pretty_print(p, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@project.command("info")
@click.option("-p", "--project", "project_path", required=True, help="Path to project JSON")
@click.pass_context
def info(ctx, project_path):
    """Show project metadata and content analysis."""
    try:
        proj = proj_mod.open_project(project_path)
        inf = proj_mod.info_project(proj)
        pretty_print(inf, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@project.command("set-field")
@click.option("-p", "--project", "project_path", required=True, help="Path to project JSON")
@click.argument("key")
@click.argument("value")
@click.pass_context
def set_field(ctx, project_path, key, value):
    """Set a project field (mutates the JSON file)."""
    try:
        proj = proj_mod.open_project(project_path)
        proj[key] = value
        proj["updated_at"] = proj_mod._now_iso()
        proj_mod._atomic_write(project_path, proj)
        pretty_print({"status": "ok", "key": key, "value": value}, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@project.command()
@click.option("-p", "--project", "project_path", required=True, help="Path to project JSON")
@click.option("--dry-run", is_flag=True, help="Show what would be appended without saving")
@click.argument("inject_type", required=False, default=None,
                type=click.Choice(["formula", "heading", "paragraph", "code", "mermaid", "table", "image"]))
@click.option("--latex", default=None, help="LaTeX formula content")
@click.option("--display", is_flag=True, default=True, help="Display mode ($$) vs inline ($)")
@click.option("--text", default=None, help="Heading or paragraph text")
@click.option("--level", type=int, default=1, help="Heading level (1-6)")
@click.option("--code", default=None, help="Code block content")
@click.option("--lang", default="", help="Code block language")
@click.option("--diagram", default=None, help="Mermaid diagram source")
@click.option("--headers", default=None, help="Table headers comma-separated")
@click.option("--rows", default=None, help="Table rows semicolon-separated, comma cells")
@click.option("--alt", default=None, help="Image alt text")
@click.option("--url", default=None, help="Image URL/path")
@click.pass_context
def inject(ctx, project_path, dry_run, inject_type,
           latex, display, text, level, code, lang, diagram, headers, rows, alt, url):
    """Inject content into a project.

    Examples:
      ffx project inject formula -p proj.json --latex 'E=mc^2'
      ffx project inject heading -p proj.json --text 'Intro' --level 1
      ffx project inject paragraph -p proj.json --text 'Hello'
      ffx project inject code -p proj.json --lang python --code 'print(1)'
      ffx project inject mermaid -p proj.json --diagram 'flowchart LR A --> B'
      ffx project inject table -p proj.json --headers "Name,Age" --rows "Alice,30"
      ffx project inject image -p proj.json --alt logo --url /img/logo.png
    """
    try:
        proj = proj_mod.open_project(project_path)
        content = proj.get("content", "")

        if inject_type == "formula" and latex:
            new_content = proj_mod.inject_formula(content, latex, display=display)
        elif inject_type == "heading" and text:
            new_content = proj_mod.inject_heading(content, text, level)
        elif inject_type == "paragraph" and text:
            new_content = proj_mod.inject_paragraph(content, text)
        elif inject_type == "code" and code:
            new_content = proj_mod.inject_code_block(content, code, lang)
        elif inject_type == "mermaid" and diagram:
            new_content = proj_mod.inject_mermaid(content, diagram)
        elif inject_type == "table":
            h = [x.strip() for x in (headers or "").split(",")]
            raw = rows or ""
            r = [[c.strip() for c in cell.split(",")] for cell in raw.split(";")] if raw else []
            new_content = proj_mod.inject_table(content, h, r)
        elif inject_type == "image" and alt:
            new_content = proj_mod.inject_image(content, alt, url or "")
        else:
            click.echo(f"Error: invalid inject type '{inject_type}' or missing content", err=True)
            sys.exit(1)

        if dry_run:
            result = {"status": "dry_run", "injected_type": inject_type, "new_content": new_content}
        else:
            proj["content"] = new_content
            proj["updated_at"] = proj_mod._now_iso()
            proj_mod.snapshot_project(proj)
            proj_mod._atomic_write(project_path, proj)
            result = {"status": "ok", "injected_type": inject_type, "history_size": len(proj.get("_session", {}).get("history", []))}

        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@project.command("save")
@click.option("-p", "--project", "project_path", required=True, help="Path to project JSON")
@click.option("-o", "--output", "out_path", default=None, help="Output path (defaults to project_path)")
@click.pass_context
def save(ctx, project_path, out_path):
    """Save (persist) project state to disk."""
    try:
        proj = proj_mod.open_project(project_path)
        target = out_path or project_path
        saved = proj_mod.save_project(target, proj)
        pretty_print({"status": "saved", "path": saved}, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@project.command("undo")
@click.option("-p", "--project", "project_path", required=True, help="Path to project JSON")
@click.pass_context
def undo(ctx, project_path):
    """Undo the last content change (requires prior snapshot)."""
    try:
        proj = proj_mod.open_project(project_path)
        result = proj_mod.undo_project(proj)
        if result is None:
            pretty_print({"status": "no_history", "message": "Nothing to undo"}, _effective_json(ctx))
        else:
            proj_mod._atomic_write(project_path, proj)
            info = proj_mod.info_project(proj)
            pretty_print({"status": "undone", **info}, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@project.command("redo")
@click.option("-p", "--project", "project_path", required=True, help="Path to project JSON")
@click.pass_context
def redo(ctx, project_path):
    """Redo the last undone change."""
    try:
        proj = proj_mod.open_project(project_path)
        result = proj_mod.redo_project(proj)
        if result is None:
            pretty_print({"status": "nothing_to_redo", "message": "Redo stack is empty"}, _effective_json(ctx))
        else:
            proj_mod._atomic_write(project_path, proj)
            info = proj_mod.info_project(proj)
            pretty_print({"status": "redone", **info}, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@project.command("snapshot")
@click.option("-p", "--project", "project_path", required=True, help="Path to project JSON")
@click.pass_context
def snapshot(ctx, project_path):
    """Push current state onto history stack (prepare for undo)."""
    try:
        proj = proj_mod.open_project(project_path)
        proj_mod.snapshot_project(proj)
        proj_mod._atomic_write(project_path, proj)
        status = proj_mod.session_status(proj)
        pretty_print({"status": "snapshot_saved", **status}, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@project.command("export")
@click.option("-p", "--project", "project_path", required=True, help="Path to project JSON")
@click.argument("output_md", type=click.Path(exists=False))
@click.pass_context
def export(ctx, project_path, output_md):
    """Export project content to a .md file."""
    try:
        proj = proj_mod.open_project(project_path)
        out = proj_mod.export_markdown(proj, output_md)
        pretty_print({"status": "exported", "output": out}, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@project.command("diff")
@click.argument("path_a", type=click.Path(exists=True))
@click.argument("path_b", type=click.Path(exists=True))
@click.pass_context
def diff(ctx, path_a, path_b):
    """Compare two markdown files and show stat differences."""
    try:
        result = proj_mod.diff_markdown(path_a, path_b)
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@project.command("status")
@click.option("-p", "--project", "project_path", required=True, help="Path to project JSON")
@click.pass_context
def status(ctx, project_path):
    """Show project metadata and session status."""
    try:
        proj = proj_mod.open_project(project_path)
        info = proj_mod.info_project(proj)
        sess = proj_mod.session_status(proj)
        pretty_print({"info": info, "session": sess}, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


# ── analyze group ─────────────────────────────────────────────────────

@cli.group()
def analyze():
    """Analyze markdown content, ADRs, and project structure."""


@analyze.command()
@click.argument("path", type=click.Path(exists=True))
@click.pass_context
def file(ctx, path):
    """Analyze a single markdown or text file."""
    try:
        with open(path, encoding="utf-8") as f:
            content = f.read()
        result = proj_mod.analyze_markdown(content)
        result["path"] = path
        result["file_size"] = os.path.getsize(path)
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@analyze.command()
@click.pass_context
def adr(ctx):
    """List and analyze all ADRs in docs/ADR/."""
    try:
        root = find_flutter_root() or str(Path.cwd())
        adr_dir = Path(root) / "docs" / "ADR"
        if not adr_dir.is_dir():
            click.echo(json.dumps({"status": "not_found", "path": str(adr_dir)}))
            return

        adrs = []
        for f in sorted(adr_dir.glob("*.md")):
            content = f.read_text(encoding="utf-8")
            analysis = proj_mod.analyze_markdown(content)
            last = f.stem.split("-")[-1].lower()
            status = "unknown"
            if "accepted" in last:
                status = "accepted"
            elif "draft" in last:
                status = "draft"
            elif "superseded" in last:
                status = "superseded"
            adrs.append({"id": f.stem, "status": status, **analysis})

        pretty_print({"count": len(adrs), "adrs": adrs}, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@analyze.command()
@click.pass_context
def structure(ctx):
    """Show project directory structure summary."""
    try:
        root = find_flutter_root() or str(Path.cwd())
        root_p = Path(root)
        summary = {
            "root": root,
            "lib_count": _count_files(root_p / "flutter_app" / "lib", "*.dart"),
            "test_count": _count_files(root_p / "flutter_app" / "test", "*.dart"),
            "integration_test_count": _count_files(root_p / "flutter_app" / "integration_test", "*.dart"),
            "docs_count": _count_files(root_p / "docs", "*"),
            "adr_count": _count_files(root_p / "docs" / "ADR", "*.md"),
            "tools": {
                "adi": (root_p / "tools" / "adi" / "adi.dart").is_file(),
                "ffx_analyze": (root_p / "tools" / "ffx-analyze" / "analyze.py").is_file(),
            },
        }
        pretty_print(summary, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


def _count_files(dir_path: Path, pattern: str) -> int:
    if not dir_path.is_dir():
        return 0
    return len(list(dir_path.glob(f"**/{pattern}")))


# ── export audit（Agent-native DOCX QA）───────────────────────────────

@analyze.command("contract-sync")
@click.pass_context
def contract_sync(ctx):
    """Contract Sync 最小版（ROADMAP 3.10.2）：Matrix ↔ contracts/*.json 一致性校验。

    Feature Capability Matrix（S0-S5）↔ 契约 s0_unsupported 机器强制：
    - 规则 1：Matrix S0 能力必须被 contract 声明（漏声明 = 漂移 ERROR）
    - 规则 2：Matrix S≥4 能力不得被 contract 标为不支持（误声明 = ERROR）
    - 规则 3：contract s0 需有 Matrix 依据（额外能力 → WARN）
    exit：0=一致（可含 WARN）/ 1=漂移 ERROR
    """
    try:
        from cli_anything.ffx.core.contract_sync import (
            check_contract_sync,
            render_sync_report,
        )

        result = check_contract_sync()
        if _effective_json(ctx):
            pretty_print(result, True)
        else:
            click.echo(render_sync_report(result))
        sys.exit(0 if result.get("status") != "error" else 1)
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@analyze.command("audit")
@click.argument("path", type=click.Path())
@click.pass_context
def audit(ctx, path):
    """Audit an exported artifact (DOCX OOXML integrity + semantic model).

    Agent-native Export QA（docs/DOCX-QA-PIPELINE.md Level A）：
    不依赖 Microsoft Word；解包 .docx 校验 OOXML 结构 + 提取语义模型，
    输出 JSON 质量报告（artifact_integrity / semantic_fidelity 等）。
    """
    try:
        from cli_anything.ffx.core import docx_qa as docx_mod

        suffix = Path(path).suffix.lower()
        if suffix == ".docx":
            result = docx_mod.audit_docx(path)
        else:
            result = {
                "path": path,
                "error": f"unsupported format: {suffix or '(none)'} (expect .docx)",
            }
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


# ── adi group ─────────────────────────────────────────────────────────

@cli.group()
def adi():
    """ADI (Agent Diagnostic Interface) commands — delegates to adi.dart."""


@adi.command()
@click.option("--root", "project_root", default=None, help="Project root for locating adi.dart")
@click.pass_context
def doctor(ctx, project_root):
    """ADI self-check."""
    try:
        root = project_root or find_flutter_root()
        result = adi_mod.doctor(cwd=root)
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@adi.command()
@click.option("--root", "project_root", default=None, help="Project root")
@click.pass_context
def latest_error(ctx, project_root):
    """Get the latest error observation."""
    try:
        root = project_root or find_flutter_root()
        result = adi_mod.latest_error(cwd=root)
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@adi.command()
@click.argument("trace_id")
@click.option("--root", "project_root", default=None, help="Project root")
@click.pass_context
def trace_show(ctx, trace_id, project_root):
    """Show a trace chain by ID."""
    try:
        root = project_root or find_flutter_root()
        result = adi_mod.trace_show(trace_id, cwd=root)
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@adi.command()
@click.argument("session_id")
@click.option("--root", "project_root", default=None, help="Project root")
@click.pass_context
def replay(ctx, session_id, project_root):
    """Replay a session."""
    try:
        root = project_root or find_flutter_root()
        result = adi_mod.replay(session_id, cwd=root)
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@adi.command()
@click.option("--root", "project_root", default=None, help="Project root")
@click.pass_context
def agent_context(ctx, project_root):
    """Generate Agent context Markdown."""
    try:
        root = project_root or find_flutter_root()
        result = adi_mod.agent_context(cwd=root)
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@adi.command()
@click.option("--root", "project_root", default=None, help="Project root")
@click.pass_context
def failures(ctx, project_root):
    """List recent failures."""
    try:
        root = project_root or find_flutter_root()
        result = adi_mod.failures_list(cwd=root)
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@adi.command()
@click.argument("failure_id")
@click.option("--root", "project_root", default=None, help="Project root")
@click.pass_context
def failure_show(ctx, failure_id, project_root):
    """Show failure details."""
    try:
        root = project_root or find_flutter_root()
        result = adi_mod.failure_show(failure_id, cwd=root)
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@adi.command()
@click.argument("session_id")
@click.option("--after-fix", "after_fix", is_flag=True, default=False,
              help="Validate after fix (replay + invariant); adi.dart requires "
                   "this flag, ffx always validates after-fix")
@click.option("--root", "project_root", default=None, help="Project root")
@click.pass_context
def validate(ctx, session_id, after_fix, project_root):
    """Validate after fix (replay + invariant)."""
    try:
        root = project_root or find_flutter_root()
        result = adi_mod.validate_after_fix(session_id, cwd=root)
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@adi.command()
@click.option("--root", "project_root", default=None, help="Project root")
@click.pass_context
def aggregate(ctx, project_root):
    """Aggregate observations into failures."""
    try:
        root = project_root or find_flutter_root()
        result = adi_mod.aggregate_failures(cwd=root)
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@adi.command()
@click.argument("source")
@click.option("--out", "output_dir", default=None, help="Output directory (.adi/)")
@click.option("--root", "project_root", default=None, help="Project root")
@click.pass_context
def import_cmd(ctx, source, output_dir, project_root):
    """Import an ExportPipeline package (.zip/dir) into .adi/."""
    try:
        root = project_root or find_flutter_root()
        result = adi_mod.import_zip(source, output_dir=output_dir, cwd=root)
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


# ── diag group ────────────────────────────────────────────────────────

@cli.group()
def diag():
    """Project diagnostics: health, version, environment."""


@diag.command()
@click.pass_context
def health(ctx):
    """Overall project health summary."""
    try:
        root = find_flutter_root() or str(Path.cwd())
        root_p = Path(root)
        dart = _which("dart")
        flutter = _which("flutter")
        python = _which("python3") or _which("python")
        has_adi = (root_p / "tools" / "adi" / "adi.dart").is_file()
        has_ffx_analyze = (root_p / "tools" / "ffx-analyze" / "analyze.py").is_file()

        result = {
            "project_root": root,
            "dart_sdk": {"available": dart is not None, "path": dart},
            "flutter_sdk": {"available": flutter is not None, "path": flutter},
            "python": {"available": python is not None, "path": python},
            "adi_cli": {"available": has_adi, "path": str(root_p / "tools" / "adi" / "adi.dart")},
            "ffx_analyze": {"available": has_ffx_analyze, "path": str(root_p / "tools" / "ffx-analyze" / "analyze.py")},
            "pubspec": (root_p / "flutter_app" / "pubspec.yaml").is_file(),
            "cli_available": has_adi,
        }
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@diag.command()
@click.pass_context
def version(ctx):
    """Show ffx-cli and project versions."""
    try:
        import importlib.metadata as meta
        ffx_version = meta.version("cli-anything-ffx") if _pkg_available() else "dev"
        result = {
            "ffx_cli_version": ffx_version,
            "python_version": f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
            "project_root": str(Path.cwd()),
        }
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@diag.command()
@click.pass_context
def traces(ctx):
    """List trace IDs in .adi/traces/."""
    try:
        root = find_flutter_root() or str(Path.cwd())
        result = adi_mod.list_traces(cwd=root)
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@diag.command()
@click.pass_context
def sessions(ctx):
    """List session IDs in .adi/sessions/."""
    try:
        root = find_flutter_root() or str(Path.cwd())
        result = adi_mod.list_sessions(cwd=root)
        pretty_print(result, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


# ── capability group (Verification Orchestrator, ADR-0030) ────────────

@cli.group()
def capability():
    """Verification Orchestrator: verify / diagnose / repair-verify capabilities."""


@capability.command("verify")
@click.argument("name")
@click.pass_context
def capability_verify(ctx, name):
    """Run the capability contract verification chain (read-only)."""
    try:
        report, code = orchestrator.verify(name)
        pretty_print(report, _effective_json(ctx))
        sys.exit(code)
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@capability.command("diagnose")
@click.argument("failure_id")
@click.pass_context
def capability_diagnose(ctx, failure_id):
    """Aggregate failure context for a diagnostic_id into a bundle."""
    try:
        bundle = orchestrator.diagnose(failure_id)
        pretty_print(bundle, _effective_json(ctx))
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@capability.command("repair-verify")
@click.argument("failure_id")
@click.pass_context
def capability_repair_verify(ctx, failure_id):
    """Re-verify after agent fix: before/after/regression evidence (read-only)."""
    try:
        result, code = orchestrator.repair_verify(failure_id)
        pretty_print(result, _effective_json(ctx))
        sys.exit(code)
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


def _pkg_available() -> bool:
    try:
        import importlib.metadata
        importlib.metadata.version("cli-anything-ffx")
        return True
    except Exception:
        return False


def _which(name: str):
    import shutil
    return shutil.which(name)


# ── help ──────────────────────────────────────────────────────────────

def _print_help(ctx, use_json):
    if use_json:
        cmds = {
            "project": "Project management (create, info, inject, save, undo, redo, snapshot, export, diff, status)",
            "analyze": "Analyze markdown files and ADRs",
            "adi": "ADI diagnostic commands (doctor, trace, replay, ...)",
            "diag": "Project diagnostics (health, version, traces, sessions)",
            "capability": "Verification Orchestrator (verify / diagnose / repair-verify)",
        }
        print(json.dumps({"mode": "repl", "commands": cmds, "hint": "use --help for details"}))
    else:
        click.echo("Tafcm CLI — run a subcommand or use --help")
        click.echo("Available groups: project, analyze, adi, diag, capability")
        click.echo("Try: ffx --help")


# ── entry point ───────────────────────────────────────────────────────

if __name__ == "__main__":
    cli()
