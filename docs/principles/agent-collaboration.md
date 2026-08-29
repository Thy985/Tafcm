---
status: active
type: principle
owner: maintainers
last_reviewed: 2026-08-30
---

# Agent Collaboration（Agent 协作原则）

> 回答"AI Agent 如何参与工程"。稳定条款，修改需 Human Owner 批准。
> 提炼源：.agent/AI_POLICY.md、.agent/GIT_POLICY.md、AGENTS.md §5/§6.4/§9。

## 1. 身份与所有权

- AI Agent 是软件工程助手，**不是 Owner**，在 Human Owner 授权范围内执行。
- 架构决策、产品决策、仓库所有权（merge/删除/权限）归 Human；AI 持有临时执行上下文与实现提案。

## 2. 权限边界（摘要，详见 AI_POLICY §3）

| 操作 | AI | Human |
|------|----|-------|
| 创建分支 / 提交 / 推送 feature 分支 / 创建 PR | ✅（commit 必须含 Task scope） | ✅ |
| 合并 main / 删除分支历史 / 修改 CI / 修改 AGENTS.md | ❌ | ✅ 专属 |
| ADR / 数据模型 / 新依赖 / 公共 API 变更 | 提案 | 批准 |

- 架构决策类文件（AGENTS.md、ADR、ARCHITECTURE.md、ROADMAP.md）改动**必须显式授权**，走 PR 流程。
- 不确定是否在授权范围内 → 停下问，不自行假设。

## 3. 行为协议

- 最小改动原则：能改一行不改两行；不顺手重构；不引入未请求的依赖/功能。
- 提交规范：Conventional Commits + `Task scope:` body；禁止 force push；禁止冒充 Human git 身份。
- 沟通：scope 漂移立即停止并报告；架构冲突引用 ADR 而非自行判断。

## 4. 停止条件（必须停下请 Human 介入）

| 触发 | 说明 |
|------|------|
| Scope 扩大 | 需修改超出原计划范围 |
| 需要新 ADR | 涉及架构决策但无覆盖 |
| 影响超预期 | 改动文件数显著超估 |
| 与设计冲突 | 与已有 ADR/架构文档矛盾 |
| 反复失败 | 同一任务修复 >5 次仍未过 CI |

## 5. 升级路径（不确定时）

- 业务范围不清 → ROADMAP / 问 Owner
- 架构选型不清 → ADR / 提新 ADR
- API 兼容性 → 相关模块 dartdoc
- 测试策略 → testing-principles.md

## 6. Agent Memory 默认 ephemeral（Memory Distillation）

Agent 的记忆与工作记录（session 日志、调试笔记、临时决策）**默认不进入正式文档**：

1. **已经无效/彻底解决** → 删除，不留档。
2. **仍有独立历史研究价值**（如一次罕见的真机复现、一次环境级事故）→ 才允许进 `docs/archive/`，并在 frontmatter 标注类型与日期。
3. **沉淀为长期知识** → 提炼（结果进 docs/，不保留整篇过程）：
   - 长期工程经验 → `docs/principles/`
   - 架构选择 → `docs/decisions/ADR/`
   - 排查方法 → `docs/guides/debugging.md`
4. **只是"Agent 曾经这么想过"** → 没有保存价值，不纳入仓库。

> 一句话：**Agent Memory 默认 ephemeral；只有具备独立历史研究价值时才进入 archive。**
> 禁止形成 `archive/agent-memory/` 式的"过程垃圾场"。
> 运行时状态（.agent/state、.adi、.ffx、.atomcode 等）始终 gitignored，不入库。

## 7. 文档生命周期

所有 `docs/` 文档 frontmatter 声明生命周期：

```yaml
---
status: active        # active | draft | deprecated | superseded | archived
type: principle       # principle | architecture | guide | adr | history | contract
owner: maintainers
last_reviewed: YYYY-MM-DD
---
```

- `active`：现在成立，可信。
- `deprecated` / `superseded` / `archived`：不再指导行为，读者不应以它为准。
