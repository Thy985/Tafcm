# Tafcm Maintainer Agent — 数据格式 Schema（SCHEMA）

> **定位**：Tafcm Maintainer Agent 所有产出的**权威格式定义**——Audit 文件、Issue Body、Investigation 文档、INDEX 表、机器可读报告、邮件。
> **配套**：`PROMPT.md`（行为协议）· `POLICY.md`（权限与流程）。
> **校验**：`.github/scripts/tafcm-maintainer/validate_audit.py` 强制校验 Audit 文件；INDEX 由脚本追加更新。
> **约定**：所有日期为**审计执行日的本地日期（UTC+8）**，与 main #220 约定一致；Finding ID 使用 `F-YYYY-MM-DD-NN`；生态条目 `E-YYYY-MM-DD-NN`。
> **三问原则**（判断本系统设计是否正确的唯一标准）：
> - **Audit** 回答：Agent 到底发现了什么？证据是什么？（**记全**）
> - **Issue** 回答：项目现在到底需要处理什么？（**管住**）
> - **Email** 回答：维护者现在需要知道 / 决定什么？（**提醒与决策**）
> - 三者不得重复写"今天发现了 XXX"。

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

> **定位**：Audit 是**事实账本（Ledger of Facts）**，不是"今天做了什么"的聊天记录。
> 记录：**今天观察到了哪些新事实，以及这些事实现在处于什么状态**。
> 固定五块，缺一不可：

```markdown
# Tafcm Daily Maintainer Audit

> 运行日期：YYYY-MM-DD（本地 UTC+8）· 触发：schedule / workflow_dispatch

## Repository Health

Commit: <HEAD commit sha>
Version: <版本号，如 v0.1.1；无则 N/A>
CI: ✅/❌ <最近 CI 状态摘要（gh run list 结果）>
Tests: ✅/❌ <本地/CI 测试结果摘要>
Build: ✅/❌ <构建状态摘要>

## New Findings

### F-YYYY-MM-DD-NN

Category: bug|regression|test-gap|architecture|ecosystem|tech-debt
Severity: P0|P1|P2|P3
Confidence: High|Medium|Low
Status: NEW|UNCHANGED|UPDATED|RESOLVED|REJECTED|DUPLICATE|WAITING_FOR_HUMAN

Summary: <一句话问题描述>
Evidence: <file:line / commit / CI log / 测试输出——必须可追溯>
Impact: <真实影响范围与后果>
Recommendation: <建议方向（Create Issue / Investigate / Watch / Ignore 等），不承诺实现>
Related Issue: <已建 Issue 编号；未建则 N/A 并说明原因>

### F-YYYY-MM-DD-NN
...

（允许没有新 Finding——此时写：）

## New Findings

No significant findings.

## Existing Issue Updates

### Issue #<NNN>

Status: UNCHANGED|UPDATED|RESOLVED|REJECTED|WAITING_FOR_HUMAN
Root Cause: Confirmed|Likely|Hypothesis|Unknown
New Evidence: <今日新增的证据链摘要（代码路径 / git blame / 测试 / 生态）>
Next Step: <下一步调查或建议>

（无更新则：）

## Existing Issue Updates

None.

## Ecosystem Findings

### E-YYYY-MM-DD-NN

Topic: <主题>
Current Solution: <当前实现>
Alternative: <候选替代>
Comparison: <Feature/Stability/Performance/Community/维护成本/迁移成本对比摘要>
Recommendation: KEEP|INVESTIGATE|REPLACE|DEPRECATE
Decision: <是否值得 PoC：yes/no，理由>

（无生态发现则：）

## Ecosystem Findings

No significant ecosystem findings.

## Pending Decisions

- [ ] <需要维护者决策的事项 1>（关联：F-ID / Issue #NNN / E-ID；建议：<选项>）
- [ ] <事项 2>

（无则：）

## Pending Decisions

None.
```

**校验规则（validate_audit.py 强制）**：
1. 文件存在且文件名匹配 `\d{4}-\d{2}-\d{2}-maintainer-audit\.md`
2. 包含全部必需小节（Repository Health / New Findings / Existing Issue Updates / Ecosystem Findings / Pending Decisions）
3. Finding 段：`F-YYYY-MM-DD-NN` ID 合法、Category/Severity/Confidence/Status 字段值合法（见 §7 枚举）
4. 无 Finding 时出现 `No significant findings.`

---

## 3. Finding 状态机（跨日去重的核心）

> Agent 每天运行前先读现有 Issue + 历史 Audit + 已有 Investigation，判断：
> **"这是新问题，还是旧问题的新证据？"** 然后为每个 Finding / Issue 标记状态。

| 状态 | 含义 | 使用场景 |
|------|------|---------|
| `NEW` | 首次发现的新事实 | 今天新观察到的 Finding |
| `UNCHANGED` | 与上次记录一致，无新证据 | 旧 Finding 今天复查无变化 |
| `UPDATED` | 旧 Finding 今天获得新证据 / 根因升级 / 影响变化 | 持续调查有进展 |
| `RESOLVED` | 已确认解决（代码合入 / 验证通过） | 关闭跟踪 |
| `REJECTED` | 判定不值得修 / 误报（附理由） | 关闭跟踪 |
| `DUPLICATE` | 与既有 Issue / Finding 重复 | 链接到原始项 |
| `WAITING_FOR_HUMAN` | 需要维护者决策或授权才能推进 | 升级到人工 |

**规则**：第二天 Agent **不得**把昨天的发现重新标为 NEW——必须对照历史 Audit 给出 UPDATED / UNCHANGED / RESOLVED 等延续状态。

---

## 4. Issue Body 格式（Agent 创建——工作对象，不复制 Audit）

> **定位**：Issue 是**工作对象**，只放"执行所需要的信息"。
> 打开 Issue 即可开工，**不需要翻当天 Audit**。

```markdown
## Summary

<一句话：问题是什么、影响谁>

## Finding

F-YYYY-MM-DD-NN

## Impact

<影响范围与后果>

## Evidence

<file:line / 复现步骤 / CI log / 测试输出>

## Root Cause

Confirmed|Likely|Hypothesis|Unknown

<根因分析；非 Confirmed 必须标注级别>

## Current Status

<当前状态：调查中 / 待修复 / 等待证据 / 等待决策……>

## Recommended Direction

<建议的修复方向 / 验证方法，不承诺实现>

## Validation Plan

<建议测试层：unit/integration/E2E/golden/physical device/regression/contract validation>

## Related

Audit: docs/agent-audit/YYYY-MM-DD-maintainer-audit.md
ADR: <相关 ADR 编号，如有>
Regression: <相关回归用例，如有>
PR: <相关 PR 编号，如有>
```

**标签**：
- 必加：`source:agent`
- 类别（一或多）：`type:bug` / `type:regression` / `type:test-gap` / `type:architecture` / `type:ecosystem`
- 优先级（且仅一）：`priority:P0` / `priority:P1` / `priority:P2` / `priority:P3`
- 补充（复用仓库已有）：`bug` / `enhancement` / `documentation` 等

**标题**：
- 普通 Finding：`[Agent] <concise problem>`
- 生态 PoC（仅当 Audit E-ID 结论为"值得 PoC"才建）：`[Research] Evaluate <Topic>`

**持续调查规则（关键）**：同一问题的后续证据（9/2 补代码证据、9/3 找到历史提交、9/4 找到生态方案、9/5 根因确认）**必须全部汇总到同一个 Issue**（追加评论更新），**禁止**每天新建 #217 #218 #219 #220。

**生态研究准入（关键）**：生态发现**不直接建 Issue**。先进 Audit 的 Ecosystem Findings（E-ID）；只有当结论变成"值得做 PoC"时才建立 `[Research] ...` Issue。GitHub Issue 不被"新闻"和"研究想法"污染。

---

## 5. Investigation 文档格式（docs/agent-investigations/issue-<NNN>-<slug>.md）

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

## 6. Audit 历史索引（docs/agent-audit/INDEX.md）

```markdown
# Tafcm Agent Audit Index

> 每次运行后由 `.github/scripts/tafcm-maintainer/update_index.py` 追加一行。
> Agent 每次执行必须先读本表 + 近期 Audit，识别重复 Finding / 未解决 Finding / 长期技术债 / 趋势性问题。

| Date | New | Updated | Resolved | Issues | Ecosystem | Pending |
|------|-----|---------|----------|--------|-----------|---------|
| 2026-09-01 | 2 | 1 | 0 | 1 | 0 | 1 |
```

| 列 | 含义 |
|----|------|
| Date | Audit 日期（本地 UTC+8） |
| New | 当日状态 = NEW 的 Finding 数 |
| Updated | 当日状态 = UPDATED 的 Finding 数 |
| Resolved | 当日状态 = RESOLVED / REJECTED 的 Finding 数 |
| Issues | 当日创建的 Agent Issue 数 |
| Ecosystem | 当日生态条目数（E-* 数量） |
| Pending | 当日 Pending Decisions 条数 |

---

## 6.1 Finding 身份注册表（docs/agent-audit/FINDINGS.md，机器维护）

> **定位**：Finding 的**稳定机器身份**（E4 Finding Identity 修复）。解决"同一 Finding 跨运行被标回 NEW / ID 漂移"——identity 不再依赖 Agent 自然语言判断。
> **维护**：`.github/scripts/tafcm-maintainer/fingerprint.py` 每次运行后自动更新（不手工维护）。
> **Agent 用法**：判定"新问题 vs 旧问题"时**先查本表**——category + evidence 文件路径 + 归一化 summary 命中 = 旧 Finding 的延续（标 UNCHANGED/UPDATED，关联既有 Issue），**禁止重新标 NEW / 新建 Issue**。

```markdown
# Tafcm Agent Finding Registry（机器维护，Agent 读取去重）

| fingerprint | latest_id | category | evidence | status | issue | first_seen | last_seen |
|-------------|-----------|----------|----------|--------|-------|------------|-----------|
| ab6e10314f... | F-2026-09-01-01 | tech-debt | history_manager.dart | NEW | N/A | 2026-09-01 | 2026-09-01 |
```

**stable_fingerprint 定义**：`SHA-256(category | evidence_file_paths | normalized_summary)` 前 16 位。
- **category**：受控枚举（bug/regression/...），稳定
- **evidence 文件路径**：从 Evidence 字段提取的**文件名**（.dart/.py/.yml 等，去行号、去目录）——文件比行号稳定（代码移动行号会变）、比完整路径稳定（目录重构会变）
- **normalized_summary**：Summary 小写 + 去标点/空白 + 截断 48 字符——缓解 LLM 措辞漂移
- **设计取舍**：不用自然语言标题（LLM 每次描述不同）、不用行号（代码移动后漂移）、不用完整路径（目录重构后漂移）。证据文件路径是强锚点，归一化 summary 是辅助。

**列说明**：

| 列 | 含义 |
|----|------|
| fingerprint | 稳定身份（SHA-256 前 16 位） |
| latest_id | 该身份最近一次出现的 Finding ID |
| category | 最近一次 Category |
| evidence | 最近一次 Evidence 提取的文件名（逗号分隔） |
| status | 最近一次 Status（NEW/UNCHANGED/UPDATED/...） |
| issue | 最近一次 Related Issue 编号（N/A 未关联） |
| first_seen / last_seen | 首次 / 最近出现日期（跨运行记忆的时间范围） |

---

## 7. 机器可读报告（report.json，邮件输入）

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
      "status": "NEW|UNCHANGED|UPDATED|RESOLVED|REJECTED|DUPLICATE|WAITING_FOR_HUMAN",
      "summary": "<Summary 一句话>",
      "issue": 123
    }
  ],
  "issue_updates": [
    {"issue": 100, "status": "UPDATED", "root_cause": "Confirmed|Likely|Hypothesis|Unknown", "next_step": "..."}
  ],
  "ecosystem": [
    {"id": "E-2026-09-01-01", "topic": "...", "recommendation": "KEEP|INVESTIGATE|REPLACE|DEPRECATE", "poc": "yes|no"}
  ],
  "pending_decisions": ["...", "..."]
}
```

---

## 8. 邮件格式（双邮件：立即 + 周报）

> **原则**：邮件不做每日 Audit 复述，而是**状态变化摘要**——"自上次汇报以来，项目发生了哪些值得你知道的变化？"
> 让维护者 **7 天没看邮箱也不错过上下文**。

### 8.1 立即邮件（P0/P1 / Release Blocker / 安全 / CI 长时间失败）

```
Subject: [Tafcm] Maintainer Alert — YYYY-MM-DD

⚠️ 需要立即关注

- [P0] <Finding / Issue 一句话>
  根因：Confirmed/Likely/Hypothesis/Unknown
  Issue: #NNN

- [P1] ...
```

触发条件（任一）：
- 新 Finding 或 Issue 状态为 P0 / P1
- Release Blocker（构建失败 / 导出阻断 / 数据丢失风险）
- 安全问题
- CI 长时间失败（≥ N 天）

### 8.2 每周 Digest（正常事项汇总，每周五 18:00 北京时间发送）

```
Subject: [Tafcm] Maintainer Digest · YYYY-MM-DD → YYYY-MM-DD

Tafcm Weekly Maintainer Digest

项目状态
CI ✅ / ❌
Tests ✅ / ❌
Build ✅ / ❌

过去一周新增

#217 [P1]
PDF export terminal-state issue
根因：已确认
当前：等待修复

#221 [P2]
Physical-device regression gap
当前：待决定

过去一周解决

✅ #209
Formula fallback regression
已验证关闭

生态变化

🔍 WebView / SVG
发现上游方案 X
结论：值得 PoC

✅ Markdown parser
重新评估后仍然 KEEP

需要你决策

1. #217 是否进入下周修复
2. 是否进行 WebView X PoC

其他
无重要事项
```

---

## 9. 枚举值（受控词汇）

| 字段 | 合法值 |
|------|--------|
| Severity | `P0` `P1` `P2` `P3` |
| Confidence | `High` `Medium` `Low` |
| Root Cause | `Confirmed` `Likely` `Hypothesis` `Unknown` |
| Category | `bug` `regression` `test-gap` `architecture` `ecosystem` `tech-debt` |
| Status（Finding / Issue Update） | `NEW` `UNCHANGED` `UPDATED` `RESOLVED` `REJECTED` `DUPLICATE` `WAITING_FOR_HUMAN` |
| Ecosystem Recommendation | `KEEP` `INVESTIGATE` `REPLACE` `DEPRECATE` |
| Ecosystem POC Decision | `yes` `no` |
| Issue 标签 source | `source:agent` |
| Issue 标签 type | `type:bug` `type:regression` `type:test-gap` `type:architecture` `type:ecosystem` |
| Issue 标签 priority | `priority:P0` `priority:P1` `priority:P2` `priority:P3` |

**约束**：超出枚举的值视为格式违规（validate_audit.py 拒绝）。
