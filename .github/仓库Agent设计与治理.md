# 仓库 Agent 设计与治理

> **范围**：Tafcm 仓库内所有"由调度器触发的 AI Agent 管道"的设计事实、治理约束与演进方案。
> **不含**：应用内的 ADI/ffx 诊断工具链（见 ADR-0024）。
> **一手依据**：本文所有"现状"陈述均指向仓库内真实文件与行号；演进方案的外部依据见
> [spike: Repository Agent Automation Benchmark](../docs/archive/spikes/2026-10-repo-agent-automation-benchmark.md)
> （外部样本仅用于提供 pattern，不作为 canonical implementation；与内部 300-run 数据冲突处以内部为准）。
> **目录约定冲突（待裁决）**：仓库既有文档四层架构把工程真相放在 `docs/engineering/`
> （见 AGENTS.md §7），本文按 Human Owner 指定位置放在 `.github/` 下；如要归位，移文件即可，内容不变。
> **维护约定**：本文是**描述性与规范性文档**，不是 Agent 运行时读的协议。运行时协议仍是
> `.agent/tafcm-maintainer/*.md` 与 `.github/workflows/*.yml`；两者不一致时，以代码为准并把差异登记到 §6 未决问题。

---

## 第一部分 现状：仓库里实际存在两条 Agent 管道

### 1.1 资产清单

| 位置 | 职责 |
|------|------|
| `.github/workflows/tafcm-maintainer.yml` | 夜间维护审查（Cline Headless，单体 run）+ 周五 Digest 邮件 |
| `.github/workflows/cline-pr-review.yml` | PR 触发审查（Cline） |
| `.github/workflows/issue-triage.yml` | Review 事件触发的 Issue 挖掘（Claude Code Action，三段式） |
| `.github/scripts/tafcm-maintainer/` | validate / index / fingerprint / ensure_labels / ensure_daily_audit / report / email / cline_fallback_runner |
| `.github/scripts/issue-triage/` | fetch_input / validate_findings / create_issues + fixtures + architecture_test |
| `.github/schemas/findings.schema.json` | Finding 的机器契约（JSON Schema） |
| `.agent/tafcm-maintainer/` | POLICY / PROMPT / SCHEMA / SUPERVISOR / FRONTIER / models.json / PR_REVIEW_PROMPT |
| `docs/agent-audit/` | 26 份每日 audit + INDEX + FINDINGS 注册表 |
| `docs/agent-investigations/` | 监督层深挖产物（当前 1 份） |
| `docs/agent-supervision/` | 周度监督报告（当前 5 份） |

**关键点：同一仓库存在两种成熟度的控制面。** 管道 A 已经是 ledger-centric + 读写分离；
管道 B 仍是 run-centric 单体。治理文档必须分别描述，不能用一个"仓库 Agent"统称。

### 1.2 管道 A：issue-triage（ADR-0025，已实现目标形态）

```text
extract (deterministic)   → context.md        bash 脚本，零 LLM
analyze (untrusted reasoner) → findings.json  仅 contents:read + id-token:write，输出 JSON-only，"不发任何评论"
create  (trusted executor)   → Issue / 评论   issues:write + pull-requests:write，零 contents:write
```

已在代码里落实的治理机制（不是文档承诺）：

| 机制 | 实现位置 |
|------|---------|
| **权限分域**（推理层零写权 / 执行层零 contents:write） | `issue-triage.yml` D1，L113/L186 |
| **契约前移**：schema 在 analyze 出口和执行器入口各校验一次 | `validate_findings.py`，L171-175 / L212-216 |
| **机器身份不由模型判定**：`fingerprint = sha256(category-component-root_cause)[:16]` 脚本计算，且 prompt 明确要求模型**不要**输出 fingerprint | `create_issues.sh` L60-63 + `issue-triage.yml` L160 |
| **置信度三态门禁**：create / suggest / drop，阈值 `HIGH=0.8` `MED=0.5`，由 awk 比较而非 LLM 裁量 | `create_issues.sh` `decision()` L66-77 |
| **信任级覆盖**：`trust_level ∈ {contributor, fork}` 时任何 confidence 都不自动建 issue；fork 强制 confidence≤0.6 | `decision()` L68-69 + prompt L162 |
| **跨 run 去重记忆**：history.json 以 artifact 传递（D6，Phase B 临时方案，90d 后归零，Phase C 计划落库） | `issue-triage.yml` L205-238 |
| **白名单收口**：labels 走 ADR §D4 枚举，mentions 走仓库贡献者 + 配置白名单 | `mention_whitelist()` / `label_exists()` L79-95 |
| **干跑优先**：手动 dispatch 默认 `dry_run=true`，零 GitHub 副作用 | L47-51 / L223 |
| **离线可测**：`GH_MOCK=1` + fixtures + `run_fixtures.sh` + `architecture_test.py` 常驻 CI | scripts 目录 |

### 1.3 管道 B：tafcm-maintainer（run-centric 单体）

```text
schedule(17:23 UTC 每日) + workflow_dispatch
  → Checkout / Setup Flutter / Install Cline(3.0.60 锁定) / Ensure issue labels
  → Run Maintainer Agent（90min，单体：观察 + 判定 + 写 audit + 建 issue）
      经 cline_fallback_runner.py 按 models.json 降级链调用（#310）
  → Ensure daily audit exists（#288 兜底，缺文件则自动生成）
  → Validate pass1 → 失败则 Retry Agent 修格式 → 最终 gate
  → Update INDEX → fingerprint → FINDINGS.md
  → Guard（仅允许 audit/investigations/FRONTIER 目录变更）
  → Actions 代 commit+push（Cline 无 git push 权限）
  → Log effective model（降级归因）→ report.json → 邮件（continue-on-error，不连坐）
```

治理上**已有**的机制：最小权限矩阵（POLICY §2）、命令白名单/黑名单（`CLINE_COMMAND_PERMISSIONS`）、
越权 Guard 步骤、格式机检 + 一次重试、audit 与邮件成败分离、版本锁定、双通道（Cline 失败即 FAILED）。

治理上**缺失**的机制（相对管道 A）：

1. **观察 / 判定 / 写入都在同一 run、同一上下文**，`CLINE_COMMAND_PERMISSIONS` 的 allow 里直接含
   `gh issue create *`——提出假设者就是批准自己假设者。
2. **产物是散文文件而非账本行**：`docs/agent-audit/<date>-maintainer-audit.md`，一天一份，
   跨运行状态靠 `validate_audit.py` 的格式校验维护，不靠数据模型。
3. **证据等级是模型自评字段**：POLICY.md:197 已写"低置信度 / 无证据 → 只入 Audit，不建 Issue"，
   但 `Confidence` 由 Agent 自填，没有可机械推导的判据。
4. **静默无产出被兜底合法化**：`ensure_daily_audit.py` 在 Agent 没产出时生成一份格式合规的
   "No significant findings." 文件，把"没做完"和"查过确实没问题"压成同一个终态。
5. **无成本计量**：每次 run 不记录 duration/turns/成本估算，空转没有价格。

### 1.4 已设计但未被消费的契约（最重要的一条现状）

仓库里**已经有**目标架构的完整协议，只是没有任何 cron 执行它：

- `FRONTIER.md`（SUP-04）：假设账本的数据模型——`candidate→active→deepening→blocked→verified→cooling→retired`
  生命周期、`next_action: targeted-test / static-trace / code-read / device-validation / regression-check`
  （=分维度证据标准）、闭合必须附 `related_issue` 或 `evidence`、`depth target` 由周度 Supervisor 校准
  而非 Agent 自定（POLICY.md:120）、`activation_reason: changed-code / new-issue / test-failure /
  new-evidence / risk-driven`（=调度器输入）。
- `SUPERVISOR.md`：独立验证层的角色表与节奏（SUP-01：weekly deep pass + 6 个事件触发条件），
  一句话即本文第三部分的主张——**"Agent 自治 ≠ Agent 自证"**。

现状证据：26 份 audit 产出，FRONTIER 里只有 2 条 Entry（FR-001 blocked on #263、FR-002 cooling）。
即：**账本模型建好了，夜间管道没有真正走它**；而 `docs/agent-investigations/`（深挖产物）只有 1 份，
说明 Investigator 阶段只存在于人工交互会话，没有调度化。

> 结论：第三部分的工作**不是发明新架构，而是（a）把管道 A 已验证的控制面移植到管道 B，
> （b）把 FRONTIER/SUPERVISOR 这两个已写好但没接线的契约变成有 cron 的执行阶段。**

### 1.5 模型供给层（#310，已合入 main `cf78545`）

- `.agent/tafcm-maintainer/models.json`：providers（`clineProvider` / `baseUrl` / `keySecret`）+ `chain` +
  `maxAttemptsPerRun` + `onError`（按错误签名分类：rate_limit / timeout / auth / missing_key → next，unknown → fail）。
- **配置里只存 Secret 的名字，永不存密钥值**；新增供应商必须同时在 workflow 增加一行显式
  `X_API_KEY: ${{ secrets.X_API_KEY }}`——这是一处刻意保留的人工评审位，不是冗余。
- `cline_fallback_runner.py` 为 maintainer 与 pr-review 共用；输出前对已知 Secret 做 redact；
  成功时落 `model_used` 归因文件。11 条不变量测试 + models.json schema 校验已进 CI 常驻（ci.yml job `cline-fallback-runner`）。

---

## 第二部分 为什么要改（300-run 账）

量化口径与来源见 spike §3，此处只保留与本文决策直接相关的三条：

- **77% 空转**是**缺确定性 Eligibility 层**的算术结果，不是模型能力问题：夜间全扫无论有无活都启动 LLM。
- **25% 红率**混着三类本不该同框的失败（provider 层 / agent 层 / 基建层），语义未分层。
- **#289 账本自毁**是写路径结构问题：账本写入与 Agent 产物生成未分离、无单条 KB 硬顶、无人编辑让位规则。
- 反向事实：`#245-250` 性能批次的议程供给确实来自这条管道，**广度是它的独有能力**，
  因此方案不砍广度，只给它换出口。

---

## 第三部分 目标设计（v3）

**目标一句话**：不是让 Maintainer Agent 更聪明，而是让它**只在值得思考时思考，并且每一次思考
都是一个可验证、可计量、可恢复的状态转换**。

心智模型改名只在**产物形态同时变化**时才成立：
`Nightly Repository Audit`（"仓库有什么问题？"，产物=散文）
→ `Nightly Engineering Investigation`（"今晚哪个工程假设值得实验验证？"，产物=账本行 + artifact）。
若仍每天产出一份 md，改名等于零。

### 3.1 主链

```text
                              Schedule
                                 │
                   ┌─────────────┴─────────────┐
                   ↓                           ↓
          Maintenance Gate              Exploration Gate
        changed_code / new_issue       exploration_due
        test_failure / ci_red          && exploration_budget
        frontier_change                (scheduled_slot / frontier_stale
                   │                   / structural_churn / coverage_floor)
                   │                           │
                   └─────────────┬─────────────┘
                                 ↓
              eligible = maintenance_work OR exploration_due
              否 → 写一行 NO_WORK 终态（零 token），结束
                                 ↓
                     Dimension Scheduler（零 token）
                     领域 + 工作集 + Top-N 队列 + 分数分解
                                 ↓
        ┌── Run 1 ─────────────────────────────────────────┐
        │ Scout（只读，无 issue 权，无账本写权）             │
        │ Planning → 实验设计 → 静态分析 / 轻量执行 → 观测    │
        │ 产出 = 可实验假设（含 invariant + falsifier）      │
        │ 出口 = L0/L1 candidate 进 Hypothesis Ledger        │
        │ 无异常 = NO_FINDING 账本行（合法体面出口）          │
        └───────────────────────┬───────────────────────────┘
                                ↓
                     Deterministic Top-N（分数见 3.5）
                                ↓
        ┌── Run 2 ─────────────────────────────────────────┐
        │ Investigator（只读 + 零写权沙箱执行）              │
        │ 复现 / benchmark / 差分对照 / profile              │
        │ 产出 = evidence_bundle（含复现物 + 凭证申报）      │
        │ **无 issue 权、无账本写权**                        │
        └───────────────────────┬───────────────────────────┘
                                ↓
        ┌── Run 3（无 LLM）────────────────────────────────┐
        │ Deterministic Verifier                            │
        │ 干净 checkout 重跑复现物 / 校验预期出处 / 算        │
        │ fingerprint / 查预算 / 扫密钥 → verdict            │
        └──────────┬────────────────────┬───────────────────┘
                   ↓                    ↓
                 reject               verified
                   │                    ↓
             仅记账本           Publisher（纯脚本）
                              create_issue / comment_existing
                                       ↓
                              Ledger transition（确定性步骤写）
                                       ↓
                        Projection：FRONTIER.md / FINDINGS.md / Dashboard
                                       ↓
                              Governance（Human Owner 裁决）
```

**四个结构决定，不可协商：**

```text
观察 ≠ 判定 ≠ 证明 ≠ 写入
Scout 的成功指标不是"找到 3 个 bug"，而是"找到 2 个值得花预算验证的假设"
Agent 可以提出假设、设计实验、执行实验、解释实验；
  但"这个结果是否足以改变仓库状态"由机器协议决定
Issue publisher 不相信 investigator 的 confirmed 自述，只消费 evidence_bundle + verdict
```

**为什么是四段而非两段**（对上一版"Scout / Investigator 两段"的自我修正）：
只拆两段时，Investigator 仍然同时承担"调查 → 判定 → 写 Issue"，
只是把三件事搬进了同一个 run——与"观察/判定/写入分离"的原则不符。
拆成四段后，**没有任何 LLM job 持有 GitHub 写权**，且最后一段甚至不需要模型。
这不是新发明：管道 A 的 `analyze → validate → create`（§1.2）已经是这个骨架，
`create_issues.sh` 的 `decision()` 已经证明"发布与否由 awk 阈值而非模型裁量"可落地。

**两道 run 边界的硬理由**（保留）：Cline 步骤现为 `timeout-minutes: 90`，
"实验设计→执行→深挖"是最长的长尾，会在实验中途被砍；**半截调查是比空转更糟的新噪声类**
（它带着"我快证明了"的口吻）。段边界同时让 `created_by_run ≠ verifier_run` 成为结构强制。

**双路 Gate 的必要性**（对上一版的硬修正）：单一 `has-work` 会把最想保留的能力一起杀掉——
"仓库没有新 commit / 没有新 issue / FRONTIER 没漂移"**不等于**"今天不值得主动探索"。
若只留 change-driven 一条，v3 就退化成"砍掉 nightly scan"，恰好砍掉 `#245-250` 那类
已被内部数据证实有价值的产出。因此两条 eligibility 各判、各记预算、各出指标：
maintenance 通道要 precision，exploration 通道要低频高 recall，**不用一个指标逼迫两种行为**。

**Scout 的产出物是"值得验证的假设"，不是"bug 结论"**——这是 Agent objective 的变化，不是措辞变化：

```text
Hypothesis:   autosave path 随文档体积恶化
Evidence:     DocumentController → serializeDocument() 出现在每次 change 上
Experiment:   100 / 500 / 1000 次编辑 × 1KB / 100KB / 1MB 文档
Expected:     bounded scaling
              出处 kind=passing_test → flutter_app/test/performance/block_lookup_scaling_test.dart
              基线 kind=golden_baseline → test/performance/perf_baseline.json + perf_ratchet_test.dart
Falsifier:    延迟随文档体积保持平坦 → 假设不成立
Tier:         L0（此阶段无执行记录）→ Investigator 跑完实验且对照成立才可能到 L2
```

于是行为从 `code reading` 变成 `hypothesis-driven engineering`：Scout 一晚的成功不是"找到 3 个 bug"，
而是"找到 2 个值得花预算做实验的假设"。

### 3.2 证据分级：按证据来源类型判定，不按 run 数量判定

| 级别 | 判据（可由脚本校验） | 出口 |
|------|----------------------|------|
| **L0 静态怀疑** | 只有代码位置 + 推理；`invariant_source.kind = self_authored`；无执行记录 | Hypothesis Ledger |
| **L1 观测异常** | 有实验执行记录/输出，但预期出处仍为本次自建，或无对照臂 | Hypothesis Ledger |
| **L2 可复现发现** | 三条件**合取**（见下） | Publisher → Issue |

```text
L2 = stable_reproduction ∧ independent_proof ∧ deterministic_rerun
       （复现物已提交且重跑结果与申报一致）
     ∧ independence_proofs_granted 非空 且 invariant_provenance = pass
       （预期出处不是本次自建）
     ∧ 由普通 CI job / verifier 在干净 checkout 执行（不由 Agent 执行自己写的测试）
附加约束：tier_run_separation（verifier run_id ≠ created_by_run）
```

**独立性凭证类型**（`independence_proofs` 枚举，取代"不同 run 即独立"）：

```text
preexisting_oracle      预期引用本次之前就存在的通过测试 / ADR 条款 / dartdoc 契约 / golden baseline
differential_test       至少两个对照臂（新旧路径 / 局部改动对照 / 两渲染器）
clean_checkout_reproduction  复现物落在干净 checkout 可定位处
deterministic_ci_rerun  由确定性步骤重跑，结果与申报一致
external_contract       预期来自仓库外的一手规范
```

`不同 run` 只是**必要非充分**条件：形式上两次 run，认知上仍可能是同一个 Agent
"自提假设 → 自设计证据 → 自解释证据"。所以独立性按**来源类型**判定。

**机械阻断点**：`invariant_provenance` 检查 `ref_commit` 能被 git 解析**且早于**本 hypothesis 的
created run——这是"Agent 写错测试自证 bug"这条闭环唯一可被脚本掐断的位置。

**成本与副作用（必须记在文档里，不能只在讨论里）**：允许 Agent -authored 的复现代码在 CI 执行，
等于把任意代码执行面引入仓库 CI。约束方式：复现物只在**零写权、无写用途 Secret** 的独立 job 里执行
（`experiment.sandbox` 字段申报 + verifier 的 `sandbox_isolation_verified` 回查），
且**不得**在持有 `contents:write` 的 maintainer job 内执行。管道 A 之所以没有这个暴露面，
正是因为它规定 analyze "输出 JSON-only，不发任何评论"、模型从不产可执行代码（`issue-triage.yml` L161）。

> 已有先例：管道 A 的 fingerprint 由脚本算、decision 由 awk 比阈值、`trust_level=fork` 强制
> confidence≤0.6。本文只是把同一原则从"confidence"换成"L0/L1/L2 + 凭证存在性"。

### 3.3 Hypothesis Ledger：系统的核心对象，不是中间产物

它应当被定义为**整个 Repository Agent 的工作队列**：Scheduler 问的不是"今天跑什么 prompt"，
而是"今天 frontier 上哪三个问题最值得投入预算"。系统形态因此从 `Cron → Agent` 变成闭环：

```text
Repository State → Frontier → Scheduler → Agent → Evidence → Frontier update
```

- 机器账本为唯一真相：**append-only NDJSON 事件流**
  （`.github/schemas/ledger-event.schema.json`），每行含 `actor` / `run_id` / `budget_bucket` /
  `evidence_tier` / `independence_proofs` / `verdict` / `cost` / `record_kb`。
- `docs/agent-audit/INDEX.md`、`FINDINGS.md`、`FRONTIER.md`、Dashboard issue、metrics
  一律是这条流的**只读投影**——改展示永不碰账本。这正是 #289 的结构答案。
- **`FRONTIER.md` 的 7 态生命周期直接复用，不新建状态机**。与它正交的还有两条轴，三者必须分清：

  | 轴 | 取值 | 含义 |
  |----|------|------|
  | `lifecycle_stage` | candidate→active→deepening→blocked→verified→cooling→retired | 在队列的哪一段 |
  | `evidence_tier` | L0 / L1 / L2 | 被证到什么程度 |
  | `publisher_action` | create_issue / comment_existing / suggest_only / drop | 机器允许怎样改变仓库状态 |

- 写入约束：单条 KB 硬顶 + 写前 schema 校验；账本由确定性步骤在 `if: always()` 写，**Agent 无账本写权限**。
- **tier 提升到 L2 与 `verified` 迁移只能由 Verifier（无 LLM 段）触发**；由 `created_by_run` 同一 run
  提出的 confirmed 一律被 `tier_run_separation` 检查拒掉。
- 去重与追加：`fingerprint` 命中历史 → `comment_existing`（同一问题的后续调查汇总到同一 Issue，
  POLICY.md:201 既有纪律，禁止每天新建同主题 Issue）。

### 3.4 noop 终态契约

两路 Gate 都不放行时写一行可机读 JSON（`gate-result.schema.json` 的 `noop_record`：日期 / 原因 /
耗时 / 是否零 token）进单一账本，
**删除 `ensure_daily_audit.py`**：它把静默失败伪装成正常产出，语义与"NO_FINDING 是体面出口"相反。
Agent 未完成时必须显式写 `INCOMPLETE`（强制出口），禁止静默。

### 3.5 维度与预算

- 首批 **2 个** Scout 维度：**Performance**、**Correctness / Test Gap**。
- **Architecture / Data Flow 改为两层，而不是"取消 Agent"**（修正上一版"完全下沉到确定性 Gate"的过头表述）：
  22 个守门测试（layer_dependency / ui_dependency_direction / provider_uniqueness / file_access /
  file_size / no_print …）能覆盖的是**已知 invariant**；而 `new abstraction / wrong responsibility /
  duplicated state / coupling drift / unnecessary indirection / boundary violation` 这些
  尚未被现有测试表达的形态，机器判不了。正确的分层是：

  ```text
  Architecture
    ↓ Deterministic Architecture Gate（已知违规 → 自动发现，零 token）
    ↓ 无违规 → 正常不启动 LLM
    ↓ 仅当 frontier_stale || structural_churn 高 → 低频 Architecture Investigation
  ```

  即 **Architecture 的第一层观察机器化，而不是每天让 LLM 自由审**——不是"不需要 Agent"。
  触发条件写在 `gate-result.schema.json` 的 `exploration.reasons`
  （`structural_churn` = `lib/` 下新增文件 / 新目录 / 新 Provider 定义的 git 统计）。
- 每维度配 **investigation protocol**（各自的证据标准），而不是共用一条越来越长的 PROMPT：
  Performance 要 benchmark/profile/复杂度；Correctness 要 reproduction + test case；
  Export 要 `输入 → 中间表示 → 输出 → 实际 artifact 比对`。
  **Performance 维度可最先落地**，因为 `preexisting_oracle` 凭证已有现成落点：
  `flutter_app/test/performance/` 下已有 `block_lookup_scaling_test.dart`、`perf_baseline.json`、
  `perf_ratchet_test.dart`（基线即 oracle，不必由 Agent 自建预期）。
- **Top-N 选择必须确定性打分**，且公式里证据成本在**分母**：

  ```text
  Priority Score = risk × churn × staleness × activation_weight × expected_value
                   ÷ evidence_cost
  ```

  把 `evidence_cost` 当乘项会让**最烧预算的实验排最前**（上一版的错）。
  让 LLM 选 Top-N 或让 LLM 填公式里的数值，闸门就白装——但**完全不依赖模型标注也不现实**，
  所以规则是"LLM 可标注、脚本封顶"：`risk` / `expected_value` 从 `severity` 枚举派生，
  而 `severity` 受 tier 天花板约束（`L0/L1` 不得标 `critical/high`，由写入步骤强制降级）。
  ADR-0025 的 `fork → confidence≤0.6` 是同一手法的既有先例。其余三项
  （churn / staleness / activation_weight / evidence_cost）全部机械可得。
- **成本归因到工作集大小，不归因到日历条数**：限定文件清单的专题 Scout 比无界全扫更便宜。
  真贵的是 Investigator，所以它的入口必须是 Top-N 且 N 小。
- 两本账分开记：Maintenance Budget（高频·便宜·确定性，目标高 precision）/
  Exploration Budget（低频·高成本·主动探索，目标低频高 recall），各设日/周上限。

### 3.6 成功度量

30 天窗口内**先只记可精确度量的**：

```text
gate_skip_rate · agent_activation_rate · llm_cost_per_activation
issue_adopted_rate · review_to_fixup_rate
silent_failure_rate · infra_failure_rate · human_review_minutes/accepted_finding
```

```text
Net Maintainer Value = Accepted Findings + Follow-up Fixes [− 暂不计量: Prevented Regressions]
                       − LLM Cost − Human Review Cost − Automation Maintenance Cost
```

**测量效力约束（有意收紧）**：历史重大发现批次样本仅 ~3 次，`*/100 activations` 类指标在 30 天窗
统计功效不足，**只作趋势不作门槛**；Prevented Regressions 是反事实量，无操作化定义前显式不入账
（候选代理：守门测试回归覆盖的历史 finding 数，另立条目计量）。

**影子期分母纪律**：gate 步骤是 `continue-on-error: true`，失败夜晚步骤仍显示 success。
这类夜晚**必须从 `gate_skip_rate` / `agent_activation_rate` 的分母中显式剔除或单独标注**，
否则算出来的空转率是假的。`tafcm-maintainer.yml` 里 `Alert — Eligibility Gate 本夜未产出判定`
步骤负责把缺席写在 step summary 与 workflow annotation 上；**剔除依据本身是机器可读的**——
同一步骤会写 `.tmp/tafcm-maintainer/gate-failure.json` 进 artifact。
判定规则：`gate-result.json` 缺失且 `gate-failure.json` 存在 = 本夜不计入分母；
两者都缺 = 该 job 根本没跑（另按基建失败处理，同样不计入）。

**Scout vs 全扫的比较用"同夜影子跑"**，不用前后分段——每晚 1 次、n≈30/臂的顺序分段会被 main 活跃度混淆。
影子跑：全扫照旧 + 每晚 1 个专题 Scout，比较单位是**每条 finding 的证据完整度**与
**Scout→Verifier 的 verified 转化率**（不是 Agent 自报的 confirmed），不是原始 finding 数。

### 3.7 不做

照搬事件驱动矩阵完全替换每日扫（样本内无人做 ≠ 不该做；广度有内部数据支撑，双层化即是答案）；
OIDC（provider 不支持）；GitHub App 身份（单人仓库收益 < 成本）；一次性上线 7 个维度。

### 3.8 三个核心接口（已定死，先于任何 Scout Prompt）

**顺序原则：接口先于 prompt。** 一旦这三个接口稳定，后续 Cline / Claude / Gemini 乃至换掉整个
Agent 层都只是**执行器替换**，而不是再重构一次治理面。三份契约已落成 draft-07 JSON Schema，
与既有 `.github/schemas/findings.schema.json` 同构（identity 一律由脚本计算、模型不得输出）：

| 接口 | 文件 | 生产者 | 关键约束 |
|------|------|--------|---------|
| **Hypothesis Ledger** | `.github/schemas/ledger-event.schema.json` | 确定性写入步骤（Agent 无写权） | append-only 事件流；`actor`+`run_id` 每行必填；`hypothesis.invariant_source.kind` 决定可达 tier 上限；`record_kb` 落盘前校验 |
| **Dual Eligibility Gate** | `.github/schemas/gate-result.schema.json` | 零 token 步骤 | `eligible = maintenance.work_present OR exploration.due`；`additionalProperties: false`（禁止把 LLM 输出夹带进 gate）；`dimension.workset` 是 Agent 的观察边界=预算来源；`noop_record` 是 NO_WORK 的机读终态 |
| **Deterministic Verifier** | `.github/schemas/verdict.schema.json` | 无 LLM 段 | 14 项 `checks` 全为执行结果/git 事实；`tier_granted` 由 verifier 重判、不接受上游申报；`publisher_action` 四态；`reject_reason_code` 枚举；`x-l2-definition` 把 L2 写成三条件合取 |

接口的三条硬读法：

1. **Publisher 只读 `verdict` + `evidence_bundle`**，不读 Investigator 的自然语言结论；
   publisher 自身是纯脚本，`ledger.verdict` 内嵌的那份才是它唯一的输入。
2. **Gate 结果里没有任何字段可以由模型填写**——`additionalProperties: false` 是为此而设。
3. **`invariant_source` 是 L0/L1/L2 的分水岭**，因为它是唯一能被 `git rev-parse` / `git log -1 --format=%cd`
   机械否证的字段。

**契约不靠文档约束**：`.github/scripts/tafcm-maintainer/validate_agent_contracts.py`（纯 stdlib）
校验三份 schema 的单文件约束 + **跨文件枚举一致性**（维度 / 独立性凭证类型 / publisher 动作 / actor），
由 `ci.yml` job `agent-control-plane-contracts` 常驻。跨文件一致性是它的存在理由——三份契约各自演化时
Scheduler / Scout / Investigator / Verifier 的字段语义会悄悄分叉，workflow 层看不出异常，
直到账本投影写不出来。守门有效性已做红-绿验证：临时把 `gate-result` 的 `ux_state` 改成 `ux_status`
→ 脚本 exit 1 并报枚举漂移；改回 → exit 0。

---

### 3.9 已落地：P0-1 双路 Gate（影子模式）

| 件 | 位置 |
|----|------|
| Gate + Scheduler | `.github/scripts/tafcm-maintainer/eligibility_gate.py`（纯 stdlib，`--fixture` 注入信号） |
| 写前校验器 | `contract_minicheck.py`（draft-07 子集：type/enum/required/additionalProperties/items/minItems/pattern/$ref） |
| 不变量测试 | `eligibility_gate_test.py`（37 例）+ `contract_minicheck_test.py`（16 例） |
| 接线 | `tafcm-maintainer.yml` step `Eligibility Gate (shadow)`，产物 `gate-result.json` 进 artifact；失败夜另由 `Alert — Eligibility Gate 本夜未产出判定` 步骤标注（§3.6 分母纪律） |
| 守门 | `ci.yml` job `agent-control-plane-contracts` 跑上述两份测试 |

**影子语义（刻意）**：闸门只记录判定，Cline 仍每晚执行；`continue-on-error: true`——闸门自身缺陷
不得红掉夜间管道，缺陷在 artifact 与 step summary 留痕。攒够真实夜晚的 `gate_skip_rate` 与误判样本后，
再把 `eligible=false` 变成真正的激活条件。

八条由测试或评审逼出来的实现规则（不是风格选择）：

1. **缺数据 ≠ 陈旧**。`dimension_state` 为空若被当作"90 天没查"，探索通道会每晚放行，
   闸门立刻退化成它本该关闭的每日无界全扫。只有在探测记录里确实没出现过、或有明确日期且
   已超期才算陈旧（`never_probed` 由 §3.10 那个单一读取函数给，不从维度状态里读）。
2. **维度映射取最具体前缀**。`flutter_app/lib/`（architecture，最便宜）会吞掉
   `flutter_app/lib/presentation/` 下的全部变更，把每次 run 都派到成本最低的维度——
   正是"漂向易实验模块"这个偏差在代码层的复现。
3. **两本账分别扣减**。`maintenance 耗尽 + exploration 耗尽` 必须得出 `eligible=false`；
   早期写法在这种组合下会算出 true，等于预算上限形同虚设。`no_work` 与
   `*_budget_exhausted` 是不同终态，混淆会让空转率指标说谎。
4. **契约形状就是接口，消费方必须按形状解析**。首版把账本候选 id 当序号 `int(c)` 重排，
   而契约与 `ledger-event.hypothesis_id` 规定的是完整字符串 `HYP-007` → 账本一接上就
   `ValueError` 裸 traceback（`evaluate()` 调用点在 `main()` 的 try 之外）。修法是原样透传、
   无法归一的形状交给写前契约校验拒绝，**不在闸门内部静默修形**。
   21 例测试没抓到它，因为没有任何一例填过 `candidate_ids`——没走过的输入路径等于没有测试。
5. **会让触发器静默失真的解析必须响，不该只写在 docstring 里**。活跃区 Entry 数原先只按
   `## 冷却区` 切分，标题一旦改名，cooling/retired 会全数算进活跃区、`frontier_change` 虚高；
   现在两个小节标记缺一即 `GateError`。同理 `structural_churn` 的代码路径改为显式常量
   `CHURN_CODE_PREFIXES = (lib/, test/)`：原先硬编码 `lib/` 会漏掉 `test/`，
   但**不能**从 workset 取并集——那会把 `.github/`、`tools/` 的配置改动也算成代码结构抖动。

**周预算维度暂未生效**：`budget.*.spent_this_week / cap_this_week` 由信号透传，真实探针目前
返回空 budget（恒 `null`，契约允许）。周上限要等 P0-2 账本提供逐夜成本行才能算。

**日上限同样不生效**（2026-10-03 评审更正，此前的说法是错的）：夜间管道从来没用
`append-gate --llm-cost` 传成本，账本里没有任何成本行 → `spent_today` 恒 0 → `exhausted`
永不成立 → 预算这条"独立于工作量的否决路径"端到端是惰性的。这不是接线遗漏可以悄悄略过的
程度问题：影子期读数如果被解读成"预算够用"，P0-1b 的激活判定就建在一个不存在的约束上。
现在 `budget.enforced`（布尔）与 `budget.note="cost_not_recorded…"` 进入 gate-result，
投影里对应 `ledger-metrics.json: budget_caps_enforced=false`。成本落账归 P0-3。

6. **契约描述就是验收标准，代码与它不符即为 bug**。`gate-result.schema.json` 里写的是
   `frontier_change = ledger 有 open candidate 且其 target 路径出现在近期 diff`，首版只实现了前半个合取
   （数 Entry 条数）。仓库现状恰好有一条长期 blocked 的 FR-001，于是 maintenance 通道**夜夜必开**，
   影子期"哪些夜晚本可跳过"的读数系统性偏高——这类错误不会让 CI 变红，只会让结论变错。
   现改为解析活跃区 Entry 的 `next_action: target:` 路径并与 diff 求交（同文件或同目录兄弟文件），
   Entry 条数降级为读数 `open_candidate_count`，不再单独构成触发条件。
7. **有账本不该比没账本更保守**。`days_since_last_exploration` 缺失而 `last_exploration_date` 存在时，
   原实现的两个槽位分支都进不去 → 每周探索被静默关闭；而这正是 P0-2 只提供日期的形状。
   现由日期推算天数，推算不出（日期不可解析）直接 `GateError`，不做"当没数据"的静默降级。
8. **判定阶段的错误走同一条响亮失败路径**。`evaluate()` / `emit()` 原先在 `main()` 的 try 之外，
   任何 `GateError` 会变成裸 traceback。现已收进同一个 try，退出码 1 且 `[FAIL]` 可读。
9. **闸门不能吃自己的排泄物**。"上次审查"用日期窗口取 diff 时，审查提交本身就落在那一天，
   而 P0-2 之后账本三件套每晚必然往 main 提交一次 → `commits_since_last_audit` 恒非空 →
   `changed_code` 夜夜必开 → `eligible` 恒为 true。这是第 6 条同一个根因的更严重版本：第 6 条
   修的是"数 Entry 条数"，这条是"把上一夜的输出当成本夜 inputs"。现在窗口改为
   `<audit sha>..origin/main` 的精确 rev-range，并按 `AGENT_OWNED_PREFIXES`
   （`docs/agent-audit/`、`docs/agent-investigations/`）剔除自产物；被剔除的提交数以
   `self_referential_commits_excluded` 留在读数里，剔除本身可审计。
   讽刺的是影子期无法用影子读数发现这条——一个恒为 true 的布尔值，离线复算也造不出一个
   "可跳过"的夜晚，而日历时间花掉就没了。

**陈旧度与候选队列已接上账本**（P0-2 收尾，此前"已知未接"）：`ledger.py state` 产
`dimension_state` / `probed_dimensions` / `days_since_last_exploration`，闸门用
`--state-file` 消费。这条交接现在是**契约**而不是约定：键名与 `schema_version` 由
`ledger.STATE_REQUIRED_KEYS` 单侧声明、闸门侧强制校验，缺键或形状不对一律 `GateError`
（以前是 `.get()` 到底，schema 漂移会安静退化成"今晚没有陈旧维度"——把"读不到账本"
记成"确实没有陈旧"，正是本闸门要避免的调试方式）。`eligibility_gate_test` 里有一条
真跑 `cmd_state` 再喂闸门的 round-trip 用例，两边任何一侧改键名都会撞墙。

阈值仍未校准：`EXPLORATION_SLOT_DAYS=7`、
`DIMENSION_STALE_DAYS=21`、`STRUCTURAL_CHURN_LINES=800`）**未校准**，
2026-10-03 实跑产品代码 7 天增行 1141 已越过 800。

对这条阈值的处置是**有意不动它**：把它调到 2000 是拿一个猜测替换另一个猜测。且现在是影子模式，
过度触发的代价只是读数噪声而非真实成本——每夜的 reasons 全量进 artifact，
"这周若按此阈值会跳过几夜"可以离线从同一份数据算出来。必须修的是语义不符（上面第 6 条），
不是阈值偏松。两条随之而来的已知偏差记在这里，供校准解读：

- `structural_churn` 是 **7 天滚动累计**，一旦越线会连响数夜，不代表当晚有新抖动；
- 影子期第一周**只读数、不调阈值**，任何阈值改动必须在 PR 里引用影子读数本身。

---

### 3.10 已落地：P0-2 Canonical Ledger + 只读投影

| 件 | 位置 |
|----|------|
| 账本写入者（唯一入口） | `.github/scripts/tafcm-maintainer/ledger.py`：`append` / `append-gate` / `import-audit` / `import-findings` / `state` / `project` / `reconcile` |
| 账本（canonical） | `docs/agent-audit/ledger.ndjson`（append-only NDJSON；2026-10-03 评审后**重生成 bootstrap**：注册表 31 条 + 1 条 audit finding = 32 事件，不再有手写 gate 行） |
| 只读投影 | `docs/agent-audit/LEDGER.md`（人读）、`ledger-metrics.json`（指标） |
| 不变量测试 | `ledger_test.py`（44 例）+ `eligibility_gate_test.py`（44 例，含 state→gate round-trip） |
| 接线 | `tafcm-maintainer.yml` §3.6 步骤组 + `Guard — ledger is append-only`；`ci.yml` 跑测试 + `project --check` + `reconcile` |

机器强制的不变量（每条都有对应用例，不是文档承诺）：

1. **身份与时刻由脚本拥有，申报即拒写**：ledger 复用 `fingerprint.py` 的
   `SHA-256(category|files|norm_summary)[:16]`。`event_id` / `ts` / `hypothesis_id` /
   `hypothesis.created_by_run` 上游给了就**拒写**（不是覆盖——覆盖等于让调用方以为自己的
   值生效，下次它就不来看这份账本了）。`actor=importer` 有一条窄例外：历史行沿用注册表
   已申报的身份，仅对 `run_id` 以 `import-` 开放，**代价写进账本本身** ——
   `identity_source=registry_declared`，投影与 `reconcile` 按这个前提说话。
   评审实测：注册表里有 8 个 `latest_id` 各挂两个 fingerprint（含 `a1b2c3d4e5f60001`
   这类手填占位），说明 `latest_id` 从来不是身份。账本如实记录并计数
   （`registry_label_collisions`），**不替它合并**——那可能是两个真不同的 Finding
   被起了同一个名字。
2. **自证阻断**：`tier_promoted` / `verdict(verified)` / `published` 只能由 verifier 及以上
   角色写，且 `run_id` 必须不同于该假设的 `created_by_run`；scout/investigator 写 promote → 拒写。
   `importer` 也被移出签字方（本 PR 前它在 `PROMOTION_ACTORS` 里，等于给自证开了一条既带
   fingerprint 申报权、又带批准权的通道）。账本里没有该假设的 `hypothesis_added` 也不许签字，
   否则 `metrics.verified` 会被一个拼错的 id 涨上去。
3. **append-only + 损坏即停 + 重放可识别**：只追加；已有行 JSON 损坏或非 UTF-8 时**拒绝续写**，
   不"顺手重建"；`event_id` 改为内容寻址（掺时钟的行既不能被人重算核对，也识别不出重放），
   同一行重复写入直接跳过。夜间管道里的 `Guard — ledger is append-only` 用 diff 检查
   "无删除/改写行"——此前"只有确定性步骤能写账本"只是注释，而 Guard 按目录前缀放行
   `docs/agent-audit/`，Cline 本来就能直接改这个文件。
4. **单条 KB 硬顶 32KB**：按**落盘字节**算（按去掉字段的估算算会漏掉转义与 id 开销，
   实测能写出 32,787 字节的行）。
5. **去重只对未闭合身份**：同 fingerprint 有开放假设 → 记 `duplicate_of` 复用原编号；
   `retired` / `verified` 会从开放映射里**摘除**（只"不再覆盖"不够：同一个 bug 复发会被挂到
   一个退役假设上，永远进不了候选队列）。`retired` 事件按契约不许自带 fingerprint，
   闭合靠已有的 id→fingerprint 映射回填。
6. **导入幂等**：`import-findings` 跑两次不会多一份状态。
7. **降级与阻断可见**：散文 audit 的 Finding 一律 `evidence_tier=L1`，`P0/P1` 触到 L1 天花板
   被降为 `medium`，原值留在 `severity_declared`；`L2` 且 `invariant_source.kind=self_authored`
   在写入步骤直接拒（契约把这句叫"机械阻断点"，那它就不能只存在于契约文字里）。
8. **每次 run 必留 gate 行**（`gate_eligible` / `gate_no_work` / `gate_skipped_run`），
   否则 `gate_skip_rate` 没有分母；闸门步骤自己失败时写 `gate_step_failed` 而不是静默跳过。
   读数口径修正：`gate_step_failed` 的夜晚**既不进分子也不进分母**（单列 `gate_unavailable`）——
   把它们算成"合法跳过"会让坏掉的闸门看起来很有用。`Commit Audit` 因此改成
   `if: always() && steps.guard.outcome == 'success'`，audit 解析失败的夜晚闸门行仍要落账。
   **失败夜的既定行为**（写清楚，免得下次当成 bug）：`import-audit` 读不到当晚 audit 文件
   会 `OSError → exit 1`（缺文件=事故，不静默跳过），该夜 Finding 不进账本、job 判红；
   `append-gate` / `project` / 两个 Guard 都带 `always()`，所以闸门行仍被提交。
   **漏掉的夜晚不会自动补**：workflow 每晚只传当天的文件名，补录要人工跑
   `ledger.py import-audit --audit docs/agent-audit/<漏的那晚>-maintainer-audit.md`
   （按 fingerprint 去重，重复导入不会多一份）。自动补扫未导入的 audit 文件记在 P0-2b。
9. **投影必须可复现**：`LEDGER.md` 正文不含生成时间（带时间戳 = 每晚都把没变的账本改脏，
   而且 CI 永远没法判"投影与账本一致"）。新增 `project --check`，已挂进 `ci.yml`：
   手改投影、或写了账本没重生成投影，PR 直接红。这是 #289 那条红线的机器版本。
10. **一把日历**：夜间管道统一 `RUN_DATE="$(date -u +%Y-%m-%d)"` 传给 `state` / 闸门 /
    `import-audit --observed-date`。cron `17:23Z` 恰好落在 CST 次日 01:23，audit 文件名沿用
    CST，两套日历混在一个 `last_observed` 字段里会让 21 天阈值系统性少算一天，同日夜重跑
    还会算出负数天数（探索被永久抑制）。

**P0-2 未解决、留给 P0-2b/P0-3 的**（现在写下，别等校准数据里才发现）：

- 账本只增不减：目前没有任何写入者会产出 `retired` / `verified`，`open_severity` 是对历史的
  max、`candidate_ids` 永不收缩 → 调度器的 risk 输入会朝"最老的导入说了算"固化；
- 成本未落账 → 预算上限惰性（见 §3.9）；
- 注册表 `FINDINGS.md` 与账本仍两套状态并存，靠 `reconcile` 守着；`import-findings` 的
  身份是"申报来的"而不是"算出来的"，注册表里没有存 Summary 原文，重算所需输入根本不在那一行；
- `frontier_open_candidates` 已由 `state` 产出但闸门仍解析 `FRONTIER.md`，两个 frontier 概念
  并存到 P0-2b；
- 漏掉的一夜不会自动补录：`import-audit` 只读当天文件名，audit 生成后、导入前挂掉的窗口
  需要人工补跑或加自动补扫（P0-2b）。

两条由真实数据（不是 fixture）逼出的修正：

- **回填不得清零陈旧度**。首版 `state` 用事件 `updated_ts` 算"最近探测时间"，导入 31 条历史后
  所有维度都变成"今天刚查过"，探索通道会安静 21 天。改为 `hypothesis.last_observed`
  （注册表的 `last_seen` / audit 文件名日期），并已把该字段加进 schema + 契约校验断言。
- **`by_bucket` 暴露导入行归属**：历史导入记 `meta`，实时活动记 maintenance/exploration，
  两者混算会让成本指标失真，投影里分开显示。

**已知限制（诚实登记）**：`category → dimension` 是查表映射（`tech-debt` 目前落到 `infra_ci`），
所以"某维度在账本里没有行"**不等于**"该维度从未被探测"。因此 `never_probed` 只能显式记录，
不由缺席推断——这正是 §3.9 规则 1 的延伸。落地形态：`ledger.py state` 报
`probed_dimensions`（闸门行分配过的维度 + 有假设的维度），判定与打分**共用同一个读取函数**
`_never_probed()`。首版打分路径（`_staleness` / `assign_dimension`）还在读每维度
`d_state["never_probed"]`——账本从不产这个字段，于是"从未探测"档在 Top-N 里永不成立，
最该补覆盖的维度反而排在已探测的后面；2026-10-04 修掉，配 `ScoringSourceTest` 两例。
同轮评审又指出 `_staleness` / `_is_stale` 里留着 `or d_state.get("never_probed")`：三个调用点
都已把结论算成参数传进来，那个分支永远为假，是死代码——删掉，读路只留一条（全仓 grep 确认
无人产、无人测该字段后才动）。

---

### 3.11 夜间管道连续失败的归因（2026-10-04 实测）

现象：`schedule` run 2026-10-01 / 10-02 / 10-03 连续三夜 `completed/failure`，账本里
`gate_evaluations` 仍是 0 —— **影子期指标的分母不是"还差点数据"，是断的**。

日志证据（`gh run view 37149937938 --log-failed`）：

```text
error: You’ve reached the API rate limit for free users. Upgrade to a Token Plan …
ALL_CHAIN_FAILED: 降级链耗尽或封顶，最后类别见上方 FALLBACK 行
```

根因是两层，不是一层：

1. **provider 侧**：AGNES 免费配额耗尽（与 2026-10-02 那次定性相同）。
2. **结构侧（真正的放大器）**：`.agent/tafcm-maintainer/models.json` 里 `providers` 只有
   `agnes` 一个、`chain` 只有**一个节点**。所以 `onError: rate_limit → next` 在单节点链上
   等价于"同一模型、同一配额池连撞 `maxAttemptsPerRun=3` 次然后失败"——**这不是降级链，
   是重试**。配额是账户级的，重试烧穿的还是同一个池子。

修法（按代价排序；第 1 条只能由 Human Owner 做，因为只有你能建 Secret）：

1. 往 `providers` + `chain` 加**第二个独立配额池的 provider**，并在 workflow 显式加一行
   `env`（Actions 不支持按名动态引用 secrets；这个摩擦是 #310 里确认过的故意设计）。
   加完之后"降级"这个词才成立。
2. `rate_limit` / `timeout` 是分钟到小时级窗口，立刻连打三次必然全撞同一窗口：应改成
   **同模型退避重试一次再降级**（即 P1-5 里那条"transient 先同模型重试"）。
3. 已完成：`Report status` 不再只看邮件 outcome 就打印 `Audit = SUCCESS`。那句措辞正是
   三夜失败被读成"只是邮件挂了"的原因。现在 SUCCESS 要求两件事同时成立——本夜 Cline 跑成
   **且** audit 文件在；三种失败分开说：`FAILED (Cline 执行失败)`（跑了但崩，指向供给层）、
   `FAILED (Cline 未运行: outcome=skipped/cancelled)`（上游步骤断了 job，Cline 压根没跑，
   此时工作树里可能还有当天早先一次成功运行的 audit，只看文件会重新掩盖失败）、
   `FAILED (无 audit 文件)`（跑成了但没产物）。第二种是三轮评审指出 `outcome` 对 skipped
   步骤返回 `skipped` 而非 `success` 后补的——归因错了，排查方向就会被引向模型配额。

**别把这条读成"闸门没用"**：闸门排在这些步骤之前，但失败发生在模型供给层，控制面本身
没问题；恰恰是 §3.10 那条红线（LLM 写权限与供给解耦）还没做完的部分在疼。

---

## 第四部分 治理红线（机器强制优先于协议约定）

1. Agent **不 merge PR、不 push main**（AGENTS.md §6.4）；写操作由 Actions 代执行。
2. **任何 LLM job 零 GitHub 写权**：Scout 与 Investigator 都不得持有 `gh issue create`；
   Issue 只由无 LLM 的 Publisher 段按 `publisher_action` 创建（比上一版"Scout 无、Investigator 有"更严）。
3. **tier 提升与 `verified` 只能由 Verifier 段触发**；`created_by_run == verifier run` → `tier_run_separation` fail。
4. **独立性按证据来源类型判定，不按 run 数量判定**；`invariant_source.kind = self_authored` 封顶在 L1。
5. **Agent-authored 复现代码只在零写权、无写用途 Secret 的独立 job 内执行**，
   不得在持 `contents:write` 的 maintainer job 里跑（新增 CI 任意代码执行面必须显式承认并隔离）。
6. 配置文件中**永不出现密钥值**，只出现 Secret 名字；新增供应商必须新增一行显式 workflow env（人工评审位）。
7. Agent 无账本写权限；账本由确定性步骤写；投影只读。
8. 每个写步骤有 KB 硬顶 + 写前校验（防 #289 类自毁）。
9. 错误分层不得压扁：provider 错 / agent 错 / 基建错在账本里是三种行，不得都表现为 workflow 红。
10. L0/L1 不得自动产生 Issue；`NO_FINDING` / `NO_WORK` 是合法终态，不需要被"优化"掉。
11. `severity` 受 tier 天花板约束，由写入步骤强制降级；模型可标注，但数值不得越过脚本上限。

---

## 第五部分 落地顺序

**接口先行**：P0-0 已随本文完成（三份 schema 定稿）。P0 之后再写 Scout / Investigator prompt，
避免 prompt 反过来塑造接口。

| 阶段 | 内容 | 量级 |
|------|------|------|
| **P0-0** | **三份接口契约定稿**（ledger-event / gate-result / verdict）+ 跨文件一致性校验脚本 + CI job `agent-control-plane-contracts` | ✅ 已合入 main（PR #311） |
| P0-1 | **双路 Eligibility Gate + Dimension Scheduler**（零 token，输出 `gate-result.json`；两通道分别记预算）——**影子模式已上线，尚未接管激活** | ✅ 本 PR（详见 §3.9） |
| P0-1b | 接管激活：`eligible=false` 时不起 Cline，改写一行 NO_WORK 终态。**前置条件**：影子期攒到 `gate_skip_rate` 与误判样本、阈值完成校准、账本提供真实陈旧度 | 待影子数据 |
| P0-2 | **Canonical Ledger**（append-only NDJSON + KB 硬顶 + 写前校验 + promote 作者分离 + 只读投影） | ✅ 本 PR（详见 §3.10） |
| P0-2b | 投影收编：`FRONTIER.md` 由账本生成；`FINDINGS.md` 的写入者从 `fingerprint.py` 换成账本投影。**过渡期靠 `reconcile` 守漂移**，两套状态并存不是终态 | 1 天 |
| P0-3 | noop 终态契约；**删除** `ensure_daily_audit.py`；PROMPT 增加强制 `INCOMPLETE` 出口 | <0.5 天 |
| P1-4 | 错误分层语义 + 凭据/工具 preflight 烟测；#310 onError 增加 transient 先重试 + 降级粘住 N 小时 | <1 天 |
| P1-5 | 四段管道接线（Scout / Top-N / Investigator / Verifier+Publisher），复用管道 A 的 extract→analyze→create 骨架与 GH_MOCK fixtures 手法 | 1-2 天 |
| P1-6 | **Deterministic Verifier 实现**：干净 checkout 重跑复现物 + `invariant_provenance` git 校验 + 零写权沙箱 job | 1-2 天 |
| P2-7 | 2 个 investigation protocol（Performance / Correctness）+ Top-N 确定性打分实现 | 1-2 天 |
| P2-8 | 双预算账本与成本计量；影子 A/B 记账 | 1 天 |

**移植优先于新建**：管道 A（ADR-0025）已实现的 schema 校验、执行器边界二次复校、脚本化 fingerprint、
三态门禁、白名单收口、干跑与 GH_MOCK fixtures，全部是管道 B 缺的东西，直接搬。
**不再发明新机制**：本设计用到的每个部件在仓库里都有先例——`decision()` 的门禁、`FRONTIER` 的状态机、
`SUPERVISOR` 的独立验证层、#310 的 provider recovery；缺的是把它们接成一条控制链。

---

## 第六部分 未决问题

1. `issue-triage` 的 history 是 artifact（90d 归零，Phase C 计划落库）；它与 Canonical Ledger 是
   **合并成一个账本还是两个**？合并前不得新建第三套状态。
2. 管道 A 的 analyze 走 `anthropics/claude-code-action` + MiniMax 代理，Secret 名为 `DEEPSEEK_API_KEY`
   ——**Secret 命名与实际供应商已漂移**。是否统一并入 `models.json` 供给层（#310 目前只覆盖 Cline 侧两处调用）。
3. Investigator / Verifier 的调度频率与 Top-N 取值未定（候选：每周 1 次 N=3）。
4. Experiment 成本上限：单次 Investigator 允许 `flutter build` / 真机集成吗？若允许，预算单位不再是 token，
   而是 runner-minutes（`budget.unit` 已预留该枚举）。
5. `clean_checkout_rerun` 用什么 runner / timeout / 缓存策略；Agent-authored 复现物的保留期。
6. `docs/agent-supervision/` 的 5 份人工监督报告与新四段管道的边界（哪些维度仍归人，尤其真机验证）。
7. 三份 schema 的 CI 校验位置：**已并入 `ci.yml` job `agent-control-plane-contracts`**。
   待定的是下一步 Verifier 实现用同一 job 追加 fixture 测试，还是新开 `agent-verifier` job。
8. **阈值校准与接管判据**（P0-1b 的入口条件）：`EXPLORATION_SLOT_DAYS` / `DIMENSION_STALE_DAYS` /
   `structural_churn` 行数阈值目前是先验值，2026-10-03 实跑即触发 churn（1141 > 800），说明偏低。
   需要影子期回答两个问题：真实夜晚里 maintenance-only 判定的 precision 是多少？
   连续几夜 NO_WORK 会不会漏掉后来被证明有价值的发现？在拿到这两条之前不接管激活。
