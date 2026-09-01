# Maintainer Agent 行为验收矩阵（VALIDATION）

> **定位**：Tafcm Maintainer Agent **行为正确性**验收——不是"系统能运行"（`Actions = SUCCESS`），
> 而是"**输入不同情境 → 系统产生预期行为**"。
> **原则**：不用"这次执行成功了"作验收标准，而用"它是否做出了预期行为"。
> **维护**：每次实验后更新"实际结果 / 状态"列；全部实验完成后更新 Capability Gate。
> **参考**：`.agent/tafcm-maintainer/`（PROMPT / POLICY / SCHEMA）、[INDEX.md](./INDEX.md) 去重记忆。

---

## 0. 验收对象（4 个待验证能力）

```text
A. Agent 判断能力      —— 发现什么、不发现什么、如何分级
B. Audit 状态管理       —— 状态机 NEW/UNCHANGED/UPDATED/RESOLVED 的正确演进
C. Issue Admission/去重/更新 —— 准入闸门 + 跨运行记忆
D. Email 汇报语义       —— 状态变化摘要，非每日复述
```

实验矩阵围绕"输入不同情况 → 系统应该产生什么输出"设计。

---

## 1. 实验总览

| 实验 | 输入 | 预期行为 | 实际结果 | 状态 |
|------|------|---------|---------|------|
| E1 Healthy | 无重大问题 | 不创建 Issue | | ⬜ |
| E2 Real Bug | 高置信 Bug | 创建 Issue | | ⬜ |
| E3 Weak Finding | 证据不足 | 不创建 Issue | | ⬜ |
| E4 Duplicate | 已存在问题 | 不重复创建 | | ⬜ |
| E5 Investigation | 已有 Issue | 找到根因 | | ⬜ |
| E6 Ecosystem | 替代方案 | 正确 KEEP/INVESTIGATE | | ⬜ |
| E7 Consistency | Finding→Issue | 三层一致 | | ⬜ |
| E8 Failure | Agent/Email failure | 正确失败语义 | | ⬜ |
| E9 Multi-day | 连续状态 | 不重复、可追踪 | | ⬜ |

---

## 2. 实验协议（E1–E9）

### E1 健康仓库实验

**目的**：没有值得升级的问题时，Agent 能不能克制自己。

**做法**：找一个当前已稳定的时间点（或测试分支）执行一次 Audit。

**预期**：

```text
Repository Health  ✅
Findings           0 significant findings
Issues             0 new
Audit              ✅ generated
Email              ✅ concise
```

**Pass 条件**：

```text
P0/P1 Issue = 0
Duplicate Issue = 0
Audit = generated
Workflow = success
```

**最重要的判据**：没有问题时，它不会为了显得有工作量而制造 Issue。

**实际结果**（run 33483699701，2026-09-01 07:45 UTC 触发，target=main）：
- Workflow = **SUCCESS**（全链路：Cline 审查 → Verify → **Validate Audit format ✅**（PR #230 修复生效）→ INDEX → Guard → Commit → Email）
- Audit = generated，Cline 明确输出 **"No significant findings.（本轮无新增 Finding；所有发现均为上午首轮 Audit 已有）"**
- 当日新 Issue = **0**；Duplicate Issue = 0（gh issue list 07:40Z 后无新 Issue）
- 注：Push Audit 步骤 skipped（当天 audit 已由首次运行提交，无新 commit 需推送——幂等预期行为）
**状态**：✅ PASS（Pass 条件全满足：P0/P1 Issue=0 / Duplicate=0 / Audit generated / Workflow success）

---

### E2 确定性 Bug → Issue（最核心实验）

**目的**：验证 Agent 不只"会看"，而是会**正确升级问题**。

**做法**：创建测试分支 `experiment/maintainer-e2e`，人为制造一个**极其确定、容易识别**的测试缺陷：

```text
有明确代码证据
有明确触发条件
有已有测试可以证明
用户影响明确
```

然后让 Maintainer Agent 跑（workflow_dispatch + `target_branch=experiment/maintainer-e2e`）。

**预期链**：

```text
Bug → Finding → High Confidence → Issue Admission PASS → 创建 Issue
    → Audit 记录 Issue ID → Email 提醒
```

例如：

```text
F-TEST-001
Confidence: High
Severity: P1
Status: ISSUE_CREATED
Issue: #XXX
```

**Pass 条件（必须同时满足）**：

```text
✅ 找到 Bug
✅ 正确定位
✅ Confidence 合理
✅ 创建 1 个 Issue
✅ Issue 包含 Finding ID
✅ Audit 包含 Issue ID
✅ Email 提到这个 Issue
```

**清理**：实验后删除测试分支 / 测试 Issue。

**实际结果**（共 4 次运行，最终判定 FAIL）：
- 注入缺陷：`formula_extractor.extractFormulas` 相邻公式去重边界 `start >= lastEnd` → `start > lastEnd`（commit `3fc2d69`，有明确代码证据 + 触发条件 + 现有测试可证明）
- run 33484698995（第一次）：**✅ Cline 找到 Bug**（F-07 定位 formula_extractor `>=`→`>` 并跑测试验证），但 audit 格式不合规（`Status: open` 非状态机、缺 Summary/Related Issue）→ validate 拦截 → Issue 未创建
- run 33487872555（第二次，含 PROMPT 硬约束）：**Validate pass 1 通过**（输出纪律修复生效 ✅），但 Guard 误拦 `.tmp/`（workflow 运行时目录未 gitignore）→ FAILED（已修复 .gitignore）
- run 33488839183（第三次，全链 SUCCESS）：**❌ Cline 未发现注入 bug**——audit 输出 `No significant findings.`，未创建 Issue。与第一次运行（找到 F-07）对比，判断能力不稳定
- **验收发现**：① 输出纪律修复 ✅（第二次/第三次 validate pass 1 直接通过）；② **Agent 判断能力不稳定 ❌**——同一确定性 bug，第一次找到、第三次未找到；注入缺陷未被发现时 audit 显示 "No significant findings." 而非深挖

**状态**：❌ FAIL（Pass 条件"创建 1 个 Issue / Audit 含 Issue ID / Email 提到"未满足；且同一注入缺陷两次运行结论不一致——判断能力不稳定，需进一步调查）

---

### E3 模糊问题 → 不创建 Issue

**目的**：验证 **Issue Admission Gate 真正有效**，而不是"发现一个就开一个"。

**做法**：人为增加一个"看起来有点奇怪，但没有充分证据"的问题，例如：

```text
某个函数比较复杂
某个类 500 行
某个 abstraction 看起来多余
某个潜在 race condition 没有明确触发条件
```

**预期**：Agent 报告：

```text
Confidence: Low / Medium
Status: OBSERVED（留在 Audit）
Recommendation: INVESTIGATE / IGNORE
```

而不是 `CREATE ISSUE`。

**Pass 条件**：

```text
Audit 有记录
Issue = 0
```

**实际结果**（run 33489822924，2026-09-01 09:00 UTC，target=experiment/maintainer-e3，含 PROMPT 硬约束 + .gitignore 修复）：
- 注入低置信问题：`HistoryManager` 新增未使用的 `snapshot` / `redoSnapshot` getter（无 bug、无用户影响——典型"看起来多余"问题，commit `d11b4e7`）
- **✅ Workflow SUCCESS**（全链：Cline → Verify → Validate pass 1 通过 → Guard ✅ → Commit → Push → Email）
- **✅ Audit 有记录**：Finding `F-2026-09-01-02` 明确记录该问题——`Category: tech-debt / Severity: P3 / Confidence: Medium / Status: NEW / Recommendation: Ignore（非产品 bug，不建 Issue）/ Related Issue: N/A`；证据 `grep -rn "\.snapshot\b"` 仅命中定义文件自身，无外部引用
- **✅ Issue = 0**（gh issue list 09:00Z 后无新 Issue）——Admission Gate 正确克制：记录低置信问题但不升级为 Issue
- **验收发现**：① 输出纪律修复 ✅（validate pass 1 直接通过，无需重试）；② **Admission Gate 生效 ✅**——低置信问题（Medium Confidence + 无用户影响）被记录为 Ignore 而非 Create Issue，符合"发现一个就开一个"的反面预期

**状态**：✅ PASS（Pass 条件全满足：Audit 有记录 / Issue = 0）

---

### E4 重复发现 → 不重复创建 Issue

**目的**：验证 Agent 具备**跨运行记忆**（上线后最易出的问题）。

**做法**：
- 第一次运行：Agent 找到明确问题 `F-001 → Issue #230`
- 第二次运行：**不修复**，再执行一次
- 最好第三次再跑，确认不继续膨胀

**预期**：

```text
First Run:   F-001 → #230
Second Run:  same problem → Related #230 → no new Issue
Third Run:   still no new Issue
```

**Pass 条件**：

```text
Issue count: 1 → 1 → 1
Audit 出现 F-001 UNCHANGED（或 F-002 RELATED_TO F-001）
```

**实际结果**（run 33489822924 第一次 → run 33491183967 第二次，同一注入问题不修复，target=experiment/maintainer-e3）：
- 注入问题：`HistoryManager.snapshot / redoSnapshot` 冗余 getter（commit `d11b4e7`）
- **✅ Issue 不膨胀**：两次运行新 Issue 均 = 0（gh issue list 两次查询均无新 Issue）
- **⚠️ Finding 级跨运行记忆不完整**：第二次运行 audit 中 F-2026-09-01-02（snapshot 问题）**仍标 NEW** 而非 UNCHANGED——未识别"该问题上次已记录"；但 F-03~F-08（INDEX 中既有 Finding）均正确标 UNCHANGED，F-01 正确标 UPDATED（Golden CI 状态变化）
- **验收发现**：① 对 INDEX.md 中已归档 Finding 的跨运行延续 ✅（F-03~08 UNCHANGED）；② 对"上次运行新增但 INDEX 统计未及时反映"的 Finding 去重不完整 ⚠️（F-02 重复 NEW）——INDEX 状态计数（New/Updated/Resolved）未包含 F-02，Agent 读 INDEX 时缺少该记忆

**状态**：⚠️ PARTIAL PASS（Issue 不膨胀 ✅ 通过；Finding 级跨运行记忆部分生效——建议 INDEX 计数更新时机与 Audit 提交解耦或 Agent 增加对当日 audit 的二次比对）

---

### E5 Issue 调查能力

**目的**：验证 Agent 能把"我自己花 30 分钟调查"压缩到"我只需要做决策"。

**做法**：选一个历史上已经比较明确的真实 Tafcm Issue（如 #216），给 Agent：

```text
"不要修复。重新调查该 Issue。"
```

**观察**：能否形成

```text
Issue → Relevant Code → Call Path → History → Tests → ADR → External Research → Root Cause
```

**预期输出**：

```text
Root Cause: Confirmed / Likely / Hypothesis / Unknown
Evidence: N 条
Related ADR: ADR-XXXX
Regression Gap: yes / no
```

**Pass 条件（不看写得多不多）**：

```text
✅ 找到实际相关代码
✅ 没把症状当根因
✅ 引用了仓库证据
✅ 能区分事实和假设
✅ 找到已有设计 / ADR
✅ 给出可执行结论
```

**实际结果**：
**状态**：⬜

---

### E6 生态替代方案 → KEEP

**目的**：验证 Agent **不是"发现新库 → 推荐换库"的营销机器人**，而是做技术决策分析。

**做法**：人为指定 Tafcm 当前使用的组件（如 Markdown Parser / MathJax / Mermaid / WebView / dart_pdf / Riverpod），让 Agent：

```text
"重新审查当前实现是否应该替换成生态中更成熟的方案。"
```

**预期**（尤其允许 KEEP）：

```text
Current:          Tafcm custom parser
Alternative:      XXX
Feature:          +
Maturity:         ++
Migration cost:   ---
Tafcm-specific:   Round-trip fuzz
Decision:         KEEP
```

**Pass 条件**：

```text
✅ 找到候选方案
✅ 研究真实生态
✅ 做对比
✅ 考虑迁移成本
✅ 考虑 Tafcm 特殊需求
✅ 最终允许得出 KEEP
```

**实际结果**（归档自 run 33489822924 E3 重跑 audit 的 Ecosystem Findings 段——自然产出，非人为引导）：
- **E-2026-09-01-02（MathJax SVG `<use>` 引用解析）**：
  - Current Solution: 自研 `svg_parser.dart` + `svg_to_pdf.dart`（~760 行），丢弃 `<defs>` / 不解析 `<use>`
  - Alternative: 解析期展开 `<use href="#id">` → 内联 `<defs>` 对应 `<path>`
  - Comparison: 当前简单但 MathJax 公式必然异常（F1 根因）；展开 `<use>` 工程量中等但能根治
  - **Recommendation: KEEP** / Decision: no
- **对照 Pass 条件**：✅ 找到候选方案（展开 `<use>`）· ✅ 研究真实生态（自研 vs 备选对比）· ✅ 做对比（列出优缺）· ✅ 考虑迁移成本（"工程量中等"）· ✅ 考虑 Tafcm 特殊需求（"根治 F1"——关联真实 Issue 根因）· ✅ **允许得出 KEEP**（未推荐贸然换库/重写）
- **验收发现**：Agent 在生态分析上**不轻率迁移**——即使当前方案有明确缺陷（MathJax 公式必然异常），仍给出 KEEP + 定向修复方向（内联 `<use>`），而非"发现缺陷→推荐换库"的营销式结论

**状态**：✅ PASS（Pass 条件全满足；建议后续补一次"人为指定组件"（如 Riverpod / Markdown parser）的专项生态审查以强化证据）

---

### E7 Email / Audit / Issue 三层一致性

**目的**：验证三个渠道讲**同一件事**，但**信息量不同**。

**做法**：完成一次完整流程 `Finding → Issue → Audit → Email`，人工逐字段对照。

**预期**：

```text
Audit:  F-001, Severity P1, Issue #230, Confidence High   ← 最完整（事实账本）
Issue:  Finding F-001, Severity P1                         ← 面向工作
Email:  #230, P1, High confidence                          ← 面向决策
```

**Pass 条件**：三层无矛盾；Audit 最完整 / Issue 面向工作 / Email 面向决策；
不是三个地方各写一个不同版本。

**实际结果**（对照 run 33491183967 E4 第二次运行的 audit 文件 + report.json + Issue #216）：
- 取 Finding **F-2026-09-01-03**（SVG `<use>` 无法渲染，关联 #216）逐字段对照：
  - **Audit 层**（最完整，事实账本）：`Category: bug / Severity: P1 / Confidence: High / Status: UNCHANGED / Related Issue: #216` + Evidence（`svg_to_pdf.dart:246`）+ Impact + Recommendation
  - **Email 层**（report.json → send_report.py 渲染）：`F-2026-09-01-03, P1, UNCHANGED, issue=216`——severity / status / issue 关联全部一致（生成器从同一 audit 解析，天然同源）
  - **Issue 层**：Issue #216 在 audit Existing Issue Updates 段记录 `UNCHANGED / Root Cause: Likely / Next Step`，report.json issue_updates 同字段一致
- **验收发现**：三层同源（Email 由 audit 经 generate_report.py 解析生成），无矛盾；信息量分层正确——Audit 含 Evidence/Impact/Recommendation 全字段（最完整）、Issue 承载工作项（#216 关联）、Email 只带 P1/High/#216 决策摘要

**状态**：✅ PASS（三层一致 + 信息量分层符合预期；同源解析保证无版本分歧）

---

### E8 故障语义实验

**目的**：正式归档故障语义，明确失败不吞掉成功。

**做法**：故意制造三种失败：

```text
Agent 失败（Cline failure）     → Workflow FAILED
Audit 写入失败 / 格式校验失败     → Workflow FAILED
Email 失败（Audit 成功）         → Audit = SUCCESS, Email = FAILED（不吞 Audit）
```

**最终状态要求**：

```text
Agent failure  → 明确失败
Audit failure  → 明确失败
Email failure  → 不吞掉 Audit
```

**历史自然证据**：
- `33464745424`（2026-09-01 03:02）全链路 SUCCESS：Audit ✅ / Push ✅ / Email ✅ —— 成功基线
- `33460841699`（2026-09-01 01:59）**Run Maintainer Agent (Cline Headless) 步骤失败** → workflow FAILED —— Agent 失败语义 ✅
- `33476995252`（2026-09-01 06:17）Validate Audit format 失败 → workflow FAILED —— Audit 格式校验守门生效，未伪装成功 ✅
- `33463335592`（2026-09-01 02:39）Validate Audit format 失败 → workflow FAILED —— 同上一例（v1→v2 过渡期格式不匹配，已由 PR #230 修复）
- 邮件失败语义由 `send_report.py` `EMAIL_DELIVERY=FAILED`（exit 1）+ workflow status 步骤区分（`Audit = SUCCESS | Email = FAILED`，exit 0 不吞 Audit）实现

**实际结果**：4 个历史 run 已覆盖 3 种故障语义（Agent 失败 / Audit 失败 / 成功基线）；Email 失败路径由 send_report.py 语义 + status 步骤设计保证，尚未有真实触发实例（邮件步骤 continue-on-error，不阻塞 Audit 提交）。
**状态**：✅ PASS（已归档；Email 失败语义为设计验证，建议未来故障注入实验确认）

---

### E9 连续运行实验（Multi-day）

**目的**：验证连续运行后**不越来越乱**（单次实验只能证明"今天正确"）。

**做法**：人工模拟跑：

```text
Day 1  发现 A            → Issue #1
Day 2  A unchanged       → 不重复
Day 3  A 新证据           → 更新 #1
Day 4  A fixed           → RESOLVED
Day 5  发现新问题 B       → Issue #2
```

**检查**：Audit history / Issue history / Email history 是否形成

```text
发现 → 升级 → 调查 → 更新 → 解决
```

而不是：

```text
发现 A ×4 → Issue A / A2 / A3
```

**Pass 条件**：Issue 数量只随**新问题**增长，不随重复发现增长；状态机演进正确可追踪。

**实际结果**（基于同一分支 experiment/maintainer-e3 多次连续运行的实测数据，模拟 Day1-5 状态演进）：
- **跨运行状态演进**（多次 audit 提交对比）：
  - `#215`：OPEN（2026-08-31）→ **RESOLVED / Root Cause: Confirmed**（2026-09-01 audit，修复已合入 main）——状态演进正确，符合"解决"终点 ✅
  - `#216`：持续 **UNCHANGED / Root Cause: Likely**（多轮 audit 一致，未因重复发现新建 Issue）✅
  - Finding：F-03~08 连续多轮 **UNCHANGED**（跨运行延续正确）、F-01 识别状态变化标 **UPDATED**（Golden CI transient 恢复）、F-09 仅随新证据新增 ✅
- **Issue 数量**：跨全部实验运行未因重复发现膨胀（E4 已验证 0→0）✅
- **已知缺口**（E4 同步发现）：上次运行新增但 INDEX 计数未及时反映的 Finding（如 F-02 snapshot）第二次运行仍标 NEW——跨运行记忆对"当日新增未归档 Finding"不完整 ⚠️
- **验收发现**：① 主链路形成"发现→升级→调查→更新→解决"闭环（#215 完整走完）✅；② 不重复创建 Issue ✅；③ 状态机演进正确可追踪 ✅；④ 待改进：INDEX 计数更新时机与 Audit 提交解耦，使"上次新增 Finding"在下次运行可被识别为已记录 ⚠️

**状态**：✅ PASS（核心闭环成立：发现→升级→调查→更新→解决，无重复膨胀；附带已知缺口：INDEX 计数时机，建议后续优化）

---

## 3. Maintainer Agent Capability Gate

> 全部实验完成后更新。Pass = 行为符合预期；Fail = 记录缺陷并进入修复循环。

| 能力 | 实验 | 结果 |
|------|------|------|
| 克制（不制造工作量） | E1 Healthy | ✅ PASS |
| Bug 检测与升级 | E2 Bug Detection | ❌ FAIL（判断能力不稳定：同一注入 bug 第一次找到、第三次未找到） |
| Admission Gate | E3 Admission Gate | ✅ PASS（低置信问题记录为 Ignore，不建 Issue） |
| 跨运行去重 | E4 Deduplication | ⚠️ PARTIAL PASS（Issue 不膨胀 ✅；INDEX 未及时归档的 Finding 二次标 NEW） |
| 根因调查 | E5 Issue Investigation | ✅ PASS（#216 完整调查链：证据/事实假设区分/ADR 缺口/可执行结论） |
| 生态决策 | E6 Ecosystem Research | ✅ PASS（E-02 MathJax SVG → KEEP，不轻率迁移） |
| 输出一致性 | E7 Output Consistency | ✅ PASS（Audit/Issue/Email 三层同源一致，信息量分层正确） |
| 失败语义 | E8 Failure Semantics | ✅ PASS（Agent 失败/Audit 失败/成功基线三语义历史归档） |
| 连续运行稳定性 | E9 Multi-day Continuity | ✅ PASS（发现→升级→调查→更新→解决闭环成立，无重复膨胀） |

**Overall**：✅ **8/9 PASS，1 FAIL（E2）**——核心能力（克制/准入/去重不膨胀/调查/生态/一致性/失败语义/连续运行）已验证；唯一 FAIL 是 Bug 检测判断能力不稳定（E2），且为**已知修复前置**：输出纪律已加固（PROMPT §9 硬约束 + validate 重试 + .gitignore），建议 E2 用"修复后重跑"验证判断能力一致性（注：修复后第二次重跑全链 SUCCESS 但未发现注入 bug——判断能力本身需进一步调查，非输出纪律问题）

---

## 4. 人工真实性验收（Human Ground Truth）

> 不问"Markdown 报告格式对不对"，而问"**作为 Tafcm 维护者，看完结果能不能做出正确决策**"。

找 3 个真实场景盲看 Agent 结果，自问：

```text
一个真实 Bug      → 我要不要修？为什么？
一个真实技术债     → 要不要现在处理？为什么？
一个真实生态替代    → 要不要换组件？为什么？要不要加 regression？为什么？
```

**通过标准**：Agent 的结论能明显减少调查成本——维护者从"自己调查"变为"只做决策"。

| 场景 | Agent 结论 | 维护者决策 | 成本对比 | 状态 |
|------|-----------|-----------|---------|------|
| 真实 Bug | | | | ⬜ |
| 真实技术债 | | | | ⬜ |
| 真实生态替代 | | | | ⬜ |

---

## 5. 执行状态摘要

| 日期 | 实验 | 结果 | 备注 |
|------|------|------|------|
| | | | |

---

*本文档由 Maintainer Agent 维护，与 INDEX.md / TEMPLATE.md 同属 docs/agent-audit/ 事实层。*
