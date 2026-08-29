# ADR-0025：Issue 自动挖掘与分类 Agent 架构

> **状态**：Proposed（随本 ADR 提交，Human Owner 签字即 Accepted）
> **版本**：v1.0
> **作者**：AI 协作开发者（基于 Human Owner 契约评审意见）
> **关联**：`docs/decisions/ADR/0024-agent-diagnostic-interface.md`（ADI）· `.github/workflows/claude-review.yml`（四级审查基线）· `.github/pull_request_template.md`

---

## 背景（Context)

已存在 PR 自动代码审查（`claude-review.yml`：四级审查 + `anthropics/claude-code-action@v1` + minimaxi 代理端点 + `deepseek-v4-flash`）。审查过程会在 PR 上产生未解决评论，但这些**有效工程信号没有落库**，无法被追踪、排期、指派。本 ADR 引入一个从 **PR 未解决评论** 与 **分支 Git log** 自动挖掘并分类 Issue 的 Agent CI 工作流。

**核心约束（来自 Human Owner 评审）**：仓库为 **PUBLIC**，PR 来源不可信 → 输入源与执行权限**不得处于同一信任域**。Claude 必须被定位为 **不可信分析器（Untrusted Analyzer）**，而不是拥有仓库操作权的执行 Agent。系统采用三段式：

```
GitHub Event
   │
   ▼
┌────────────────────────┐   Deterministic Extractor（fetch_input.sh）
│ 信息提取：PR 评论 / Git │   规范化输入，== 输出 context.md ==
│ log → 规范化上下文       │
└────────────────────────┘
   │
   ▼
┌────────────────────────┐   AI Reasoning Layer（Claude Code Action）
│ 智能分析：分类 + 摘要    │   无任何写权限 ← 只读 + 写 findings.json
│ → 结构化 findings.json │
└────────────────────────┘
   │
   ▼
┌────────────────────────┐   Deterministic Executor（create_issues.sh）
│ 生成 Issue：校验 + 去重  │   validate + sanitize + gh API
│ + 置信度三态 + 建标签    │
└────────────────────────┘
   │
   ▼
       GitHub Issue / PR 建议评论
```

> **设计红线**：AI 提供判断，系统掌握权力。Claude 的任何输出都是「建议」，由确定性脚本按契约校验后才可能落地为 GitHub 副作用；杜绝 prompt injection 把「LLM 输出错误」放大为「仓库授权滥用」。

---

## 决策（Decision）

### D1. 三段式信任边界（Untrusted Analyzer 模型）

| 阶段 | 组件 | 读权限 | 写权限 | 信任等级 |
|---|---|---|---|---|
| 1. 提取 | `fetch_input.sh` | contents | `.tmp/` 内文件 | 可信（确定性脚本） |
| 2. 分析 | `claude-code-action@v1` | contents、`.tmp/` 内输入 | **仅 `findings.json`** | 不可信（LLM） |
| 3. 执行 | `create_issues.sh` | `.tmp/` 内 findings | issues / pull-requests API | 可信（确定性脚本，对 findings 做白名单校验） |

- Claude 的 `--allowedTools` 仅放行：`Read`、`Glob`、`Grep`、`Write`（限 `findings.json`）。**禁止** `gh`、`Bash` 写命令、GitHub 写 API。
- 禁止直接把 GitHub 原始 payload 喂给 Claude —— 必须先经 `fetch_input.sh` 规范化为 `context.md`（见 D2）。

### D2. 输入契约（`context.md` schema，强制）

`fetch_input.sh` 输出固定格式 `context.md`，Claude 只消费此文件：

```markdown
# Source
type: <pull_request_review | pull_request_review_comment | branch_scan>
repository: <owner/repo>
pr: <number | null>
base: <branch>
branch: <branch | null>
fetched_at: <ISO8601>

---

# PR Metadata（type 含 pr 时）

title: <PR title>
created_by: <login>
changed_files: <int>
commits: <int>
base_ref: <branch>
head_ref: <branch>

---

# Unresolved Review Threads（仅 isResolved=false；isOutdated 打 `[OUTDATED]`）

## Thread 1
author: <login>
status: unresolved[|OUTDATED]
file: <path>
line: <int | null>
comment: <body，截断至 800 字符>

---

# PR Comments / Review Comments（线程外）

## Comment 1
author: <login>
body: <body，截断至 800 字符>

---

# Git Log（type 含 branch 或合并信号）
```

- **所有字段必须 top-level 键值对齐，禁止自由 schema。**
- **业务规则**：提取阶段只捞 `isResolved == false` 的线程（天然过滤已解决讨论）；`isOutdated` 线程保留但强制打标，供 Claude 降权。
- **解耦**：schema 变更是契约变更，必须走 ADR 修订；脚本改动不得静默改 schema。

### D3. 分类契约（Taxonomy）

Claude 输出 `category` 仅限以下**可行动类别**（create 阶段会据类别兜底打标签）：

```
bug            → 确定会引发错误行为/异常/崩溃
security       → 权限、鉴权、敏感数据、注入、凭证等（优先级独立于 severity）
performance    → 延迟/吞吐/资源占用
tech-debt      → 需重构/清理的既有实现债务（TODO/FIXME/死代码/重复逻辑）
refactor       → 结构性重构建议（可独立为任务）
feature-request→ 缺失的必要功能
documentation  → 文档缺失/错误
```

以下类别供 Claude **内部筛除**，**禁止**据此自动建 Issue：`invalid`（误报/无效）、`duplicate`（去重由 D6 处理，模型不得自行建重复）。分类标注 `security` 时强制要求 `severity` 至少 `medium`，`confidence` 按 D5 上浮一档，避免安全问题被误判为低优先 improvement。

### D4. 标签与 Mentions 契约

- **标签白名单**（create 阶段只允许这些）：
  - 直接映射：`bug` `security` `performance` `tech-debt` `refactor` `enhancement`(feat) `documentation`
  - 缺失标签由 `create_issues.sh` 自动 `gh label create` 补齐（当前仓库缺 `security` `performance` `tech-debt` `refactor`）。
- **Mention 白名单**：Claude 输出的 `mentions` 仅为**候选**；create 阶段按 `仓库 contributors ∪ {核心开发者}` 过滤，不在白名单的一律丢弃。仓库活跃开发者经 `git shortlog` 维护（当前核心：`Thy985` / 唐怀远）。
- 正式 Issue 上 @ 通过正文末尾 `CC: @login` 追加（已过滤），避免任意注入 @ 陌生人。

### D5. 置信度三态决策（Confidence Policy）

错误成本不对称：**少建一个 Issue 成本低，多建一个垃圾 Issue 污染仓库**。据此：

| confidence | 决策 | 落地动作 |
|---|---|---|
| `>= 0.8` | **High → 自动创建** | `gh issue create` |
| `[0.5, 0.8)` | **Medium → 建议** | 仅当有 PR 上下文时，在 PR 回帖生成「建议 Issue」清单（含全文）；无 PR 时并入 summary 报告 |
| `< 0.5` | **Low → 丢弃** | 仅记录进 summary，不落任何 GitHub 副作用 |

- 阈值通过 workflow input / repository variable（`ISSUE_TRIAGE_HIGH_THRESHOLD`、`ISSUE_TRIAGE_MEDIUM_THRESHOLD`）可调，默认 `0.8` / `0.5`。
- **首版上线建议 `dry_run=true`**：逐条人工校准阈值后再放开自动创建，防止「Claude 分类很好但 Issue 污染仓库」的不可逆后果。

### D6. 去重契约（Deterministic Dedup）

- **fingerprint（结构指纹，由执行器计算）**：`create_issues.sh` 对每条 finding 计算 `sha256(category-component-root_cause)[:16]`。
  ⚠️ **契约对齐说明（D2/HIGH）**：本实现为**结构指纹**而非 ADR 早期描述的「Claude 输出的语义 kebab-case 指纹」。结构指纹仅能识别完全相同的 `category+component+root_cause` 三元组；**无法**识别「Authentication timeout after idle」与「Login timeout on idle session」这类同义异写的语义重复。语义层去重由 D6 步骤 2（标题近似匹配）兜底，但仍非严格语义等价。
- **状态存储（Phase B 临时方案）**：去重记忆以 workflow artifact（`issue-triage-history`，retention=90d）在 run 间传递，**不**落库到仓库。90 天后 artifact 过期，旧 fingerprint 视为新发现，可能重复建 Issue（见 C5/A5 风险）。
- **状态存储（Phase C 目标）**：升级为仓库内 `.issue-triage/history.json` 落库（commit-bot 写入，不入 `.gitignore`），作为长期记忆；其与仓库的写入走独立 PR/直接更新语义（见 D8 治理）。
- **去重判定（先结构后标题）**：
  1. `history` 中已存在相同 `fingerprint` → 跳过（记录 `duplicate-of`）。
  2. `gh issue list --search "in:title ..."` 命中已开 Issue 标题相似 → 跳过。
  3. 两者都未命中才允许创建。
- **跨 run 缺口（C5/A5）**：Phase B 下 artifact 过期后跨 run 去重失效，需 Phase C 落库后方可彻底解决。

### D7. 权限与 Job 拆分（Permission Boundary）

将工作流拆为两个 job，物理隔离写权限：

```
job: analyze（只读）
  permissions: contents: read · pull-requests: read
    1. fetch_input.sh            → context.md
    2. claude-code-action (只读)  → findings.json
    3. upload-artifact: findings.json
        │
        ▼
job: create（写）
  needs: analyze
  permissions: issues: write · pull-requests: write
    1. download-artifact: findings.json
    2. create_issues.sh（validate/dedupe/create）
    3. 如有 medium 建议 / 生成报告 → gh pr comment
```

- `analyze` job 无任何写权限（连 `issues: write` 与 `pull-requests: write` 都没有）——即使 LLM 被注入，也没有可借用的写令牌。
- `create` job 的写权限由确定性脚本独占消费，且脚本内置白名单校验（D3/D4/D5/D6），是第二道闸。
- `create` job 需要 `pull-requests: write` 仅用于回帖建议清单（幂等、非破坏）。

### D8. 治理（Governance）——本 ADR 属于 Human-Owner 文件

- `docs/decisions/ADR/*`、`docs/architecture/ARCHITECTURE.md` 等为本仓库 Human-Owner 专属文件，AI 仅在 Human Owner 明确授权（本次为显式评审授权）下可提交，必须走独立分支 + PR，**永不经自 merged**。
- `.issue-triage/history.json` 的累积写入由 create job 执行（确定性脚本），属系统运行时状态而非 AI 业务改动；其提交策略由 Human Owner 在首次落地时裁决。

### D9. 分类触发与并发

- 触发：`pull_request_review`(submitted)、`pull_request_review_comment`(created)、`workflow_dispatch`（手动，含 `source=pr|branch`、`pr_number`、`target_branch`、`base_branch`、`dry_run`）、可选 `schedule`（周更扫描分支 tech-debt）。
- **concurrency 按 source 分组**：`group: issue-triage-${pr_number || ref}-${event_name}`，避免 PR 扫描与 main 分支扫描互相 cancel。

---

## 被否决方案

| 方案 | 否决理由 |
|---|---|
| 让 Claude 直接 `gh issue create / edit / api` | 输入源（PR 评论）与执行权限同信任域；公开仓库下 prompt injection 直接放大为授权滥用 |
| 把 GitHub 原始 payload 直接喂给 Claude | schema 不稳定，GIGO；无法做字段级截断/降权（如 OUTDATED 标记） |
| 固定单阈值 `confidence >= 0.6` | 未区分错误成本；会同时漏建高价值与放行低价值 Issue |
| 仅靠标题精确去重 | 无法识别「Fix login timeout」与「Authentication timeout after idle」同一问题 |
| 单 job 持全量写权限（contents/pulls/issues write） | AI 阶段即持写权限，违背「Untrusted Analyzer」边界 |

---

## 后果与影响（Consequences）

- **正面**：有效工程信号落库可追踪；安全边界清晰（AI 无写权）；去重与置信度策略可人工校准，降低仓库被垃圾 Issue 污染风险；复用 claude-review 的模型路由（minimaxi + `deepseek-v4-flash`）。
- **负面/成本**：需实现 `fetch_input.sh`（GraphQL 未解决线程提取 + git log 规范化）与 `create_issues.sh`（schema 校验 + 三态 + 去重 + 建标签 + 建 Issue）；首次需 `dry_run` 校准阈值；多一个 job 的 artifact 传递复杂度。
- **守门**：
  - 输入/输出 schema 单测（fixture 驱动，见「测试要求」）。
  - 权限契约由 GitHub job 级 `permissions` 强制，任何把写权限上移到 `analyze` job 的改动必须交叉评审。
  - 分类 taxonomy 变更必须经 ADR 修订，严禁脚本内静默新增类别。

---

## 测试要求

- **本地 fixture 测试**：`fetch_input.sh` 与 `create_issues.sh` 用固定 fixture（构造 `context.md` / `findings.json`）跑通：
  - 提取：构造含 resolved/unresolved/outdated 线程 → 断言仅未解决进 `context.md`，outdated 带标记。
  - 创建：三态置信度样例 → High 建 / Medium 仅建议 / Low 丢弃；重复 fingerprint → 跳过；越权 mention/label → 被过滤。
- **dry-run 预演**：先以 `dry_run=true` 在真实 PR 上跑数轮，人工核对分类与置信度分布。
- **CI 守门候选**：架构测试校验 `issue-triage.yml` 的 `analyze` job 声明不含任何 `...: write` 权限。

---

## 实现分期

- **Phase A（契约落地）**：本 ADR + `docs/spec/issue-triage-agent.md`（规范载体）。
- **Phase B（实现）**：`fetch_input.sh` → local fixture test → Claude dry-run → `create_issues.sh` dry-run → 接入 `.github/workflows/issue-triage.yml`。
- **Phase C（上线）**：Human Owner 批准后，`dry_run=false` + `history.json` 落库 + 告警/失败处理收敛。

---

## 审批

- [ ] Human Owner 签字（Accepted）
- [ ] 关联 PR：`feat/issue-triage-workflow-clean`（PR #139，含本 ADR + 实现脚本 + 工作流）
- <short_sha> <author>: <subject>
  <body 首 200 字符>

> **G1 合规说明**：本 ADR 属 Human-Owner 专属文件（AGENTS.md §6.4）。AI 协作开发者**不代签**；须经独立 Human Owner 勾选上方「签字」框并合并后方可置为 Accepted。状态由 `Proposed` 改为 `Accepted`。