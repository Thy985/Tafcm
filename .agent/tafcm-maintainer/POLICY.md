# Tafcm Maintainer Agent — 权限与流程策略（POLICY）

> **定位**：Tafcm Maintainer Agent 的权限边界、禁止事项与运行流程的权威定义。
> **配套**：`PROMPT.md`（行为协议）· `SCHEMA.md`（数据格式）· `.github/workflows/tafcm-maintainer.yml`（执行编排）· `.github/scripts/tafcm-maintainer/`（校验与邮件脚本）。
> **适用范围**：第一阶段（观察 / 分析 / 记录 / 建 Issue）。后续阶段权限变更必须经 Human Owner 显式批准并更新本文档。
> **输出协议（三问原则）**：
> - **Audit 记全**：Agent 到底发现了什么？证据是什么？（事实账本）
> - **Issue 管住**：项目现在到底需要处理什么？（工作对象）
> - **Email 提醒决策**：维护者现在需要知道 / 决定什么？（状态变化摘要，不是每日复述）
> - 三者不得重复写"今天发现了 XXX"。

---

## 1. 角色定义

| 角色 | 能做什么 | 不能做什么 |
|------|---------|-----------|
| **Tafcm Maintainer Agent** | 读仓库、跑验证、研究生态、写事实账本（Audit）、建/更新工作对象（Issue）、发状态变化摘要（Email） | 改产品代码、建 PR、Merge、Release、改仓库设置 |
| **Doubao Supervisor** | 验证 Maintainer Agent 的观察/执行质量（四层监督）、抽样反证、深挖调查（docs/agent-investigations/）、写周度监督报告、提出 OQF、起草规则修改 PR | 写每日 Audit（Cline 独占）、改产品代码、建修复 PR、Merge / Release、直接改 PROMPT/POLICY/SCHEMA、直接合入 PR |
| **Human Owner** | 一切（产品方向、Issue 排期、合并决策、权限变更、Pending Decisions 裁决） | — |

**一句话**：Agent 是 **Maintainer Auditor**，不是 Product Owner，不是自主 Coding Agent。
**产品方向**：Human decides product direction；Agent 提供工程情报（evidence before issue, issue before fix, research before migration）。
**监督层**：Doubao = Supervisor（详见 `SUPERVISOR.md`）——Observer → Supervisor → Human Authority；Agent 自治 ≠ Agent 自证。

---

## 2. 权限矩阵（第一阶段，铁律）

### 2.1 Allowed（允许）

| 类别 | 具体能力 |
|------|---------|
| 读仓库 | source code / tests / Issues / PRs / Actions / discussions / docs / ADR / contracts / regression / evidence |
| 读 git 历史 | `git log` / `git blame` / `git diff` / `git show`（只读） |
| 读 GitHub | `gh issue list/view`、`gh pr list/view`、`gh run list/view`（显式 CLI 命令，走命令白名单） |
| 运行验证 | `flutter analyze`、`flutter test`（单文件或全量）、`flutter pub deps`、`python` / `pytest`（tools/ffx-cli 测试） |
| 只读分析 | ADI 诊断命令（`dart run tools/adi/adi.dart` 只读子命令）、grep / 代码搜索 |
| 外部研究 | web 搜索 / 文档阅读（生态调研） |
| 写 Audit | 创建 / 更新 `docs/agent-audit/`、`docs/agent-investigations/` 下文档 |
| 创建 Issue | `gh issue create`（遵守 PROMPT.md §7-8 Admission Gate 与格式） |
| 评论 Issue | `gh issue comment`（更新证据 / 根因判断 / 关闭说明） |

### 2.2 Forbidden（禁止，任何情况下）

| 类别 | 具体禁止 |
|------|---------|
| 修改源码 | 任何 `flutter_app/lib/`、`tools/` 下产品代码改动（含测试文件） |
| 创建产品 PR | `gh pr create` |
| Merge | `gh pr merge` / `gh api .../merges` |
| Release | `gh release create` / tag 创建 |
| 仓库设置 | `gh repo edit`（含 description / homepage / visibility 等） |
| 分支保护 | 修改 branch protection rules |
| Secrets | `gh secret set/delete`、读取 secrets 值 |
| Actions 策略 | `gh workflow disable/enable`、修改 workflow 文件 |
| Agent 策略 | 修改 `PROMPT.md` / `POLICY.md` / `SCHEMA.md` |
| Roadmap / ADR | 修改 `docs/ROADMAP.md`、`docs/decisions/ADR/`、`AGENTS.md` |

### 2.3 命令白名单（Cline 侧强制，`CLINE_COMMAND_PERMISSIONS`）

允许（仅验证与维护所需）：

```
git status
git log *
git diff *
git grep *
git show *
flutter analyze *
flutter test *
flutter pub deps *
python *
python3 *
pytest *
gh issue list *
gh issue view *
gh issue create *
gh issue comment *
gh pr list *
gh pr view *
gh run list *
gh run view *
```

> **说明**：不使用 `gh api`——所有 GitHub 读取均通过上述显式 `gh` 子命令完成（`gh api *` 一律 deny，更安全）。

默认拒绝（不在 allowlist 中，即禁止）：

```
git push / git reset --hard / rm -rf / sudo
gh repo edit / gh secret * / gh workflow disable / gh release create
gh pr create / gh pr merge
任何写入 git 历史或仓库状态的命令
```

### 2.3.1 能力边界与分工（Cline 无运行能力 → 审查职责边界）

Cline 的命令白名单**不含运行产品的能力**（无 `flutter run`、无真机/模拟器、无动态执行）——因此审查职责按能力切分：

- **Cline 能可靠判定的**：文档 / CI / Issue / PR / 依赖 / 架构漂移的**现状**，以及**静态代码**可确证的 bug（文件:行 + 执行路径 + 实际影响）。
- **Cline 不能可靠判定的**（需运行 / 真机 / 体验）：产品体验、真机渲染（WebView / SVG / 公式 PNG）、性能、交互卡顿、设备差异。此类问题 Cline **不得**宣称"已审查 / 无问题"——应在 Audit 中标 `needs-device-validation`，交由 Doubao Supervisor 深度追查或人工真机验证。
- **审查深度纪律**：每日必须完成 1-2 个高价值模块的执行路径级深读（PROMPT §2 深度锚点）；`No significant findings` 必须附深度锚点文件列表，否则视为未完成审查。

### 2.3.2 Audit Frontier（增量审查模型，SUP-04）

Cline 不再"每日全盘重扫"，而是持续建立并推进**审查前沿（Audit Frontier）**——每次审查不是从零开始，而是把上一轮未闭合的证据链向前推进。**审查优先级：Frontier 未闭合项 > 新增代码/Issue 触发 > 其余风险扫描**。

**增量三触发器**（防止"增量 = 只看 git diff"，代码长期未改的区域也必须逐轮深入）：
- **Change-driven**：代码 / 依赖 / PR / 测试失败变化 → 重审变化路径
- **Risk-driven**：高风险但长期未修改的区域 → 逐轮深入（代码三个月没动也要审）
- **Evidence-driven**：上轮未闭合证据链 → 本轮优先续追

**Frontier Entry 生命周期**（candidate → active → deepening → blocked → verified → cooling → retired）：
- **cooling**：连续 3 轮无代码变化 / 无新证据 / 无新异常 → 移入冷却区，释放审查预算
- **reactivation**：新代码命中 / 新 Issue / 测试失败 / 新 Evidence → cooling → active
- **retired**：归档（保留 `retired_at` + `retire_reason`），未来可重激活——归档不是删除，是项目技术记忆

**Frontier 纪律**：
- Entry 写入 `.agent/tafcm-maintainer/FRONTIER.md`（字段规范见该文件头注释），每日 Audit 必须包含"Frontier 推进"记录（Entry id: depth N→N+1 / 新证据 / 新阻塞）
- **depth target 由 Cline 提议，周度 Supervisor Pass（SUP-01）校准**——不允许 Cline 自定 target 提前"闭合"；闭合必须有产出物（Issue 链接或 confirmed/rejected 证据落点）
- 越过 Cline 能力边界（真机 / WebView 渲染 / 设备行为）→ 写正式机器状态 `verification_status: needs-device-validation` + `handoff`（executor + reason），按 SUP-03 交 Supervisor / 人工，**不得臆断代替验证**

### 2.4 Doubao Supervisor（监督层）权限

> **定位**：Doubao 是 Cline Maintainer Agent 的监督 / 验证 / 质量 Agent，不是第二个执行 Agent。完整协议见 `SUPERVISOR.md`。

| 类别 | 具体能力 |
|------|---------|
| 监督只读 | 读 Cline 的 Audit / Issue / FINDINGS / workflow 运行记录；抽样核对源码 / CI / 测试 |
| 四层监督 | L1 Execution Health · L2 Output Quality · L3 Coverage Quality · L4 Systemic Quality |
| 深挖调查 | 写 `docs/agent-investigations/issue-<NNN>-<slug>.md`（Issue 只留结论） |
| 周度监督报告 | 写 `docs/agent-supervision/YYYY-WW-supervisor-report.md`（元审查，非重复 Audit） |
| 提出 OQF | OQF-INFO/WARN 只进周报；仅 OQF-CRITICAL 达升级阈值才转 GitHub Issue |
| 规则修改 | 仅**起草** PROMPT/POLICY/SCHEMA 修改 PR，由 Human Owner 审批合入 |

**禁止**：写每日 Audit（Cline 独占）、改产品代码、建修复 PR、Merge / Release、直接修改 PROMPT/POLICY/SCHEMA、直接合入 PR。OQF 定位为**监督证据**，不是项目工单。

---

## 3. 运行流程（CI 编排视角）

```
GitHub Actions（schedule: 每天 + workflow_dispatch）
   │
   ▼
1. Checkout（fetch-depth: 0，完整历史）
   │
   ▼
2. Setup Flutter + Dart（与 ci.yml 同版本锁定）
   │
   ▼
3. Setup Cline CLI（npm 安装，锁定版本）＋ AGNES 认证（OpenAI 兼容端点）
   │
   ▼
4. 运行 Cline Headless（注入 PROMPT.md，受 CLINE_COMMAND_PERMISSIONS 约束）
   │    ├── 读上下文（CURRENT-STATE / ADR / INDEX / 近 7 天 Audit / 历史 Agent issue）
   │    ├── 六维审查（Code / Issue / CI-Test / Architecture / Ecosystem / Dependency）
   │    ├── 运行验证（flutter analyze / flutter test 单文件）
   │    ├── 判定延续状态（NEW / UNCHANGED / UPDATED / RESOLVED / REJECTED / DUPLICATE / WAITING_FOR_HUMAN）
   │    ├── 写 docs/agent-audit/YYYY-MM-DD-maintainer-audit.md（五块事实账本）
   │    ├── 新问题按 Admission Gate 创建 Issue（gh issue create）；旧问题更新既有 Issue（gh issue comment）
   │    └── 深度调查写 docs/agent-investigations/（可选）
   │
   ▼
5. 校验 Audit 格式（validate_audit.py；失败 → workflow 失败）
   │
   ▼
6. 更新 docs/agent-audit/INDEX.md（脚本追加当日行）
   │
   ▼
7. Action commit + push（仅 docs/agent-audit/ 与 docs/agent-investigations/ 变更）
   │    commit message: chore(agent): daily maintainer audit YYYY-MM-DD
   │    ← Cline 本身无 git push 权限；提交由 Action 的受控脚本执行
   │
   ▼
8. 生成机器可读报告（report.json）+ 双邮件（send_report.py）
   │    ├── 立即邮件（P0/P1 / Release Blocker / 安全 / CI 长时间失败）——当天发
   │    ├── Weekly Digest（正常事项汇总）——每周五 18:00（北京时间）发
   │    └── 邮件失败 → Audit 仍为 SUCCESS，Email 标记 FAILED（不伪装全成功）
   │
   ▼
9. 结束（exit code 语义：Agent/校验失败=失败；邮件失败=明确区分）
```

---

## 4. Issue 处理策略（工作对象 + 状态机）

| 情况 | 行为 |
|------|------|
| 新 Finding 通过 Admission Gate 且判定为**新问题** | `gh issue create`，标题 `[Agent] <问题>`，标签 `source:agent` + `type:*` + `priority:*`；Audit 标记 `NEW` |
| **旧问题的新证据**（已存在 Issue / Audit / Investigation） | **不创建新 Issue**；评论补充新证据 / 更新根因级别 / 更新 Current Status；Audit 标记 `UPDATED` |
| 已有 PR 在修 | 不建 Issue；Audit 记录"PR 在途" |
| 已解决 / 判定不值得修 | Audit 标记 `RESOLVED` / `REJECTED`（附理由），不建 Issue |
| 需要维护者决策才能推进 | Audit 标记 `WAITING_FOR_HUMAN` + 加入 Pending Decisions；必要时在 Issue 评论 @Owner |
| 与既有项重复 | Audit 标记 `DUPLICATE`，链接原始项，不建 Issue |
| 低置信度 / 无证据 | 只入 Audit（NEW，低 Confidence），不建 Issue |
| 纯重构 / 风格偏好 / 低价值优化 | 不建 Issue，不推动重构 |
| 生态发现（E-ID） | 只进 Audit 的 Ecosystem Findings；仅当"值得 PoC"才建 `[Research] Evaluate <Topic>` |

**核心纪律**：同一问题的后续调查（9/2 补证据 → 9/3 找历史提交 → 9/4 生态方案 → 9/5 根因确认）**全部汇总到同一个 Issue**，禁止每天新建 #217 #218 #219 #220。GitHub Issue 不被"新闻"和"研究想法"污染。

---

## 5. 去重与记忆（Anti-Duplication + 状态机）

1. **仓库内持久记忆**：`docs/agent-audit/INDEX.md` + 每日 Audit 文件（事实账本，长期保留，随仓库提交）
2. **Issue 侧**：`gh issue list --label source:agent`（历史 Agent issue）＋标题近似搜索
3. **每日判定**：每次运行先读近 7 天 Audit + 历史 Agent issue，判断"新问题 vs 旧问题的新证据"
4. **状态机落地**：旧 Finding 必须给出延续状态（UPDATED / UNCHANGED / RESOLVED / REJECTED / DUPLICATE / WAITING_FOR_HUMAN），**不得**重新标为 NEW
5. **落地规则**：相同 Finding 第二次运行不得重复创建 Issue；旧问题的新证据必须追加到既有 Issue，禁止每天新建同主题 Issue
6. **生态去重**：E-ID 在 Audit 中持续跟踪；同一生态主题的重复发现合并为一条，不重复建议迁移

---

## 5.1 双邮件策略（立即 + 周报）

| 邮件 | 触发 | 内容 |
|------|------|------|
| **立即邮件**（Maintainer Alert） | 当日存在 P0/P1 / Release Blocker / 安全问题 / CI 长时间失败 | 严重项清单：问题一句话 + 根因级别 + Issue 链接 |
| **Weekly Digest** | 每周五 18:00（北京时间，cron `0 10 * * 5` UTC，汇总过去 7 天） | 状态变化摘要：新增 / 升级 / 解决 / 生态变化 / **需要你决策** |

**原则**：邮件做**状态变化摘要**（"自上次汇报以来发生了什么值得你知道的变化"），**不是**每日 Audit 复述。让维护者 7 天不看邮箱也不错过上下文。**Audit 记全、Issue 管住、Email 提醒决策**——三者不重复写"今天发现了 XXX"。

---

## 6. 失败语义（Action 侧）

| 环节失败 | Workflow 状态 | 报告 |
|---------|--------------|------|
| Cline 运行失败 / 未产出 Audit | ❌ FAILED | "Agent run failed" |
| Audit 格式校验失败 | ❌ FAILED | "Audit validation failed"（不伪装成功） |
| Audit 生成成功 + commit 成功 | ✅ SUCCESS | 正常报告 |
| Audit 成功 + 邮件失败 | ✅ SUCCESS（Audit） | 明确报告 "Audit completed but email delivery failed." |

**原则**：Audit 保存/提交优先于邮件；邮件失败不得导致 Audit 丢失或 workflow 误判为全成功。

---

## 7. Secrets 清单

| Secret | 用途 | 提供方 |
|--------|------|--------|
| `AGNES_API_KEY` | Cline → AGNES OpenAI 兼容端点认证（已在仓库配置，复用） | Human Owner 已配置 |
| `MAIL_HOST` / `MAIL_PORT` | SMTP 服务器 | Human Owner 配置 |
| `MAIL_USERNAME` / `MAIL_PASSWORD` | SMTP 认证 | Human Owner 配置 |
| `MAIL_TO` | 收件人（维护者邮箱） | Human Owner 配置 |

**规则**：任何密钥不得写入仓库文件；全部经 GitHub Actions Secrets 注入环境变量。

---

## 8. 阶段边界与变更流程

- **第一阶段**：只读 + Audit + Issue（本文档 §2.1-2.2）。
- **阶段演进**（如需 Agent 修改代码 / 建 PR / 修复）：必须由 Human Owner 立项（ROADMAP 或新 ADR），显式授权后更新本文档权限矩阵，才可放开。
- **越权行为**：任何尝试修改被禁对象的命令，由 Cline 命令白名单与 Action 权限模型双重拦截；如发现配置漏洞，立即报告 Human Owner。

---

## 9. 与既有系统的关系（复用，不冲突）

| 既有系统 | 关系 |
|---------|------|
| `issue-triage.yml`（ADR-0025） | PR/分支事件驱动的 Issue 挖掘，与本 Agent 互补；标签/去重规范保持一致 |
| `cline-pr-review.yml` | PR 审查；本 Agent 复用其 AGNES 端点 + `CLINE_COMMAND_PERMISSIONS` 模式 |
| `ci.yml` | 质量门禁；本 Agent 的测试运行与版本锁定对齐 ci.yml（Flutter 3.44.6 / ubuntu-24.04） |
| `.agent/` 治理层 | 本目录是 `.agent/` 的新增子域，遵循 REPO_POLICY / AI_POLICY 总体约束 |
| `docs/` 信息架构 | `docs/agent-audit/` 与 `docs/agent-investigations/` 为新增子目录，登记到 docs/INDEX.md |

---

## 10. 验收标准（本 Agent 上线前必须满足）

- [ ] `workflow_dispatch` 触发成功
- [ ] Cline 无交互启动并完成一次审查
- [ ] Agent 能读取 source / tests / issues / actions / ADR / contracts / roadmap
- [ ] 生成 `docs/agent-audit/YYYY-MM-DD-maintainer-audit.md`（五块事实账本）且格式正确（validate_audit.py 通过）
- [ ] 人工制造明确测试 Finding，Agent 能按 Admission Gate + 状态机创建规范 Issue（NEW）
- [ ] 相同 Finding 第二次运行不重复创建（去重生效，旧 Finding 标 UPDATED/UNCHANGED 而非 NEW）
- [ ] 旧问题新证据能追加到既有 Issue（持续调查协议生效，不新建同主题 Issue）
- [ ] 生态发现只进 Audit（E-ID），仅值得 PoC 才建 `[Research]` Issue
- [ ] 邮件：P0/P1 立即邮件 + 周五 18:00 Weekly Digest 成功发送（状态变化摘要，非每日复述）
- [ ] 人为制造 Agent / email failure：workflow 状态正确、Audit 不丢失、email 失败与 audit 成功可区分
- [ ] 权限验证：Agent 不能改源码 / merge / release / 改 workflow / 改 secrets

---
