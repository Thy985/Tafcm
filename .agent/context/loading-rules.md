# Context Loading Rules

> 定义 AI Agent 在每次执行任务前必须加载的上下文，按优先级分层。
> 目标：随着项目文档增长，AI 始终知道"应该读什么"，避免加载无关内容或遗漏关键约束。

---

## Level 0: Always Load（每次任务必须）

无论任务大小，每次执行前必须读取。**先读 RSL 四份核心文件，再读 AGENTS.md**——RSL 优先级高于 AGENTS.md；AGENTS.md §12 的"绕过术退役"标注只有在 RSL 被先加载时才生效，顺序颠倒会短暂误用已退役流程。

| 文件 | 原因 |
|------|------|
| [.agent/REPO_POLICY.md](file:///d:/Projects/Active/math2/.agent/REPO_POLICY.md) | **Repository Safety Layer 总纲（最高优先级）**：裁决链、三条铁律、事故登记册、损坏 SOP |
| [.agent/ENVIRONMENT.md](file:///d:/Projects/Active/math2/.agent/ENVIRONMENT.md) | 仓库拓扑唯一真相：root / 边界 / 工具链 / worktree |
| [.agent/GIT_RULES.md](file:///d:/Projects/Active/math2/.agent/GIT_RULES.md) | Git 红/黄/绿线；损坏应急 6 步 SOP |
| [.agent/COMMAND_SAFETY.md](file:///d:/Projects/Active/math2/.agent/COMMAND_SAFETY.md) | 危险命令三前置；rsync/rm 安全模板 |
| [AGENTS.md](file:///d:/Projects/Active/math2/AGENTS.md) | 项目核心规范、禁止事项（以 RSL 为准，见上方优先级） |
| [AI_POLICY.md](file:///d:/Projects/Active/math2/.agent/AI_POLICY.md) | Agent 权限边界、停止条件 |
| [ROADMAP.md](file:///d:/Projects/Active/math2/docs/ROADMAP.md) | 当前 Phase、任务优先级 |
| [WORKFLOW.md](file:///d:/Projects/Active/math2/docs/WORKFLOW.md) | 开发流程、CI/CD 门禁 |

> **优先级裁决**：RSL 四份 > AGENTS.md > 会话记忆。任何与 RSL 冲突的旧规则，以 RSL 为准（详见 .agent/REPO_POLICY.md §2）。

---

## Level 1: Phase Context（按当前阶段）

根据 ROADMAP.md 当前 Phase 加载对应文档：

### Phase 0（工程化 + UI Prototype Freeze）

| 文件 | 原因 |
|------|------|
| [ARCHITECTURE.md](file:///d:/Projects/Active/math2/docs/ARCHITECTURE.md) | 架构总览 |
| [CRITICAL_REVIEW.md](file:///d:/Projects/Active/math2/docs/CRITICAL_REVIEW.md) | 已知问题清单 |
| [GIT_WORKFLOW.md](file:///d:/Projects/Active/math2/docs/GIT_WORKFLOW.md) | Git 详细流程 |

### Phase 1（底层重构）

| 文件 | 原因 |
|------|------|
| [REFACTOR_DESIGN.md](file:///d:/Projects/Active/math2/docs/REFACTOR_DESIGN.md) | 重构方案 |
| [ARCHITECTURE.md](file:///d:/Projects/Active/math2/docs/ARCHITECTURE.md) | 架构总览 |
| [CRITICAL_REVIEW.md](file:///d:/Projects/Active/math2/docs/CRITICAL_REVIEW.md) | 已知问题清单 |

### Phase 2（编辑模型）

| 文件 | 原因 |
|------|------|
| [REFACTOR_DESIGN.md](file:///d:/Projects/Active/math2/docs/REFACTOR_DESIGN.md) | 编辑模型设计 |
| 所有相关 ADR | 历史决策 |

### Phase 3（UI Implementation）

---

## Level 2: Scope Context（按修改范围）

根据任务涉及的模块，加载对应领域的文档：

### Storage（存储层）

| 文件 | 原因 |
|------|------|
| [ADR/0003-storage-single-source-md-files.md](file:///d:/Projects/Active/math2/docs/ADR/0003-storage-single-source-md-files.md) | 存储架构决策 |
| `lib/core/services/file_service.dart` | 当前实现 |
| `lib/data/models/document.dart` | 数据模型 |

### Parser（解析器）

| 文件 | 原因 |
|------|------|
| [ADR/0004-markdown-parser-extension-strategy.md](file:///d:/Projects/Active/math2/docs/ADR/0004-markdown-parser-extension-strategy.md) | 解析器扩展策略 |
| `lib/core/parser/` | 当前实现 |
| `lib/data/models/document.dart` | AST 定义 |

### Editor（编辑器）

| 文件 | 原因 |
|------|------|
| [REFACTOR_DESIGN.md](file:///d:/Projects/Active/math2/docs/REFACTOR_DESIGN.md) | 编辑器重构方案 |
| `lib/presentation/screens/editor_screen.dart` | 当前实现 |
| `lib/presentation/widgets/preview_content.dart` | 预览组件 |

### Exporter（导出）

| 文件 | 原因 |
|------|------|
| [ADR/0005-exporter-facade-dependency-injection.md](file:///d:/Projects/Active/math2/docs/ADR/0005-exporter-facade-dependency-injection.md) | 导出架构决策 |
| `lib/domain/services/export_service.dart` | 导出服务 |
| `lib/domain/services/exporters/` | 各导出器实现 |

### State Management（状态管理）

| 文件 | 原因 |
|------|------|
| [ADR/0002-state-management-riverpod.md](file:///d:/Projects/Active/math2/docs/ADR/0002-state-management-riverpod.md) | 状态管理决策 |
| `lib/providers/` | 当前 Provider |
| `lib/domain/providers/` | 业务 Provider |

### CI / Engineering（工程化）

| 文件 | 原因 |
|------|------|
| [.github/workflows/ci.yml](file:///d:/Projects/Active/math2/.github/workflows/ci.yml) | CI 配置 |
| [ADR/0006-ci-github-actions.md](file:///d:/Projects/Active/math2/docs/ADR/0006-ci-github-actions.md) | CI 架构决策 |

---

## Level 3: Code Context（按需加载）

仅读取与任务直接相关的代码文件：

- 目标模块（要修改的文件）
- 直接依赖（被目标模块 import 的项目内文件）
- 对应测试文件

**禁止**：无目的加载整个仓库。

---

## Context Output（执行前输出）

AI Agent 在开始编码前，必须在对话中输出上下文摘要：

```markdown
## Context Summary

Phase: <当前 Phase>
Task: <ROADMAP 任务编号>

Relevant Rules:
- <AGENTS.md 中适用的规则>

Applicable ADR:
- <相关 ADR 编号和摘要>

Files to Modify:
- <文件路径 1>
- <文件路径 2>

Risk Level: Low / Medium / High
```

---

## Memory Policy

### 项目记忆

项目级记忆存储在 `project_memory.md`，记录：
- 硬约束（Hard Constraints）
- 工程惯例（Engineering Conventions）
- 经验教训（Lessons Learned）

### 会话记忆

会话级记忆存储在 `topics.md` 和 `session_memory_*.jsonl`，记录：
- 当前会话的决策和进展
- 文件修改历史

### 记忆更新触发

以下情况必须更新项目记忆：
- 发现新的硬约束
- 工程惯例变更
- 可复用的经验教训

---

**本文档由 Human Owner 维护，版本 v0.1，生效日期 2026-07-18。**