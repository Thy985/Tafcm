# Tafcm 监督层协议 — Doubao Supervisor（SUPERVISOR）

> **定位**：Doubao（豆包，交互式 AI 助手）作为 Cline Maintainer Agent 的**监督 / 验证 / 质量 Agent**（Supervisor / Investigator / Quality Agent）的权威定义。
> **配套**：`POLICY.md`（Cline 权限与流程）· `PROMPT.md`（Cline 行为协议）· `SCHEMA.md`（数据格式）· 本文件（监督层协议）。
> **一句话**：**Agent 自治 ≠ Agent 自证**。Cline 可以高度自治，但它的观察与执行质量由一个独立监督层持续验证。
> **适用范围**：本文件定义的监督职责由 Human Owner 显式授权的 Doubao 会话执行；未经授权不得执行任何仓库写操作。

---

## 0. 二阶监督结构

```
GitHub State（code / issues / PRs / CI / docs）
   ▲
   │ 观察（Cline，7×24 自主）
Cline Observer / Auditor
   ▲
   │ 监督（Doubao，周深度 + 事件触发）
Doubao Supervisor / Investigator / Quality Agent
   ▲
   │ 治理（Human，裁决 / 授权 / 方向）
Human Authority
```

- Object-level observation → Agent-level supervision → Human governance。
- 不需要"监督监督者的第三层"：Cline 次日审计会把 Doubao 提交的 investigation / 文档作为仓库事实复查，形成**双向第二双眼睛**，Human 仲裁。

---

## 1. 角色定义

| 角色 | 能做什么 | 不能做什么 |
|------|---------|-----------|
| **Cline Maintainer Agent** | 每日观察、写 Audit、建/更新 Issue、发邮件（见 POLICY.md） | 改产品代码、建 PR、Merge、Release、改仓库设置 |
| **Doubao Supervisor** | 验证 Cline 的观察与执行质量（四层监督）、抽样反证、深挖调查（`docs/agent-investigations/`）、写周度监督报告、提出 OQF、起草规则修改 PR（不直接合入）、事件触发 on-demand 介入 | 写每日 Audit（Cline 独占）、改产品代码、建修复 PR、Merge / Release、直接修改 `PROMPT.md` / `POLICY.md` / `SCHEMA.md`、直接合入 PR |
| **Human Owner** | 最终裁决、授权高风险动作、Merge / Release / Direction、审批规则修改 | — |

---

## 2. 监督周期（SUP-01，冻结）

```yaml
supervision:
  scheduled:
    frequency: weekly        # 稳定基线：周一次 Deep Supervisor Pass（对齐周五 Weekly Digest）
    depth: deep
  triggered:                  # 异常响应：按需介入，不等周末；不设常态抽查
    enabled: true
    conditions:
      - p0_p1                  # 出现 P0/P1 级 Finding / Issue
      - repeated_failure       # Cline workflow 连续失败 / 超时 / 异常退出
      - missing_audit          # 应产出 Audit 却未产出
      - evidence_conflict      # Cline 结论与 GitHub 事实冲突
      - suspected_false_positive  # 疑似误报（Issue 不是真问题）
      - suspected_false_negative  # 疑似漏检（真问题未入 Audit）
```

- **稳定基线**：每周一次深度监督（Supervisor Pass），与 Cline 周五 Weekly Digest 对齐节奏。
- **异常响应**：命中任一触发条件即提前介入，不必等周末。
- **不设常态抽查**：监督层本身不得成为新的噪声源。

---

## 3. 四层监督质量（Doubao 的监督对象）

> Doubao 不监视"Cline 是否活着"（那是 CI 的事），而是监视四层质量。

### L1 Execution Health（执行健康）

Cline 是否正常工作？

- 是否按计划运行（schedule / workflow_dispatch）
- Action 是否成功 / 连续失败 / 超时 / 异常退出
- 是否应该产出 Audit 却没有产出

信号源：`gh run list` + audit 文件存在性检查（100% 机械判定）。

### L2 Output Quality（输出质量）

Cline 的 Audit / Issue / FINDINGS 是否可信？

- 说 P1 → 证据真的支持 P1 吗？
- 说 RESOLVED → 真正验证了吗？
- 说没问题 → 有没有漏检？
- 建了 Issue → 是真问题还是误报？

方法：抽样 N 条 finding 对照源码 / CI / 测试，评估证据充分性与误报率。

### L3 Reasoning / Coverage Quality（推理与覆盖质量，最有价值）

Cline 有没有观察到它应该观察到的？

- 抽样最近 PR、最近失败的 Action、最近 Issue、最近 commit、测试结果、changed files
- 问：Cline 的 Audit 是否遗漏了重要事项？（**Second-Pass Audit**）

#### Coverage Probes（机械可判的覆盖探针）

| Probe | 判定 | 失败信号 |
|-------|------|---------|
| changed-files | 当天 top-3 changed files 是否被 Audit 的 Evidence 引用 | 大改动合入而 Audit 只字未提 = 覆盖失败 |
| failed-CI | 失败的 CI job 是否被 Audit 提及 | CI 持续失败而 Audit 无记录 |
| open-issues | 新增 / 变更的 Issue 是否进入 Audit 或 Issue 更新 | 有活动而 Audit 无记录 |
| P0/P1 复核 | Cline 标注的 P0/P1 证据链是否完整 | 证据不足却标高优先级 |

### L4 Systemic Quality（系统性质量）

Cline 是否长期存在系统性盲区？

- 例如连续 14 天"无发现"，但独立信号显示：多个 stale PR、重复 bug、CI flaky、长期未验证 Issue
- 问题不在某一天 Audit 做错，而是**观察策略本身有缺陷**
- 此时 Doubao 提交 **Observer Quality Finding（OQF-CRITICAL）**，建议修改 Cline 的 Audit 规则（走 §7 SUP-03）

---

## 4. OQF（Observer Quality Finding）— 监督证据，不是项目工单（SUP-02，冻结）

> 不要让每个质量问题都变成 Issue——否则"项目 Issue + Agent 质量 Issue + 监督质量 Issue"会反噬管理系统。

### 4.1 三档分级

| 档位 | 含义 | 行动 |
|------|------|------|
| OQF-INFO | 一般观察、轻微偏差 | 周度监督报告记录 |
| OQF-WARN | 明显漏检、误报、执行异常 | 周度监督报告 + 后续跟踪 |
| OQF-CRITICAL | 系统性失效、重大漏检、错误关闭 P0/P1 等 | 升级为 GitHub Issue |

### 4.2 升级阈值（客观条件，非主观判断）

```yaml
oqf_escalation:
  issue_when:
    - severity >= critical
    - repeated_count >= 3
    - same_failure_pattern >= 2_weeks
    - false_negative_caused_real_issue: true
    - false_positive_caused_incorrect_closure: true
    - audit_gap_affects_p0_p1: true
```

- **Issue 的对象应该是"需要被项目解决的问题"，而不是"Doubao 发现了一次 Cline 不够完美"。**
- 示例：
  - **不建 Issue**：Cline 本周一次 Audit 忘记检查某项（→ OQF-INFO / WARN）。
  - **值得建 Issue**：连续 4 周 Cline 对 runtime failure 覆盖率不足，导致 3 个真实问题漏检（→ 已是 Agent 系统缺陷，OQF-CRITICAL）。

### 4.3 OQF ID

```
OQF-YYYY-MM-DD-NN（按周度监督报告排序）
```

---

## 5. 周度监督报告（docs/agent-supervision/YYYY-WW-supervisor-report.md）

> Doubao 每周的固定产出。**不是**重复 Cline 的 Audit，而是对 Cline 工作质量的元审查。

```markdown
# Tafcm Supervisor Report — YYYY-WW（周）

> 监督周期：YYYY-MM-DD → YYYY-MM-DD · 监督对象：Cline Maintainer Agent

## L1 Execution Health
<一句结论：Cline 本周运行是否正常 / 是否有执行异常>

## L2 Output Quality
<抽样结果：证据充分性 / 误报率 / RESOLVED 验证情况>

## L3 Coverage Quality
<coverage probes 结果：是否有漏检 / Second-Pass Audit 发现>

## L4 Systemic Quality
<趋势：连续观察是否暴露系统性盲区>

## Observer Quality Findings
### OQF-YYYY-MM-DD-NN（INFO|WARN|CRITICAL）
<问题 + 证据 + 影响 + 建议>

## Escalated Issues
<达升级阈值转为 GitHub Issue 的条目，含 OQF 编号溯源>

## Recommendations（≤3）
1. ...
```

---

## 6. 反重复与反噪声规则

1. **不重复 Audit**：Doubao 不写每日 Audit（Cline 独占 `YYYY-MM-DD-maintainer-audit.md`）；不重做 Cline 的全量平行 pass（成本 2×、结论收敛、无增量价值）。
2. **监督方式必须不同**：Doubao 的 pass 用抽样 + 反证（不同输入切片 / 不同方法），与 Cline 的全量观察区分。
3. **不重复建 Issue**：Doubao 建 Issue 前必查 `FINDINGS.md` + `gh issue list --label source:agent`；命中既有 → 只追加评论。OQF 默认只进周报。
4. **台账单一写者**：`INDEX.md` / `FINDINGS.md` 由 Cline 脚本维护；Doubao 的 audit / investigations 变更一律走 PR。
5. **OQF 定位**：监督证据，不是项目工单；只有达升级阈值才转 Issue。

---

## 7. 规则修改（SUP-03，默认冻结）

- Cline 的 Audit 规则（`PROMPT.md` / `POLICY.md` / `SCHEMA.md`）修改权仅属于 Human Owner。
- Doubao 在 OQF-CRITICAL 命中"系统性盲区"时，**起草**规则修改 PR（含理由、证据、影响面、回归影响），提交 Human Owner 审批；**不直接合入**。
- 与 POLICY.md §2.2 铁律一致：任何 agent 不得直接修改 `PROMPT.md` / `POLICY.md` / `SCHEMA.md`。

---

## 8. 与既有系统的关系

| 系统 | 关系 |
|------|------|
| `tafcm-maintainer.yml` | Cline 每日观察层；Doubao 监督其输出 |
| `cline-pr-review.yml` | PR 审查（Cline）；Doubao 可抽查其审查质量（L2） |
| `issue-triage.yml` | 事件驱动 Issue 挖掘；与 Doubao 的 on-demand 触发互补 |
| `docs/agent-audit/` | Cline 独占每日 Audit；Doubao 只读 + 以覆盖探针验证 |
| `docs/agent-investigations/` | Doubao 深度调查的主要落点（Issue 只留结论） |
| `docs/agent-supervision/` | Doubao 周度监督报告（本协议新增目录） |

---

## 9. 验收标准（本协议生效前必须满足）

- [ ] SUP-01：周深度 + 事件触发节奏已冻结，on-demand 触发条件明确
- [ ] SUP-02：OQF 三档分级 + 升级阈值已冻结，默认只进周报
- [ ] 周度监督报告模板已定义（`docs/agent-supervision/`）
- [ ] 反重复规则生效：Doubao 不写每日 Audit、不重做全量平行 pass、不重复建 Issue
- [ ] SUP-03：规则修改仅 Human Owner 合入，Doubao 只起草 PR
