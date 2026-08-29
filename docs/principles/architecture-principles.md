---
status: active
type: principle
owner: maintainers
last_reviewed: 2026-08-30
---

# Architecture Principles（架构原则）

> 回答"系统为什么这样组织"。稳定条款，修改需 Human Owner 批准。
> 提炼源：AGENTS.md §1、ARCHITECTURE.md、ADR-0002/0003/0009/0012/0020/0031。

## 1. 六层分层，依赖单向

```
presentation → providers → domain → data → core → main.dart
```

- 依赖只允许自上而下，**循环依赖零容忍**（CI 守门，非口头约定）。
- `core` 不得反向 import `presentation` / `domain` / `providers`。
- 新增跨层调用前先问：这一层真的需要知道它吗？能下沉到更底层吗？

## 2. .md 文件是唯一真相源

- 文档存储以 `.md` 为单一真相（ADR-0003 Implemented）；废弃 `formula_fix_documents.json` 与 SharedPreferences 存正文。
- 禁止新增第四套存储；派生缓存（SQLite / FileIndex）需先过 ADR。
- 从外部读取的字节流必须走 `decodeBytesAuto`（中国用户 .md 常含 GBK 字节），禁止直接 `utf8.decode`。

## 3. 编辑器：Transaction 模型 + WYSIWYG 块编辑

- 用户操作 → `EditorCommand`（纯数据、可序列化）→ `CommandHandler` → `TransactionBuilder → BlockOperation` → AST。
- 用户看到的是 Document 而非 Block；BlockRenderer 是排版引擎不是卡片系统（Typora 化，非 Notion 化）。
- 编辑/预览分离模式是历史遗留，目标态为单一 WYSIWYG 视图。

## 4. 状态管理走 Riverpod 决策树

- 需要异步 → FutureProvider / AsyncNotifierProvider；需要改状态 → StateNotifierProvider / StateProvider；否则 → Provider。
- Provider 状态必须不可变（`copyWith` / 新对象，禁止 `state.list.add`）。
- 资源持有型 Provider（WebView / Stream / Timer）必须 `autoDispose` 或显式清理。
- 禁止在多个文件定义同名 Provider。

## 5. 渲染与公式：矢量优先、可降级、不崩溃

- 公式渲染：LaTeX → SVG 矢量（导出硬约束），flutter_math 降级渲染，绝不因公式解析失败 crash。
- Renderer 不得因未知 BlockElement crash（ADR-0022 原则仍有效；实现上靠全量 exhaustive switch 保证）。
- 用户输入路径上的任何层，都不能因为未来能力缺失而 crash。

## 6. 可观测性内建

- ADI（Agent Diagnostic Interface）+ observability 采集是架构的一部分，不是事后补丁（ADR-0023/0024）。
- 关键行为必须有诊断入口：渲染追踪、错误快照、诊断 zip 导出。

## 7. 架构演进纪律

- 架构决策先落 ADR（禁止凭空设计）；跨阶段实现禁止。
- 重构 PR 必须 0 业务行为变化；演进不追求目录好看，追求"权威性 + 入口清晰"。
- 当前阶段定位（2026-08-30）：Phase 3 系列收尾、阶段间空档期；新大阶段功能需 Human Owner 立项。
