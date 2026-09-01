# Tafcm Maintainer Agent — 权限与流程策略（POLICY）

> **定位**：Tafcm Maintainer Agent 的权限边界、禁止事项与运行流程的权威定义。
> **配套**：`PROMPT.md`（行为协议）· `SCHEMA.md`（数据格式）· `.github/workflows/tafcm-maintainer.yml`（执行编排）· `.github/scripts/tafcm-maintainer/`（校验与邮件脚本）。
> **适用范围**：第一阶段（观察 / 分析 / 记录 / 建 Issue）。后续阶段权限变更必须经 Human Owner 显式批准并更新本文档。

---

## 1. 角色定义

| 角色 | 能做什么 | 不能做什么 |
|------|---------|-----------|
| **Tafcm Maintainer Agent** | 读仓库、跑验证、研究生态、写 Audit、建 Issue、评论 Issue | 改产品代码、建 PR、Merge、Release、改仓库设置 |
| **Human Owner** | 一切（产品方向、Issue 排期、合并决策、权限变更） | — |

**一句话**：Agent 是 **Maintainer Auditor**，不是 Product Owner，不是自主 Coding Agent。

---

## 2. 权限矩阵（第一阶段，铁律）

### 2.1 Allowed（允许）

| 类别 | 具体能力 |
|------|---------|
| 读仓库 | source code / tests / Issues / PRs / Actions / discussions / docs / ADR / contracts / regression / evidence |
| 读 git 历史 | `git log` / `git blame` / `git diff` / `git show`（只读） |
| 读 GitHub | `gh issue list/view`、`gh pr list/view`、`gh run list/view`、`gh api` 只读端点 |
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
gh api repos/Thy985/Tafcm/issues/*        # 只读查询
gh api repos/Thy985/Tafcm/pulls/*         # 只读查询
```

默认拒绝（不在 allowlist 中，即禁止）：

```
git push / git reset --hard / rm -rf / sudo
gh repo edit / gh secret * / gh workflow disable / gh release create
gh pr create / gh pr merge
任何写入 git 历史或仓库状态的命令
```

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
   │    ├── 读上下文（CURRENT-STATE / ADR / INDEX / 近期 Audit）
   │    ├── 六维审查（Code / Issue / CI-Test / Architecture / Ecosystem / Dependency）
   │    ├── 运行验证（flutter analyze / flutter test 单文件）
   │    ├── 写 docs/agent-audit/YYYY-MM-DD-maintainer-audit.md
   │    ├── 按 Admission Gate 创建 Issue（gh issue create）
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
8. 生成机器可读报告（report.json）+ 发送邮件（send_report.py）
   │    邮件失败 → Audit 仍为 SUCCESS，Email 标记 FAILED（不伪装全成功）
   │
   ▼
9. 结束（exit code 语义：Agent/校验失败=失败；邮件失败=明确区分）
```

---

## 4. Issue 处理策略

| 情况 | 行为 |
|------|------|
| 新 Finding 通过 Admission Gate | `gh issue create`，标题 `[Agent] <问题>`，标签 `source:agent` + `type:*` + `priority:*` |
| 已有重复 Issue | **不创建**；评论补充新证据 / 更新根因级别（Confirmed/Likely/Hypothesis/Unknown） |
| 已有 PR 在修 | 不建 Issue；Audit 记录"PR 在途" |
| 已解决 Finding（近期 Audit 已报告） | Audit 记录 Status=Resolved/Verified 或 Won't-fix（附理由） |
| 低置信度 / 无证据 | 只入 Audit，不建 Issue |
| 纯重构 / 风格偏好 / 低价值优化 | 不建 Issue，不推动重构 |

---

## 5. 去重与记忆（Anti-Duplication）

1. **仓库内持久记忆**：`docs/agent-audit/INDEX.md` + 每日 Audit 文件（长期保留，随仓库提交）
2. **Issue 侧**：`gh issue list --label source:agent`（历史 Agent issue）＋标题近似搜索
3. **每日检查**：每次运行先读近期 Audit，识别重复 / 未解决 / 趋势性 Finding
4. **落地规则**：相同 Finding 第二次运行不得重复创建 Issue；必须引用已有 Issue 或标注已报告

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
- [ ] 生成 `docs/agent-audit/YYYY-MM-DD-maintainer-audit.md` 且格式正确（validate_audit.py 通过）
- [ ] 人工制造明确测试 Finding，Agent 能按 Admission Gate 创建规范 Issue
- [ ] 相同 Finding 第二次运行不重复创建（去重生效）
- [ ] 邮件成功发送 `Tafcm Daily Maintainer Report`
- [ ] 人为制造 Agent / email failure：workflow 状态正确、Audit 不丢失、email 失败与 audit 成功可区分
- [ ] 权限验证：Agent 不能改源码 / merge / release / 改 workflow / 改 secrets

---
