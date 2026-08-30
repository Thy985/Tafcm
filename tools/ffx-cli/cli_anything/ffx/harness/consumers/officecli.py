"""officecli 消费端薄封装（ADR-0030 §3.4）。

包装 OfficeCLI：view screenshot（视觉捕获 CAP-WORD-F）+ view issues（结构化问题）。
探测路径复用 docx_qa._find_officecli。
"""
from __future__ import annotations

import json as jsonlib
from pathlib import Path

from .base import ConsumerResult, run_cmd


def find() -> str | None:
    """探测 officecli.exe（复用 docx_qa 的既有路径探测）。"""
    from cli_anything.ffx.core.docx_qa import _find_officecli

    return _find_officecli()


def view_screenshot(docx: str | Path, out_png: str | Path, timeout: int = 120) -> ConsumerResult:
    """officecli view screenshot：渲染 docx 第 1 页 → PNG（Agent/人工可审阅）。

    产物 out_png 由调用方收集。
    """
    officecli = find()
    if not officecli:
        return ConsumerResult(
            exit_code=127,
            summary="officecli not installed (consumer evidence gap — ENV_MISSING)",
            issues=[{"issue": "officecli_missing", "detail": "officecli not found"}],
        )
    rc, out, err = run_cmd(
        [officecli, "view", str(docx), "screenshot", "--page", "1", "--out", str(out_png)],
        timeout=timeout,
    )
    if rc == 0 and Path(out_png).is_file() and Path(out_png).stat().st_size > 0:
        return ConsumerResult(
            exit_code=0,
            summary=f"officecli screenshot ok → {Path(out_png).name}",
            raw=(out + err)[-300:],
        )
    return ConsumerResult(
        exit_code=rc,
        summary=f"officecli screenshot failed (rc={rc})",
        issues=[{"issue": "screenshot_failed", "detail": (out + err)[-300:]}],
        raw=(out + err)[-500:],
    )


def view_issues(docx: str | Path, timeout: int = 120) -> ConsumerResult:
    """officecli view issues：结构化问题清单（Agent 可自愈）。

    issues 必须是 JSON list（schema 校验防输出格式变更误报）。
    """
    officecli = find()
    if not officecli:
        return ConsumerResult(
            exit_code=127,
            summary="officecli not installed (ENV_MISSING)",
            issues=[{"issue": "officecli_missing", "detail": "officecli not found"}],
        )
    rc, out, err = run_cmd(
        [officecli, "view", str(docx), "issues", "--json"],
        timeout=timeout,
    )
    if rc != 0:
        return ConsumerResult(
            exit_code=rc,
            summary=f"officecli issues failed (rc={rc})",
            issues=[{"issue": "issues_query_failed", "detail": (out + err)[-300:]}],
            raw=(out + err)[-500:],
        )
    start = out.find("{")
    if start < 0:
        return ConsumerResult(
            exit_code=2,
            summary="officecli issues: no JSON output",
            issues=[{"issue": "no_json_output", "detail": out[-300:]}],
            raw=out[-500:],
        )
    try:
        data = jsonlib.loads(out[start:])
        issues_raw = data.get("data", {}).get("issues")
        if not isinstance(issues_raw, list):
            return ConsumerResult(
                exit_code=2,
                summary="officecli issues: schema violation (issues not a list)",
                issues=[{"issue": "schema_violation", "detail": out[-300:]}],
                raw=out[-500:],
            )
        return ConsumerResult(
            exit_code=0,
            summary=f"officecli issues ok ({len(issues_raw)} issues)",
            issues=issues_raw,
            raw=out[-500:],
        )
    except Exception as e:  # noqa: BLE001
        return ConsumerResult(
            exit_code=rc,
            summary=f"officecli issues: JSON parse error: {e}",
            issues=[{"issue": "json_parse_error", "detail": out[-300:]}],
            raw=out[-500:],
        )
