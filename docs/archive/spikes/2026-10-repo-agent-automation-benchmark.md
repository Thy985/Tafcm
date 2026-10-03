# Repository Agent Automation Benchmark — 外部对照与 Tafcm 控制面定位

> 生成：2026-10-03 ｜ 输入：Tafcm maintainer/pr-review 300 次真实 run + 7 个外部系统源码级调研
> 方法：全部结论来自一手来源（repo 内 workflow/源码文件原文、官方文档），标注文件级 URL；
> 对内部传闻与本仓库转述做了真伪核验。调研代理：gh-aw / OpenHands / Claude Action /
> run-gemini-cli / Copilot 平台 / Renovate+Dependabot 六路并行。

---

## 0. 一句话结论

Tafcm 的 77% 空转、25% 基建失败、#289 账本自毁**不是"这套 Cline 不够好"，而是
run-centric 形态的结构性后果**：本次抽样的 7 个成熟系统全部是 ledger-centric +
确定性前置闸门，且**样本内未发现 nightly 无界全仓 LLM 扫描被作为默认主提案
通道**（存在性陈述仅限样本，不外推为"行业没有"）。
我们独有的价值（24 个 agent issue 全部闭环的议程供给）在样本内没有对应物——
正确动作是给它加闸门和账本，而不是砍掉或继续调 prompt。

**本文档的边界**：外部 Benchmark 提供的是 control-plane *pattern*，不是 Tafcm 的
canonical implementation。凡与内部 300-run 数据冲突处，以内部数据为准（见 §3、§4）。

---

## 1. 对既有转述的三处核验修正

| 转述 | 核验结果 | 出处 |
|---|---|---|
| gh-aw "agent 默认只读，写走独立 safe-outputs job" | ✅ **属实**：`agent → detection → safe_outputs → conclusion` 四段链，写 token 只在 safe_outputs job；agent 输出经 artifact 传递并被 threat detection 审查；`target:` 是 enforced 不是 validated | github/gh-aw `docs/src/content/docs/reference/threat-detection.md`、`.github/aw/safe-outputs.md` |
| gh-aw "cheap triage → noop → 强模型升级" | ✅ 属实但**形态更强**：便宜层不是小模型，是**零 token 的确定性 shell steps**（"Shell steps run outside the AI sandbox (no tokens)"）；`noop` 是声明式工具且折叠进**唯一母 issue**、记录 noop 烧掉的 AIC | `.github/aw/token-optimization.md`、`actions/setup/js/handle_noop_message.cjs` |
| "gh-aw 有跨供应商限流自动降级" | ❌ **不成立**：`model_fallback.cjs` 仅是配置级兜底（主 model 为空时取值），无 429 运行时 failover。**样本内 7 家未见对应物**——#310 是 Tafcm 自有的 provider-level recovery 设计，正确动作是借鉴 Gemini 的错误分类/sticky 补完它，而非找现成照抄或因"行业没做"而自疑。gemini-cli 的 `modelChains` 比我们多一维：按错误类型（terminal/transient/not_found）决定 `sticky_retry` 还是回弹 | gh-aw `actions/setup/js/model_fallback.cjs`；google-gemini/gemini-cli `docs/reference/configuration.md` L1418-1520 |

附带事实：Claude 官方**废弃了 `fallback_model`**，做法是每 workflow 钉死一个 model
（"Claude Code's default model changes between releases"）——降级链在 Anthropic 是被
主动放弃的路线，坚持无降级≠保守，有降级≠必须做对：我们的分类降级设计要自己守住质量门。

---

## 2. Repository Agent Control Plane 对照表（10 维）

`—` = 该机制缺失。加粗 = 该维度给出了可直接抄的答案。

| 维度 | gh-aw | OpenHands | Claude Action | run-gemini-cli | Copilot 平台 | Renovate | **Tafcm 现状** |
|---|---|---|---|---|---|---|---|
| Trigger | 事件+模糊调度（打散整点）+workflow_run 门控 | label/review_requested；cron 示例默认注释 | 事件+@claude；官方支持 schedule | dispatcher 命令路由到 4 类 job | **仅 PR 生命周期 3 时点**（无每日全扫档）| run interval | 每日 cron 全扫（唯一自由度=时间）|
| Eligibility | `pre_activation` job：预算/deadline/skip-if-match，**数据不全=拒绝启动** | scanner 数 `todo-count>0` 才起 LLM | workflow `if:` + actor 校验 + fork 排除 | search 谓词先筛，空列表跳过 agent step | glob 审批 + 文件类型硬排除 | requireConfig=required | **—（每晚无条件全烧）** |
| Triage/noop | noop 一等公民：折叠单母 issue + **记录 noop 成本** | "记录 no-changes，**这是多数周的预期结果**" | prompt 显式 abstain 条款 | prompt "Precision over Coverage，宁可漏" | 无发现仍产可判定终态契约 | onboardingNoDeps：无事=零输出 | 空转也产整份 audit 文件（26 份/月）|
| Context | "Pull, don't push"：确定性预采压成 JSON 落盘，agent 读文件；>20KB 禁整读 | 7500 token 硬上限注释；GraphQL 补 REST 缺字段 | 实体作用域（单 PR/issue），批量靠预写 dossier | jq 拼 context.json 内联 | instructions 文件体系 + `excludeAgent` 按面排除 | — | **每晚自由重读全仓（空转成本主体）**|
| Identity | 引擎级 + 镜像 digest pinning | 三级：GITHUB_TOKEN/PAT/GitHub App；**无 OIDC** | **OIDC 换短期 Anthropic token**（jti 单次使用细节完备）| App mint 或 GITHUB_TOKEN | copilot[bot]；automation 署名人且不可自批 | — | github-actions[bot]（commit）+ Thy985 混淆（Cline 无独立身份）|
| Permission | **agent job 全只读**，写经 detection→safe-outputs；allowed-files | PR review 只给 `pull-requests:write` 不给 contents；**preflight 权限烟测**（真 POST 再 DELETE，跑前失败）| `--permission-mode auto` + disallowedTools + egress firewall enforce | `--yolo` 但内置工具清零 + MCP 逐工具白名单 + 写 job 再过滤 label | 单分支 push、不可 merge、CI 过前不触发 workflows、firewall allowlist | — | 命令白名单（POLICY §2.3）已有——**这条我们做对了**，但写权限与推理在同一 job |
| Output | 全部带 `max:`/`expires:`/label 归属；PR 强制 draft；"never merge own PRs" | 分支命名含 ISO 周；draft PR | sticky comment + 结构化 outputs + **Haiku 分类内联评论去噪** | Acknowledge 评论带 run 链接 | review cycles | PR + dashboard checkbox 即指令 | issue + audit 文件，无上限无 TTL |
| State/Ledger | `tools.ledger` 6 种类型化模型，独立分支不可变记录，**单条 32KB/patch 10KB 硬顶，compaction 独立受信 job** | claim key 编码进可观测事实（`scan:repo:num:head`、ISO 周）；隐藏 marker 原地改写评论 | concurrency group 按实体 + 分支前缀去重（无 label 状态机）| label 队列自排空；**无跨 run 账本** | 会话按 PR 延续 + session logs | **ensureIssue 单账本原地 upsert**；拒绝=记账状态不是删除 | FINDINGS.md 追加式，写路径与校验同体 → #289 自毁已实证 |
| Failure | `report_incomplete`/`missing_tool`/`missing_data` 显式失败工具（ADR 29804）——**机制性消灭静默无产出** | fail-closed 于未知 conclusion；重试话术必须匹配真实存在的触发方式 | retryWithBackoff + 双层 timeout | 先落 artifacts 再 exit 1；fallthrough 给用户失败评论 | 59min 硬超时、stall 诊断事件、错误分级 | **错误分类学（error.ts）**：infra 错=账本行静默重试，仅配置/契约错才升级红 | Cline 失败→全链红；限流靠 #310 分类降级（方向对，止于模型层）|
| Economics | 统一 AIC 计量，`max-daily-ai-credits` **跨 workflow 日累计硬闸** + 双层并发 | `maxNewPerRun=2` 只计**新开会话**不计检查数；blocked 不占名额 | `--max-turns` + step timeout（无预算体系）| maxSessionTurns + compressionThreshold | **单次 review 明码 $0.05–$1 + Actions 分钟双计量，预算触顶全线停摆** | prHourlyLimit=2 削峰入 Rate-Limited 区**不丢单**；每生态 5 PR 上限 | 免费额度；空转无价格反馈，失败是唯一信号 |

---

## 3. 用这套模型重新解释 Tafcm 的 300 runs

**77% 空转 ≠ 模型差，是三层缺失的算术结果：**
1. 没有 Eligibility 层——样本内 7 家的一致做法是在 LLM 之前放**零 token 确定性闸**
   （OpenHands scanner / Gemini search 谓词 / gh-aw pre_activation / Claude `if:`）。
   "昨晚 main 有没有新 commit、有没有未分诊 issue、有没有文件漂移"全部可以用
   `git diff --since` + `gh issue list` 判定，判定为无 → 不启动 Cline。
2. 空转被**过度生产**：noop 日仍产出一份完整 audit 文件。样本内对 noop 的通用形态是
   一行可机读终态（Copilot "did not comment on any files"）折叠进单一账本
   （gh-aw 单母 issue），26 份/月 → 1 个账本 + 26 行。
3. 空转**无价格**：GitHub 用 AIC 给每次 run 标价、Copilot 用预算触顶自动惩罚空转；
   免费额度让我们对最贵的错误（无价值燃烧）完全无感——这就是为什么 30 天没人
   觉得需要给它加闸门。

**25% 失败 ≠ 稳定性差，是失败语义没分层：**
- 昨晚的限流（provider 层）→ #310 已对齐 gh-aw/gemini 方向（且领先：跨供应商运行时 failover 两家都没有，gemini 的 modelChains 多一个 sticky 维度可抄）。
- #288 静默无产出（agent 层）→ gh-aw 的答案不是兜底文件而是**消灭该状态**：`report_incomplete` 是 agent 的强制出口，"没做完"必须是显式产出而非空。我们目前的 `ensure_daily_audit.py` 兜底是把静默失败合法化，语义相反。
- 工具不匹配 #297（基建层）→ OpenHands 的 preflight 烟测：10 秒内可撤销的真实写操作验证凭据，失败发生在烧 token 之前。
- 结构性对照：Renovate 300 万次 run 里 infra 错误只进账本行（Errored 区，下次重试），**整体 run 不红**；我们任何一层失败都是 workflow 红 → 25% 红率里混着三类本不该同框的东西。

**#289 账本自毁 ≠ 脚本 bug，是写路径结构问题：**
样本内三条独立防线，我们当时一条都没有：① 账本写入与 agent 产物生成分离（Claude：
agent 永无写账权限，账本由 `if: always()` 确定性步骤写）；② 单条写入硬上限
（gh-aw：32KB/条、10KB/patch）；③ 人编辑即让位（Renovate：PR Edited→Blocked，bot
拒写）。#295 修复选择了"整体重建"，恰好是 Renovate `ensureIssue` 语义的简化版——
事后看方向正确，但当时缺一顶 `max-record-kb` 的帽子。

**24 issue 全闭环 ≠ 该模式被验证，是被高估的幸存偏差：**
样本内 7 家均未把 nightly 全扫作为**默认主提案通道**（存在性陈述仅限样本）——Copilot 连"每日全仓扫"这一档都不存在
（价值判断：审查只在变更落地时有意义）；Claude 自仓 3 个 cron 全是零 LLM 脚本。
但我们确实产出了性能战役整批议程（#245-250），这是样本内没有对应物的能力。诚实的表述是：
**"自由全扫"是广度的赌注，闸门化后它仍是独有能力**——只是当前它在为 23% 有产出的日子
支付 100% 的运行成本，样本内的答案一致是把支付结构倒过来。

---

## 4. Tafcm v2：两层扫描架构与改造清单

> **本节已被 v3 取代**（2026-10-03）。v2 的单一 `has-work` 闸会把主动探索一起杀掉，
> 且只拆两段时 Investigator 仍同时承担"调查→判定→写入"。
> **当前权威设计**：[.github/仓库Agent设计与治理.md](../../../.github/仓库Agent设计与治理.md)
> （双路 Eligibility Gate + 四段管道 + L0/L1/L2 按证据来源类型判定 + 三份 JSON Schema 接口）。
> 本节保留为外部对标结论与研究记录；两处冲突以权威设计文档为准——本仓库不接受同一主题有两个真相源。

**v2 目标一句话**：不是让 Maintainer Agent 更聪明，而是让它**只在值得思考时思考，
并且每一次思考都是一个可验证、可计量、可恢复的状态转换**。

样本系统偏 change/issue/PR-driven，而 Tafcm 已验证的最佳成果（#245-250 性能批次）
是 repository-driven——因此 v2 **不砍全仓扫描，而是把它从"默认生产通道"降格为
"探索通道"**，两条通道各配独立预算，不用一个指标逼迫两种行为：

```text
                    Repository
                        │
          ┌─────────────┴─────────────┐
          ↓                           ↓
   Continuous Gate              Exploration Sweep
   高频·便宜·确定性               低频·高成本·主动探索
   Maintenance Budget            Exploration Budget
   目标：高 precision             目标：低频高 recall
          │                           │
       Work?                        Agent
          │                           ↓
          ↓                        Deep Audit
        Agent                          │
          └────────────┬───────────────┘
                       ↓
                    Evidence
                       ↓
                  Governance
                       ↓
                     Ledger
```

这把四件事拆开：**什么时候值得思考 / 思考什么 / 允许产生什么写操作 / 这次发生了什么**。

### P0（砍空转成本，各 <0.5 天）
1. **确定性 Eligibility job（Continuous Gate 第一版）**：`git log origin/main --since=<上次 audit>` +
   未分诊 issue search + FRONTIER.md 漂移检查，输出 `worklist.json` 与 `has-work`；
   `if: has-work` 才起 Cline。先例：OpenHands scanner、Gemini 谓词、gh-aw steps-first。
   nightly 全扫改为每周 1 次 = Exploration Budget 通道（两者共存，互不占预算）。
2. **Canonical Ledger 与 Projection 分离**（修正原 P0-2）：机器账本为唯一真相
   （JSON/NDJSON，如 `docs/agent-audit/ledger.ndjson`），Dashboard issue、FINDINGS.md、
   metrics 都只是它的**只读投影**——改展示永不碰账本。这正是 #289 的结构答案：
   **canonical state 与 human-facing projection 必须分离**。写入加单条 KB 硬顶 +
   写前校验（gh-aw ledger 语义）；agent 无账本写权限，投影由确定性步骤在
   `if: always()` 生成（Claude dogfood 语义）。
3. **noop 终态契约**：gate 判无活时仍写一行可机读 JSON（日期/原因/耗时/token 估算），
   折叠进单账本（gh-aw noop 母 issue 语义），不再逐日生产整份 audit 文件。

### P1（失败分层，各 <1 天）
4. **错误分层语义**：provider 错→#310 降级（已完成）；agent 未完成→PROMPT.md 增加
   gh-aw 式强制出口（"未完成必须显式写 INCOMPLETE 标记，禁止静默"），替换
   ensure_daily_audit 的兜底合法化逻辑；凭据/工具错→OpenHands preflight 烟测步骤。
5. **sticky 降级维度**：#310 的 onError 增加 `transient 同模型先重试一次再换` 与
   `降级成功后粘住 N 小时`（gemini modelChains 的 stateTransitions 语义）。

### P2（结构对齐，各 1-2 天）
6. **读写分离**：Cline job 只读 + 输出 JSON artifact → 新增 safe-writes job（写 token）
   执行 issue create/commit（gh-aw agent→detection→safe-outputs 的单人项目缩水版）。
7. **预算账本**：每 run 记录 duration/turns/成本估算，按 Maintenance / Exploration
   两本账分别记，加各自日/周上限（gh-aw AIC 的免费层平替）——给空转标上价格。

### 成功度量（30 天 A/B，替代原"noop<10%"单指标）
Gate 命中率下降可能与任务质量上升同时发生，单看 noop 率会误判。核心指标组：

```text
gate_skip_rate · agent_activation_rate · llm_cost_per_activation
重大discovery/100_activations* · issue_adopted_rate · review_to_fixup_rate
silent_failure_rate · infra_failure_rate · human_review_minutes/accepted_finding
```

```text
Net Maintainer Value = Accepted Findings + Follow-up Fixes [− 暂不计量: Prevented Regressions]
                       − LLM Cost − Human Review Cost − Automation Maintenance Cost
```

**测量效力警告（有意收紧）**：样本内历史重大发现批次仅 ~3 次，30 天窗的
`*/100 activations` 统计功效不足，只作趋势不作门槛；Prevented Regressions 是
反事实量，无操作化定义前**显式不入账**（候选代理指标：守门测试回归覆盖的
历史 finding 数，另立条目计量）。`human_review_minutes/accepted_finding` 是本期
主问题——"一个被接受的发现花掉多少机器成本与人类注意力"——其余为归因辅助。

**不做**：照搬 Copilot 事件矩阵完全替换每日扫（样本内无人做≠不该做，我们的数据
支持保留广度，双层化即是答案）；OIDC（provider 不支持）；GitHub App 身份
（单人仓库收益<成本）。

---

## 5. 保留判断

- #310 降级链对照后**确认为领先项**（gh-aw 无运行时 failover，Claude 主动废弃），
  与 v2 清单不冲突，P1-5 是其补齐。
- gh-aw maintainer.md 两句原文可直接钉进我们的 PROMPT.md：
  *"should not manufacture comments or changes to prove activity"*、
  *"Treat a whole-run noop as exceptional: inspect the bounded work queue first"*。
- 下一步验证信号：P0 上线后 30 天，按 §4"成功度量"指标组记账——重点不是
  "noop 率降到多少"，而是 `llm_cost_per_activation` 与
  `human_review_minutes/accepted_finding` 双下降，同时
  `issue_adopted_rate` 不掉；Net Maintainer Value 先入账 Accepted Findings +
  Follow-up Fixes − LLM Cost − Review Cost − 元维护成本（Prevented 暂不计量）。

## 附：来源索引

gh-aw：github/gh-aw（.github/aw/token-optimization.md、maintainer.md、safe-outputs.md、
actions/setup/js/model_fallback.cjs、handle_noop_message.cjs、docs/reference/
threat-detection.md、repo-memory.md、adr/29804）。
OpenHands：OpenHands/software-agent-sdk examples/03_github_workflows、
OpenHands/extensions（automations/catalog.schema.json、plugins/pr-review、
skills/github-pr-reviewer/scripts/main.py）。
Claude：anthropics/claude-code-action（docs/setup.md#WIF、action.yml、src/**）、
anthropics/claude-code .github/workflows/*。
Gemini：google-github-actions/run-gemini-cli（action.yml、examples/workflows/**）、
google-gemini/gemini-cli docs/reference/configuration.md。
Copilot：docs.github.com（code-review、cloud-agent、add-custom-instructions、
risks-and-mitigations、usage-based-billing、about-automations）。
Renovate/Dependabot：docs.renovatebot.com（dashboard、automerge、minimum-release-age、
configuration-options）、renovate lib/workers/repository/{dependency-dashboard,error}.ts、
docs.github.com dependabot-*。
