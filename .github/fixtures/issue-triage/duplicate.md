# Source
type: branch_scan
repository: Thy985/Tafcm
pr: null
base: main
branch: feat/issue-triage-workflow
trust_level: maintainer
fetched_at: 2026-08-12T08:32:00Z

---

# Git Log
- a1b2c3d thy: feat(parser): add inline code branch to BlockLexer._parseInline
  BlockLexer._parseInline 之前缺少 inline code 分支，导致 \`code\` 解析失败。本 commit 补上分支 + 单测。

- b2c3d4e thy: docs(adr): accept ADR-0025 Issue Triage Agent Architecture
  ADR-0025 状态 Proposed → Accepted。同步写入 fixtures 三件 + workflow。

- c3d4e5f thy: chore(ci): add architecture test for issue-triage.yml permissions
  ci.yml 新增 architecture-test job，断言 analyze job 零写权、create job 零 contents:write。