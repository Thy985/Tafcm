"""E2E tests for ffx-cli — real files, subprocess invocation."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[4]  # math2/


def _resolve_cli(name):
    """Resolve installed CLI command; falls back to python -m for dev."""
    force = os.environ.get("CLI_ANYTHING_FORCE_INSTALLED", "").strip() == "1"
    path = shutil.which(name)
    if path:
        return [path]
    if force:
        raise RuntimeError(f"{name} not found in PATH. Install with: pip install -e .")
    return [sys.executable, "-m", "cli_anything.ffx.ffx_cli"]


class TestProjectCreateRoundtrip:
    def test_create_and_info(self, tmp_path):
        cli = _resolve_cli("ffx")
        out = str(tmp_path / "proj.json")
        r = subprocess.run(cli + ["--json", "project", "create", "-o", out, "-n", "MyDoc", "-t", "Title"],
                           capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        data = json.loads(r.stdout.strip())
        assert data["name"] == "MyDoc"
        assert data["title"] == "Title"

        r2 = subprocess.run(cli + ["--json", "project", "info", "-p", out],
                            capture_output=True, text=True)
        assert r2.returncode == 0, r2.stderr
        info = json.loads(r2.stdout.strip())
        assert info["name"] == "MyDoc"
        assert info["word_count"] == 0


class TestAnalyzeFile:
    def test_readme_analysis(self):
        cli = _resolve_cli("ffx")
        readme = PROJECT_ROOT / "README.md"
        if not readme.exists():
            pytest.skip("README.md not found")
        r = subprocess.run(cli + ["--json", "analyze", "file", str(readme)],
                           capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        data = json.loads(r.stdout.strip())
        assert data["word_count"] > 0
        assert data["file_size"] > 0


class TestAnalyzeADR:
    def test_adr_listing(self):
        cli = _resolve_cli("ffx")
        r = subprocess.run(cli + ["--json", "analyze", "adr"],
                           capture_output=True, text=True, cwd=str(PROJECT_ROOT))
        assert r.returncode == 0, r.stderr
        data = json.loads(r.stdout.strip())
        assert data.get("count", 0) > 0


class TestDiagHealth:
    def test_health_json(self):
        cli = _resolve_cli("ffx")
        r = subprocess.run(cli + ["--json", "diag", "health"],
                           capture_output=True, text=True, cwd=str(PROJECT_ROOT))
        assert r.returncode == 0, r.stderr
        data = json.loads(r.stdout.strip())
        assert "dart_sdk" in data
        assert "flutter_sdk" in data
        assert "adi_cli" in data


class TestFFXHelp:
    def test_main_help(self):
        cli = _resolve_cli("ffx")
        r = subprocess.run(cli + ["--help"], capture_output=True, text=True)
        assert r.returncode == 0
        assert "project" in r.stdout
        assert "analyze" in r.stdout
        assert "adi" in r.stdout
        assert "diag" in r.stdout

    def test_project_help(self):
        cli = _resolve_cli("ffx")
        r = subprocess.run(cli + ["project", "--help"], capture_output=True, text=True)
        assert r.returncode == 0

    def test_analyze_help(self):
        cli = _resolve_cli("ffx")
        r = subprocess.run(cli + ["analyze", "--help"], capture_output=True, text=True)
        assert r.returncode == 0

    def test_adi_help(self):
        cli = _resolve_cli("ffx")
        r = subprocess.run(cli + ["adi", "--help"], capture_output=True, text=True)
        assert r.returncode == 0


class TestFFXJSONMode:
    def test_json_output_parses(self, tmp_path):
        cli = _resolve_cli("ffx")
        out = str(tmp_path / "j.json")
        r = subprocess.run(cli + ["--json", "project", "create", "-o", out],
                           capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        data = json.loads(r.stdout.strip())
        assert "id" in data


class TestInjectWorkflow:
    def test_formula_inject(self, tmp_path):
        cli = _resolve_cli("ffx")
        out = str(tmp_path / "wf.json")
        subprocess.run(cli + ["project", "create", "-o", out, "-n", "wf"], check=True)
        r = subprocess.run(
            cli + ["--json", "project", "inject", "formula", "-p", out, "--latex", "E=mc^2"],
            capture_output=True, text=True,
        )
        assert r.returncode == 0, r.stderr
        result = json.loads(r.stdout.strip())
        assert result["status"] == "ok"

        proj = json.loads(Path(out).read_text())
        assert "E=mc^2" in proj["content"]

    def test_heading_inject(self, tmp_path):
        cli = _resolve_cli("ffx")
        out = str(tmp_path / "hf.json")
        subprocess.run(cli + ["project", "create", "-o", out], check=True)
        r = subprocess.run(
            cli + ["--json", "project", "inject", "heading", "-p", out, "--text", "Hello", "--level", "1"],
            capture_output=True, text=True,
        )
        assert r.returncode == 0, r.stderr
        proj = json.loads(Path(out).read_text())
        assert "# Hello" in proj["content"]


class TestDryRun:
    def test_dry_run_no_save(self, tmp_path):
        cli = _resolve_cli("ffx")
        out = str(tmp_path / "dry.json")
        subprocess.run(cli + ["project", "create", "-o", out], check=True)
        r = subprocess.run(
            cli + ["--json", "project", "inject", "formula", "-p", out, "--latex", "TEST", "--dry-run"],
            capture_output=True, text=True,
        )
        assert r.returncode == 0, r.stderr
        result = json.loads(r.stdout.strip())
        assert result["status"] == "dry_run"
        proj = json.loads(Path(out).read_text())
        assert "TEST" not in proj["content"]


class TestADIDoctor:
    """ADI doctor — may fail if dart is not available, that's expected."""
    def test_adi_doctor(self):
        cli = _resolve_cli("ffx")
        r = subprocess.run(cli + ["--json", "adi", "doctor"],
                           capture_output=True, text=True, cwd=str(PROJECT_ROOT))
        try:
            data = json.loads(r.stdout.strip())
            assert "status" in data
        except json.JSONDecodeError:
            assert r.returncode != 0 or "not found" in r.stderr.lower()


class TestSubprocessFullWorkflow:
    """Full end-to-end workflow via subprocess."""
    def test_create_analyze_verify(self, tmp_path):
        cli = _resolve_cli("ffx")
        out = str(tmp_path / "full.json")

        r = subprocess.run(cli + ["--json", "project", "create", "-o", out, "-n", "E2E"],
                           capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        data = json.loads(r.stdout.strip())
        assert data["name"] == "E2E"

        subprocess.run(cli + ["project", "inject", "heading", "-p", out, "--text", "Math", "--level", "1"],
                       check=True)
        subprocess.run(cli + ["project", "inject", "formula", "-p", out, "--latex", "x^2"],
                       check=True)

        r = subprocess.run(cli + ["--json", "project", "info", "-p", out],
                           capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        info = json.loads(r.stdout.strip())
        assert info["word_count"] > 0
        assert info["formula_count"] >= 1
