"""consumers 薄封装测试（mock subprocess，不依赖真实 wpscli/officecli）。

覆盖：归一化输出形状 {exit_code, summary, issues}、工具缺失 → 127、
officecli issues JSON schema 校验、pdfinfo poppler/wps 双路径。
"""
from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

from cli_anything.ffx.harness.consumers import base
from cli_anything.ffx.harness.consumers import officecli, pdfinfo, wpscli


class _FakeCompleted:
    def __init__(self, rc: int, out: str = "", err: str = "") -> None:
        self.returncode = rc
        self.stdout = out
        self.stderr = err


# ---------- base.run_cmd ----------


def test_run_cmd_ok(monkeypatch):
    monkeypatch.setattr(
        base.subprocess, "run",
        lambda *a, **k: _FakeCompleted(0, "ok-out", ""),
    )
    rc, out, err = base.run_cmd(["echo", "hi"])
    assert rc == 0
    assert out == "ok-out"


def test_run_cmd_exception_is_127(monkeypatch):
    def boom(*a, **k):
        raise OSError("no such tool")

    monkeypatch.setattr(base.subprocess, "run", boom)
    rc, out, err = base.run_cmd(["wpscli"])
    assert rc == 127
    assert "run error" in err


def test_run_cmd_timeout_is_127(monkeypatch):
    def hang(*a, **k):
        raise base.subprocess.TimeoutExpired(cmd=["wpscli"], timeout=90)

    monkeypatch.setattr(base.subprocess, "run", hang)
    rc, out, err = base.run_cmd(["wpscli"], timeout=90)
    assert rc == 127
    assert "timeout" in err


# ---------- wpscli ----------


def test_wpscli_word2pdf_missing_tool_127(monkeypatch):
    monkeypatch.setattr(wpscli, "find", lambda: None)
    res = wpscli.word2pdf("in.docx", "out.pdf")
    assert res.exit_code == 127
    assert any(i["issue"] == "wpscli_missing" for i in res.issues)


def test_wpscli_word2pdf_ok(monkeypatch, tmp_path):
    monkeypatch.setattr(wpscli, "find", lambda: "C:/wpscli.exe")
    out = tmp_path / "out.pdf"
    out.write_bytes(b"pdf")
    monkeypatch.setattr(
        base.subprocess, "run",
        lambda *a, **k: _FakeCompleted(0, '{"type":"completed"}'),
    )
    res = wpscli.word2pdf("in.docx", out)
    assert res.exit_code == 0
    assert "word2pdf ok" in res.summary


def test_wpscli_pdfinfo_fail_issue(monkeypatch):
    monkeypatch.setattr(wpscli, "find", lambda: "C:/wpscli.exe")
    monkeypatch.setattr(
        base.subprocess, "run",
        lambda *a, **k: _FakeCompleted(3, "", "boom"),
    )
    res = wpscli.pdfinfo("x.pdf")
    assert res.exit_code == 3
    assert any(i["issue"] == "pdfinfo_failed" for i in res.issues)


# ---------- officecli ----------


def test_officecli_screenshot_missing_127(monkeypatch):
    monkeypatch.setattr(officecli, "find", lambda: None)
    res = officecli.view_screenshot("in.docx", "out.png")
    assert res.exit_code == 127
    assert any(i["issue"] == "officecli_missing" for i in res.issues)


def test_officecli_screenshot_ok(monkeypatch, tmp_path):
    monkeypatch.setattr(officecli, "find", lambda: "C:/officecli.exe")
    png = tmp_path / "page_1.png"
    png.write_bytes(b"png-data")
    monkeypatch.setattr(
        base.subprocess, "run",
        lambda *a, **k: _FakeCompleted(0, ""),
    )
    res = officecli.view_screenshot("in.docx", png)
    assert res.exit_code == 0
    assert "screenshot ok" in res.summary


def test_officecli_issues_schema_violation(monkeypatch):
    monkeypatch.setattr(officecli, "find", lambda: "C:/officecli.exe")
    # issues 非 list → schema violation
    monkeypatch.setattr(
        base.subprocess, "run",
        lambda *a, **k: _FakeCompleted(0, '{"data":{"issues":"oops"}}'),
    )
    res = officecli.view_issues("in.docx")
    assert res.exit_code != 0
    assert any(i["issue"] == "schema_violation" for i in res.issues)


def test_officecli_issues_ok(monkeypatch):
    monkeypatch.setattr(officecli, "find", lambda: "C:/officecli.exe")
    monkeypatch.setattr(
        base.subprocess, "run",
        lambda *a, **k: _FakeCompleted(0, '{"data":{"issues":[{"id":1},{"id":2}]}}'),
    )
    res = officecli.view_issues("in.docx")
    assert res.exit_code == 0
    assert len(res.issues) == 2
    assert "(2 issues)" in res.summary


# ---------- pdfinfo ----------


def test_pdfinfo_missing_127(monkeypatch):
    monkeypatch.setattr(pdfinfo, "find", lambda: None)
    res = pdfinfo.info("x.pdf")
    assert res.exit_code == 127
    assert any(i["issue"] == "pdfinfo_missing" for i in res.issues)


def test_pdfinfo_poppler_path(monkeypatch, tmp_path):
    monkeypatch.setattr(pdfinfo, "find", lambda: "C:/poppler/pdfinfo.exe")
    pdf = tmp_path / "x.pdf"
    pdf.write_bytes(b"pdf")
    monkeypatch.setattr(
        base.subprocess, "run",
        lambda *a, **k: _FakeCompleted(0, "Pages: 1"),
    )
    res = pdfinfo.info(pdf)
    assert res.exit_code == 0
    assert "pdfinfo ok" in res.summary


def test_pdfinfo_wps_path_uses_json(monkeypatch, tmp_path):
    monkeypatch.setattr(pdfinfo, "find", lambda: "C:/Kingsoft/wpscli.exe")
    pdf = tmp_path / "x.pdf"
    pdf.write_bytes(b"pdf")
    captured = {}

    def fake_run(cmd, *a, **k):
        captured["cmd"] = cmd
        return _FakeCompleted(0, '{"page_count":1}')

    monkeypatch.setattr(base.subprocess, "run", fake_run)
    res = pdfinfo.info(pdf)
    assert res.exit_code == 0
    assert captured["cmd"][0].endswith("wpscli.exe")
    assert captured["cmd"][1] == "pdfinfo"
    assert "--json" in captured["cmd"]
