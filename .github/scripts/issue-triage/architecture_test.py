#!/usr/bin/env python3
"""architecture_test.py — issue-triage.yml 不变量守门（ADR-0025 D1/D6/D10）

不变量：
  1. analyze job 权限块不得包含任何 ': write' 字符串（ADR D1：零写权）
     — 唯一例外：id-token: write（OIDC 身份令牌授予，用于 claude-code-action
       向 LLM 代理换取短时鉴权 JWT；它不授予对 repo/issues/PR 的任何写能力，
       与 ADR D1「推理器零写权」的安全语义正交，故显式放行）
  2. create job 权限块不得包含 'contents: write'（ADR D1：仓库文件零写入）
     — 允许 issues: write / pull-requests: write（ADR D1 显式授予）
  3. workflow-level permissions 块不得含 ': write'（除白名单字段）
  4. concurrency 必填（ADR D10：防双触发）
  5. analyze job 必须 needs: extract；create job 必须 needs: analyze（job 顺序契约）

实现策略：纯 stdlib + 正则，不依赖 PyYAML，避免 CI 镜像差异。
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

YML_PATH = Path(".github/workflows/issue-triage.yml")

# create job 允许的写权限白名单（ADR D1 显式授权）
CREATE_JOB_ALLOWED_WRITES = frozenset({"issues", "pull-requests"})

# analyze job 允许的写权限白名单：id-token 是 OIDC 身份令牌授予，
# 非仓库/issue/PR 写权，不违反 ADR D1「推理器零写权」语义，故放行。
ANALYZE_JOB_ALLOWED_WRITES = frozenset({"id-token"})


def _read() -> str:
    return YML_PATH.read_text(encoding="utf-8")


def extract_job_block(text: str, job_name: str) -> str | None:
    """粗略提取从 '  <job_name>:' 起到下一个同级 job 开头。"""
    lines = text.split("\n")
    start = None
    for i, ln in enumerate(lines):
        if re.match(rf"^  {re.escape(job_name)}:\s*$", ln):
            start = i
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if re.match(r"^  [a-z][a-z0-9_-]*:\s*$", lines[j]):
            end = j
            break
    return "\n".join(lines[start:end])


def check_no_write(
    block: str, job_name: str,
    allowed: frozenset[str] = frozenset(),
) -> list[str]:
    """权限块内禁止任何 '<key>: write'，除 allowed 白名单。"""
    errs = []
    pat = r"^\s+([a-z][a-z-]*):\s*write\s*$"
    for m in re.finditer(pat, block, re.MULTILINE):
        key = m.group(1)
        if key in allowed:
            continue
        msg = (
            f"FAIL: {job_name} job contains forbidden "
            f"write permission: {key}: write"
        )
        errs.append(msg)
    return errs


def check_no_contents_write(block: str, job_name: str) -> list[str]:
    pat = r"^\s+contents:\s*write\s*$"
    if re.search(pat, block, re.MULTILINE):
        msg = (
            f"FAIL: {job_name} job contains forbidden "
            f"'contents: write' (ADR D1: zero repo writes)"
        )
        return [msg]
    return []


def check_concurrency(text: str) -> list[str]:
    if not re.search(r"^concurrency:\s*$", text, re.MULTILINE):
        return ["FAIL: missing top-level 'concurrency:' block (ADR D10)"]
    return []


def check_workflow_level(text: str) -> list[str]:
    """workflow-level permissions 块不得含 ': write'。"""
    errs = []
    m = re.search(r"^permissions:\s*\n((?:[ \t]+\S.*\n)+)", text, re.MULTILINE)
    if m:
        for line in m.group(1).split("\n"):
            if not line.strip():
                continue
            if re.search(r":\s*write\s*$", line):
                errs.append(
                    f"FAIL: workflow-level permissions contains "
                    f"': write': {line.strip()}"
                )
    return errs


def check_needs(text: str, job: str, deps: list[str]) -> list[str]:
    """job 必须 needs: <dep>（单行或块形式均可）。"""
    errs = []
    block = extract_job_block(text, job)
    if block is None:
        return [f"FAIL: missing {job} job block"]
    # 单行:  "    needs: extract"
    for dep in deps:
        pattern_inline = rf"^\s+needs:\s+{re.escape(dep)}\s*$"
        # 块形式: "    needs:\n      - extract\n      - foo"
        pattern_block = rf"^\s+needs:\s*\n\s+-\s+{re.escape(dep)}\s*$"
        if not (re.search(pattern_inline, block, re.MULTILINE)
                or re.search(pattern_block, block, re.MULTILINE)):
            errs.append(f"FAIL: {job} job missing needs: {dep}")
    return errs


def main() -> int:
    text = _read()
    errs: list[str] = []
    errs.extend(check_concurrency(text))
    errs.extend(check_workflow_level(text))

    # analyze job：零写权（不允许任何 write）
    analyze_block = extract_job_block(text, "analyze")
    if analyze_block is None:
        errs.append("FAIL: missing analyze job block")
    else:
        errs.extend(check_no_write(
            analyze_block, "analyze",
            allowed=ANALYZE_JOB_ALLOWED_WRITES,
        ))

    # create job：允许 issues: write + pull-requests: write，
    # 禁止 contents: write 与其他
    create_block = extract_job_block(text, "create")
    if create_block is None:
        errs.append("FAIL: missing create job block")
    else:
        errs.extend(check_no_write(
            create_block, "create",
            allowed=CREATE_JOB_ALLOWED_WRITES,
        ))
        errs.extend(check_no_contents_write(create_block, "create"))

    errs.extend(check_needs(text, "analyze", ["extract"]))
    errs.extend(check_needs(text, "create", ["analyze"]))

    if errs:
        print("\n".join(errs))
        print(f"\n{len(errs)} architecture invariant(s) violated")
        return 1
    msg = (
        "OK: issue-triage.yml architecture invariants "
        "satisfied (ADR-0025 D1/D6/D10)"
    )
    print(msg)
    return 0


if __name__ == "__main__":
    sys.exit(main())