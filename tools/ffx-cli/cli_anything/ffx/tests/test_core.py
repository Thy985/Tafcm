"""Unit tests for ffx-cli core modules."""
from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path

import pytest

from cli_anything.ffx.core import project as proj_mod
from cli_anything.ffx.core import session as sess_mod
from cli_anything.ffx.utils.helpers import find_flutter_root, pretty_print, resolve_cli


# ── project.py tests ──────────────────────────────────────────────────

class TestCreateProject:
    def test_creates_file(self, tmp_path):
        out = str(tmp_path / "test.json")
        p = proj_mod.create_project(out, name="TestDoc", title="A Test")
        assert os.path.isfile(out)
        assert p["name"] == "TestDoc"
        assert p["title"] == "A Test"
        assert "id" in p
        assert "created_at" in p
        assert "updated_at" in p

    def test_overwrites_existing(self, tmp_path):
        out = str(tmp_path / "over.json")
        proj_mod.create_project(out, name="v1")
        proj_mod.create_project(out, name="v2")
        loaded = proj_mod.open_project(out)
        assert loaded["name"] == "v2"


class TestOpenProject:
    def test_loads_valid_file(self, tmp_path):
        out = str(tmp_path / "p.json")
        proj_mod.create_project(out, name="X")
        loaded = proj_mod.open_project(out)
        assert loaded["name"] == "X"

    def test_missing_file_raises(self, tmp_path):
        with pytest.raises(FileNotFoundError):
            proj_mod.open_project(str(tmp_path / "nonexistent.json"))


class TestInfoProject:
    def test_empty_project(self):
        p = {"id": "abc", "name": "Empty", "content": "", "metadata": {}}
        info = proj_mod.info_project(p)
        assert info["word_count"] == 0
        assert info["heading_count"] == 0
        assert info["formula_count"] == 0

    def test_rich_content(self):
        content = """# Hello

Some text with $E=mc^2$ inline.

$$
\\frac{a}{b}
$$

```python
print('hi')
```

```mermaid
flowchart LR A --> B
```

| Name | Age |
|------|-----|
| Bob  | 30  |

![logo](/img/logo.png)
"""
        p = {"id": "x", "name": "R", "content": content, "metadata": {}}
        info = proj_mod.info_project(p)
        assert info["word_count"] > 0
        assert info["heading_count"] >= 1
        assert info["formula_count"] >= 2  # inline + display
        assert info["mermaid_count"] >= 1
        assert info["code_block_count"] >= 1
        assert info["table_count"] >= 1
        assert info["image_count"] >= 1


class TestAnalyzeMarkdown:
    def test_counts(self):
        md = "# H1\n## H2\nparagraph\n$ x $\n$$ y $$\n```js\n1+1\n```\n```mermaid\nA->B\n```\n|a|b|\n|---|---|\n|1|2|\n![img](x)\n"
        r = proj_mod.analyze_markdown(md)
        assert r["word_count"] > 0
        assert r["heading_count"] == 2
        assert r["formula_count"] >= 2
        assert r["mermaid_count"] == 1
        assert r["table_count"] == 1
        assert r["image_count"] == 1


class TestInjectFormulas:
    def test_display_formula(self):
        c = "text"
        r = proj_mod.inject_formula(c, "E=mc^2", display=True)
        assert "$$" in r
        assert "E=mc^2" in r

    def test_inline_formula(self):
        c = "text"
        r = proj_mod.inject_formula(c, "x+y", display=False)
        assert " $x+y $" in r or " $x+y\n" in r


class TestInjectHeading:
    def test_level_one(self):
        r = proj_mod.inject_heading("", "Intro", level=1)
        assert "# Intro" in r

    def test_level_three(self):
        r = proj_mod.inject_heading("", "Sub", level=3)
        assert "### Sub" in r


class TestInjectCode:
    def test_with_language(self):
        r = proj_mod.inject_code_block("", "print(1)", language="python")
        assert "```python" in r
        assert "print(1)" in r

    def test_without_language(self):
        r = proj_mod.inject_code_block("", "1+1")
        assert "```\n1+1\n```" in r


class TestInjectMermaid:
    def test_block(self):
        r = proj_mod.inject_mermaid("", "flowchart LR")
        assert "```mermaid" in r
        assert "flowchart LR" in r


class TestInjectTable:
    def test_basic(self):
        r = proj_mod.inject_table("", ["Name", "Age"], [["Alice", "30"]])
        assert "Name" in r
        assert "Age" in r
        assert "Alice" in r
        assert "30" in r


class TestInjectImage:
    def test_basic(self):
        r = proj_mod.inject_image("", "logo", "/img/logo.png")
        assert "![logo]" in r
        assert "(/img/logo.png)" in r


class TestAtomicWrite:
    def test_no_tmp_left(self, tmp_path):
        out = str(tmp_path / "a.json")
        proj_mod._atomic_write(out, {"k": 1})
        assert os.path.isfile(out)
        tmps = list(tmp_path.glob("*.tmp"))
        assert len(tmps) == 0


# ── session.py tests ──────────────────────────────────────────────────

class TestSession:
    def test_empty_session(self):
        s = sess_mod.ProjectSession()
        assert not s.has_project
        assert s.project_path is None
        assert not s.is_modified

    def test_snapshot_undo_redo(self):
        s = sess_mod.ProjectSession()
        s.set_field("x", 1)
        s.snapshot()
        s.set_field("x", 2)
        assert s.project["x"] == 2
        assert s.undo()
        assert s.project["x"] == 1
        assert s.redo()
        assert s.project["x"] == 2

    def test_empty_stack_undo(self):
        s = sess_mod.ProjectSession()
        assert not s.undo()
        assert not s.redo()

    def test_save_to_path(self, tmp_path):
        s = sess_mod.ProjectSession()
        s.set_field("name", "test")
        out = str(tmp_path / "sess.json")
        saved = s.save_session(out)
        assert saved == out
        loaded = json.loads(Path(out).read_text())
        assert loaded["name"] == "test"

    def test_save_without_path_raises(self):
        s = sess_mod.ProjectSession()
        s.set_field("k", "v")
        with pytest.raises(sess_mod.SessionError):
            s.save_session()

    def test_delete_field(self):
        s = sess_mod.ProjectSession()
        s.set_field("k", "v")
        assert s.delete_field("k")
        assert "k" not in s.project
        assert not s.delete_field("missing")


# ── helpers tests ─────────────────────────────────────────────────────

class TestHelpers:
    def test_resolve_cli_fallback(self):
        cmds = resolve_cli("ffx-nonexistent-cli-test")
        assert len(cmds) >= 2
        assert cmds[0] == os.sys.executable
        assert "-m" in cmds

    def test_find_flutter_root(self):
        # Run from project root to find pubspec.yaml
        root = find_flutter_root()
        # In tests, we may be inside ffx-cli dir; allow None if not under math2
        if root is None:
            pytest.skip("Not running from within math2 project root")
        root_p = Path(root)
        assert root_p.is_dir() and (root_p / "flutter_app").is_dir() or (root_p / "pubspec.yaml").is_file()

    def test_pretty_print_json(self, capsys):
        pretty_print({"a": 1}, use_json=True)
        out = capsys.readouterr().out
        data = json.loads(out.strip())
        assert data["a"] == 1

    def test_pretty_print_human(self, capsys):
        pretty_print({"key": "val"}, use_json=False)
        out = capsys.readouterr().out
        assert "key" in out
        assert "val" in out
