# Tafcm Maintainer Agent — 数据格式 Schema（SCHEMA）

> **定位**：Tafcm Maintainer Agent 所有产出的**权威格式定义**——Audit 文件、Issue Body、Investigation 文档、INDEX 表、机器可读报告。
> **配套**：`PROMPT.md`（行为协议）· `POLICY.md`（权限与流程）。
> **校验**：`.github/scripts/tafcm-maintainer/validate_audit.py` 强制校验 Audit 文件；INDEX 由脚本追加更新。
> **约定**：所有日期为**审计执行日的本地日期（UTC+8）**，与 main #220 约定一致；Finding ID 使用 `F-YYYY-MM-DD-NN`；生态条目 `E-YYYY-MM-DD-NN`。

---

## 1. 目录结构

```
docs/agent-audit/
├── INDEX.md                  # Audit 历史索引（每次运行由脚本追加一行）
└── YYYY-MM-DD-maintainer-audit.md             # 每日 Audit（本地日期 UTC+8）
docs/agent-investigations/
└── issue-<NNN>-<slug>.md     # 复杂 Issue 深度调查文档（可选）
```

---

## 2. Audit 文件格式（docs/agent-audit/YYYY-MM-DD-maintainer-audit.md）

```markdown
# Tafcm Daily Maintainer Audit

> 运行日期：YYYY-MM-DD（本地 UTC+8）· 触发：schedule / workflow_dispatch

## Repository State

Commit: <HEAD commit sha>
Version: <版本号，如 v0.1.1；无则 N/A>
CI: ✅/❌ <最近 CI 状态摘要（gh run list 结果）>
Tests: ✅/❌ <本地/CI 测试结果摘要>
Build: ✅/❌ <构建状态摘要>

## Findings

### F-YYYY-MM-DD-01

Category: bug|regression|test-gap|architecture|ecosystem|tech-debt
Severity: P0|P1|P2|P3
Confidence: High|Medium|Low
Status: new|open|resolved|won't-fix|duplicate

Problem: <一句话问题描述>
Evidence: <file:line / commit / CI log / 测试输出——必须可追溯>
Impact: <真实影响范围与后果>
Recommendation: <建议方向，不承诺实现>
Issue: <创建的 Issue 编号；未创建则 N/A 并说明原因（如：未过 Admission Gate / 已在 issue #XX 报告）>

### F-YYYY-MM-DD-02
...

（允许没有 Finding——此时写：）

## Findings

No significant findings.

## Issue Investigations

### Issue #<NNN>

Status: investigated|unresolved|in-progress
Root Cause: Confirmed|Likely|Hypothesis|Unknown
Evidence: <证据链摘要>
Recommendation: <建议>
Investigation: docs/agent-investigations/issue-<NNN>-<slug>.md（如有）

（无调查则：）

## Issue Investigations

None.

## Ecosystem Watch

### E-YYYY-MM-DD-01

Topic: <主题>
Current Solution: <当前实现>
Alternative: <候选替代>
Comparison: <Feature/Stability/Performance/Community/维护成本/迁移成本对比摘要>
Recommendation: KEEP|INVESTIGATE|REPLACE|DEPRECATE

（无生态发现则：）

## Ecosystem Watch

No significant ecosystem findings.

## Architecture

<架构漂移 / 依赖违规 / 过时 ADR 观察；无则 No significant architecture findings.>

## Test Gaps

<重要 Finding 的测试缺口分析：为什么没抓住 / 建议哪层加 regression；无则 None.>

## Recommended Actions

1. <最高价值动作>
2. ...
3. ...
```

**校验规则（validate_audit.py 强制）**：
1. 文件存在且文件名匹配 `\d{4}-\d{2}-\d{2}.md`
2. 包含全部必需小节标题（Repository State / Findings / Issue Investigations / Ecosystem Watch / Architecture / Test Gaps / Recommended Actions）
3. Finding 段：`F-YYYY-MM-DD-NN` ID 合法、Category/Severity/Confidence/Status 字段值合法
4. 无 Finding 时出现 `No significant findings.`

---

## 3. Issue Body 格式（Agent 创建）

```markdown
## Finding

F-YYYY-MM-DD-NN

## Severity

P0|P1|P2|P3

## Confidence

High|Medium|Low

## Problem

<一句话问题描述>

## Evidence

<file:line / 复现步骤 / CI log / 测试输出>

## Impact

<影响范围与后果>

## Root Cause

Confirmed|Likely|Hypothesis|Unknown

<根因分析；非 Confirmed 必须标注级别>

## Recommendation

<修复方向 / 验证方法>

## Regression / Validation

<建议测试层：unit/integration/E2E/golden/physical device/regression/contract validation>

## Related

Audit: docs/agent-audit/YYYY-MM-DD-maintainer-audit.md
Issue: <重复相关 issue 编号，如有>
PR: <相关 PR 编号，如有>
ADR: <相关 ADR 编号，如有>
Tests: <相关测试文件路径，如有>
```

**标签**：
- 必加：`source:agent`
- 类别（一或多）：`type:bug` / `type:regression` / `type:test-gap` / `type:architecture` / `type:ecosystem`
- 优先级（且仅一）：`priority:P0` / `priority:P1` / `priority:P2` / `priority:P3`
- 补充（复用仓库已有）：`bug` / `enhancement` / `documentation` 等

**标题**：`[Agent] <concise problem>`

---

## 4. Investigation 文档格式（docs/agent-investigations/issue-<NNN>-<slug>.md）

```markdown
# Issue #<NNN> 深度调查：<一句话主题>

> 调查日期：YYYY-MM-DD · 关联 Audit：docs/agent-audit/YYYY-MM-DD-maintainer-audit.md

## 1. 问题陈述

<Issue 描述 + 触发场景>

## 2. 调查过程

<按 PROMPT.md §3 因果链：相关代码 → 调用路径 → 状态迁移 → 测试 → git 历史 → ADR → 生态>

### 2.1 <阶段标题>

<证据 + 分析>

## 3. 已排除的假设

- <假设 A>：<排除证据>
- <假设 B>：<排除证据>

## 4. 根因结论

Root Cause: Confirmed|Likely|Hypothesis|Unknown

<结论 + 证据链>

## 5. 建议

<修复方向 / 验证方法 / 测试层>

## 6. 参考

- ADR: <编号>
- Commit: <sha>
- Tests: <文件>
```

---

## 5. Audit 历史索引（docs/agent-audit/INDEX.md）

```markdown
# Tafcm Agent Audit Index

> 每次运行后由 `.github/scripts/tafcm-maintainer/update_index.py` 追加一行。
> Agent 每次执行必须先读本表 + 近期 Audit，识别重复 Finding / 未解决 Finding / 长期技术债 / 趋势性问题。

| Date | Findings | Issues | Ecosystem | Open Actions |
|------|----------|--------|-----------|--------------|
| 2026-09-01 | 2 | 1 | 0 | 1 |
```

| 列 | 含义 |
|----|------|
| Date | Audit 日期（本地 UTC+8） |
| Findings | 当日新 Finding 数（F-* 数量） |
| Issues | 当日创建的 Agent Issue 数 |
| Ecosystem | 当日生态条目数（E-* 数量） |
| Open Actions | 当日 Recommended Actions 中未关闭项数 |

---

## 6. 机器可读报告（report.json，邮件输入）

由 `generate_report.py` 从当日 Audit + git 状态生成，**不入库**（仅作邮件中间产物）：

```json
{
  "date": "2026-09-01",
  "commit": "<sha>",
  "version": "v0.1.1",
  "ci": "pass|fail|unknown",
  "tests": "pass|fail|unknown",
  "build": "pass|fail|unknown",
  "findings": [
    {
      "id": "F-2026-09-01-01",
      "severity": "P1",
      "confidence": "High",
      "title": "<problem 一句话>",
      "action": "issue-created|audit-only|duplicate",
      "issue": 123
    }
  ],
  "issue_investigations": [
    {"issue": 100, "root_cause": "Confirmed|Likely|Hypothesis|Unknown", "status": "investigated"}
  ],
  "ecosystem": [
    {"id": "E-2026-09-01-01", "topic": "...", "recommendation": "KEEP|INVESTIGATE|REPLACE|DEPRECATE"}
  ],
  "recommended_actions": ["...", "..."]
}
```

**邮件内容**（Tafcm Daily Maintainer Report — YYYY-MM-DD）由 `send_report.py` 从 report.json 渲染，**不包含完整 Audit**，只报告值得维护者关注的事。

---

## 7. 枚举值（受控词汇）

| 字段 | 合法值 |
|------|--------|
| Severity | `P0` `P1` `P2` `P3` |
| Confidence | `High` `Medium` `Low` |
| Root Cause | `Confirmed` `Likely` `Hypothesis` `Unknown` |
| Category | `bug` `regression` `test-gap` `architecture` `ecosystem` `tech-debt` |
| Status（Finding） | `new` `open` `resolved` `won't-fix` `duplicate` |
| Ecosystem Recommendation | `KEEP` `INVESTIGATE` `REPLACE` `DEPRECATE` |
| Issue 标签 source | `source:agent` |
| Issue 标签 type | `type:bug` `type:regression` `type:test-gap` `type:architecture` `type:ecosystem` |
| Issue 标签 priority | `priority:P0` `priority:P1` `priority:P2` `priority:P3` |

**约束**：超出枚举的值视为格式违规（validate_audit.py 拒绝）。
