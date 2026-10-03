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
| **P0-0** | **三份接口契约定稿**（ledger-event / gate-result / verdict）+ 跨文件一致性校验脚本 + CI job `agent-control-plane-contracts` | ✅ 本 PR |
| P0-1 | **双路** Eligibility Gate + Dimension Scheduler（零 token，输出 `gate-result.json`），`if: eligible` 才起 LLM；两通道分别记预算 | <0.5 天 |
| P0-2 | Canonical Ledger（append-only NDJSON）+ `FRONTIER.md`/`FINDINGS.md`/Dashboard 降为投影；KB 硬顶 + 写前校验；tier/promote 作者分离 | <1 天 |
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
