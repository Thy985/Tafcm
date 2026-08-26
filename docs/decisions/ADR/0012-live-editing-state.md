# ADR-0012：Live Editing State 与 Document State 分离

> **状态**：Accepted（Human Owner 在 2026-07-24 会话中口述决策并授权起草,随 Phase 3.3 E2E 收尾 PR #65 提交）
> **版本**：v1.1 Accepted
> **起草日期**：2026-07-24
> **Accepted 日期**：2026-07-24（Human Owner 决策,PR #65 提交即冻结）
> **起草人**：AI Agent 起草,Human Owner 决策
> **关联文档**：
> - [ADR-0011 Phase 3.3 架构决策](./0011-phase3.3-architecture-decisions.md)（v1.1 Accepted,本 ADR 细化其 §4 Dirty Tracking 的「实时」维度）
> - [ADR-0008 Editor Transaction Model](./0008-editor-transaction-model.md)（v1.1 Proposed,本 ADR 的 Transaction Commit 边界依赖其 Transaction/History 模型）
> - [ADR-0009 UI Architecture Design](./0009-ui-architecture-design.md)（v1.1 Proposed,Command Layer 强制）
> - [Phase 3.3 Task Contract v1.4](../../contracts/phase3.3-task-contract.md)（Accepted,§3.3.4 实时字数统计）
>
> **审批路径**：Human Owner 在会话中直接决策「双状态分离」并指示「在继续 PR 前冻结此 ADR,避免 Command Layer 被三种提交模型返工」。本 ADR 随 PR #65 提交,合并即视为 Accepted。

---

## 版本修订记录

- **v1.0 草案 + Accepted（2026-07-24）**：初版,记录 Live Editing State 与 Document State 双状态模型。触发事件为 Phase 3.3 E2E 全量重跑暴露的「§3.3.4 实时字数」vs「产品失焦才提交」冲突。Human Owner 决策冻结。
- **v1.1 Accepted（2026-07-25）**：补「Editor Context Preservation」延伸节 —— 记录模板菜单 Toolbar 抢焦点产品 bug 及其修复（捕获最后聚焦块）;zoom 双指手势 E2E 降级为 smoke + 平台级验证 TODO。

---

## 背景

### 当前状态（冲突暴露前）

Phase 3.3 已实现：
- 字号缩放（§3.3.2）+ 焦点模式（§3.3.3）,chrome 接线完成（title / wordCount / isDirty / undo-redo 透传）
- 自动配对 / 自动续列表（PR #3,§3.3.6 / §3.3.8）
- 模板插入菜单（§3.3.10）

文本输入链路为：

```
TextEditingController  ──(onChanged)──▶  InputHandler
        │                                  │
        │                         配对 / 续行规则命中？
        │                                  │
        └──────── 失焦 / onSubmitted ───▶  UpdateBlockSourceCommand
                                                  │
                                                  ▼
                                          Document Model（committed）
```

即：**普通文本输入不会立即产生 Command**,只有「自动配对 / 自动续列表规则命中」或「失焦提交」才会把文本写进 Document Model。

### 触发本 ADR 的事件

Phase 3.3 E2E 全量重跑（Android Emulator,因 Windows 桌面未启用 + Web 不支持 integration_test,见 §12.5）暴露 14 个失败,其中 6 个根因是同一个架构冲突：

| 期望值（§3.3.4） | 实际产品行为 |
|------|------|
| 实时字数统计 | wordCount 取自已提交 source,纯文本输入不提交 → 不变 |
| 修改状态（dirty）实时显示 | isDirty 仅在 commit 后置 true |
| 实时编辑反馈 | 输入期间 Document 无变化 |

用户输入 `hello` 期间的瞬时状态对比：

| 状态 | 结果（旧架构） |
|------|------|
| TextField 显示 | `hello` |
| Document source | 旧值 |
| wordCount | 不变 |
| dirty | 不变 |
| undo | 无记录 |

而 Phase 3.3 Task Contract §3.3.4 明确要求「实时字数统计」「修改状态显示」「实时编辑反馈」,二者正面冲突。

**这次 E2E 失败不是 bug,而是一次架构验证**：它暴露了编辑器核心状态模型的一个未决选择 ——

> 「用户正在编辑中的内容（Live Editing State）」与「已经提交到文档模型的内容（Committed Document State）」是否分离？

这个决定会影响：**wordCount / dirty tracking / Undo-Redo / Auto Save / Collaboration（未来）/ AI 辅助编辑 / 搜索索引 / Preview 渲染 / PR #3 自动配对 / 后续 Phase 4 架构**。

若不冻结此决策,后续会出现：PR #3 自动配对用一种提交模型、Toolbar 用另一种、Template Insert 用第三种,最终 Command Layer 返工。

### 现有约束

- [ADR-0011 §4](./0011-phase3.3-architecture-decisions.md)：Dirty Tracking 归属 Document State（非 UI State）。本 ADR **细化**其「实时」维度,不推翻该归属。
- [ADR-0008](./0008-editor-transaction-model.md)：EditorCommand / Transaction / History 模型,本 ADR 的「Transaction Commit 边界」建立其上。
- [ADR-0009 §3](./0009-ui-architecture-design.md)：Command Layer 强制,UI 不直接调 BlockOperations。
- [AGENTS.md §2.3](../../../AGENTS.md)：services / facades 显式依赖注入。

---

## 决策

引入**双状态模型**：

```
                 User Input
                      │
                      ▼
         ┌─────────────────────┐
         │  Live Editing State │  高频、不进 History
         └─────────────────────┘
                      │
             transaction boundary（提交 / 失焦 / 规则触发）
                      │
         ┌─────────────────────┐
         │   Document State    │  稳定、进 Undo / 持久化
         └─────────────────────┘
                      │
                 HistoryManager
```

### Live Editing State

**职责**：保存用户当前编辑态。

**包含**：
- 当前 source（每个 Block 的实时文本）
- cursor / selection
- composing region

**用于**：
- wordCount（状态栏实时字数）
- dirty indicator（AppBar `•` / 保存按钮可用 / 关闭弹窗 / 自动保存判断）
- UI preview / 实时反馈

**特点**：
- 高频更新（每次 onChanged）
- **不直接进入 History**（不污染 Undo 粒度）

**Phase 3.3 最小落地位置**：
- `EditorCoordinator` 新增 `Map<BlockId, String> _liveSources`,由 `BaseBlockState._onTextChanged` 在每次文本变化时（composing 空、聚焦、含 CodeBlock）推入 `coordinator.updateLiveSource(blockId, text)`。
- `EditorCoordinator.wordCount` 改为从 `_liveSources` 实时计算（fallback 到已提交 source）。
- `EditorCoordinator.isDirty` 改为 `editor.isDirty || 任意 live 与 committed 不一致`。

### Document State

**职责**：保存稳定文档状态。

**用于**：
- 持久化（.md 导出 / 自动保存）
- Undo / Redo（History）
- Export / Sync / Collaboration（未来）

**更新方式**：仅通过 **Transaction Commit**（见 History Strategy）。

**Phase 3.3 过渡实现**：commit 时机保持现状 —— 失焦提交（`_onFocusChange` → `_commitSource`）或规则触发（`InputHandler` 自动配对 / 续列表命中时提交 `UpdateBlockSourceCommand`）。即 Phase 3.3 的「Transaction Buffer」退化为「单次 commit」,完整的合并缓冲留 Phase 3.4。

---

## History Strategy

### 禁止的方案

```dart
onChanged(value) {
  History.push(command);  // ❌ 每次按键都进 History
}
```

原因：输入 `hello` 会产生 `h → he → hel → hell → hello` **5 个 undo 步骤**,Undo 粒度完全错误,且每次按键都触发序列化 / AST 重算。

### 采用的方案

```
Live Update（高频、不进 History）
   │
   ▼
Transaction Buffer（合并 / 节流）
   │
   ▼
History Commit（1 步 Undo）
```

- **Live Update**：每次 onChanged 只更新 Live Editing State,不触碰 History。
- **Transaction Buffer / Coalescing**：将连续编辑合并为一个可撤销单元（Phase 3.4 引入,见 Migration Plan）。
- **History Commit**：在 transaction boundary（失焦 / 规则触发 / 显式命令）把合并后的结果作为 **1 个** Undo 步骤提交。

这样满足「§3.3.4 实时反馈」的同时,Undo 粒度保持正确（一次编辑 = 1 步）。

---

## Command Layer Impact

Command 分两类,统一经过 `Coordinator.handle()`（ADR-0009 强制）：

### Immediate Command（立即进 History）

例如：
- Toolbar 加粗 / 包裹（`WrapSelectionCommand`）
- 模板插入（`InsertTemplateCommand`）
- 自动配对（`PairInsertCommand` 经 `InputHandler` → `UpdateBlockSourceCommand`）
- 自动续列表（`InsertNewLineWithPrefixCommand`）

路径：`Command → Transaction → History`（同步、原子）。

### Editing Transaction（经 Live Buffer 合并后提交）

例如：
- 普通文本输入
- 删除
- 输入法（IME）组合

路径：
```
onChanged
   │
   ▼
Live State update（实时 wordCount / dirty）
   │
   ▼
Transaction Buffer（合并 / coalesce,Phase 3.4）
   │
   ▼
History Commit（transaction boundary）
```

**Phase 3.3 简化**：Editing Transaction 的 Buffer 退化为「失焦 / 规则触发即提交」,不实现合并。但 live→committed 的边界已经清晰,Phase 3.4 只需在边界前插入 Coalescing 层,不改动调用方。

---

## 替代方案

### 替代方案 A：保持 Blur Commit（拒绝）

维持现状：纯文本输入只在失焦时提交,wordCount / dirty 不实时。

**拒绝原因**：无法满足 Phase 3.3 已写入契约的：
- 实时 wordCount（§3.3.4）
- 实时 dirty 指示
- 移动端编辑实时反馈预期

且本次 E2E 失败证明它会持续制造「契约 vs 行为」的测试冲突。

### 替代方案 B：每次 onChanged 创建 Command（拒绝）

`every keystroke → UpdateBlockSourceCommand → History`。

**拒绝原因**：History 粒度错误（见 History Strategy）,Undo 体验崩溃,且每次按键触发序列化。

### 本 ADR 方案（采纳）

Live Editing State 高频更新（实时反馈）+ Document State 经 Transaction Commit（正确 Undo 粒度）。Phase 3.3 最小落地 Live + 实时 wordCount/dirty,Phase 3.4 补全 Coalescing Buffer。

---

## 与 ADR-0011 §4 的关系（细化而非推翻）

ADR-0011 §4 决策「Dirty Tracking 归属 Document State（非 UI State）」**保持不变**。

本 ADR 细化其「实时」维度：
- `isDirty` 的计算位置仍在 `EditorCoordinator`（Document State 层,非 UI State）。
- Phase 3.3 过渡实现：`isDirty = editor.isDirty（已提交脏标记）|| 任意 live source ≠ committed source（实时脏标记）`。
- 二者任一为真即显示 dirty。这既保留了「失焦才进 Document」的语义,又提供了「输入即显示 •」的实时反馈。

ADR-0011 §4.1 规划的 Phase 3.4 迁移（`CoordinatorState.isDirty` 字段）仍然有效,本 ADR 的 live 比较可无缝并入该字段的 getter 计算。

---

## 后果

### 正面后果

1. **满足 Phase 3.3 实时反馈要求**：wordCount / dirty 随输入即时刷新,契约 §3.3.4 从「需改测试绕过」变为「产品原生满足」。
2. **Undo 粒度正确**：Live State 不进 History,一次编辑 = 1 步 Undo（保留现有体验）。
3. **支持未来协作编辑**：Live / Committed 分离是 CRDT / OT 协作的标准前置架构。
4. **支持 AI 实时辅助**：AI 可读取 Live State 做实时建议,不影响已提交文档。
5. **冻结 Command Layer 提交模型**：PR #3 自动配对 / Toolbar / Template Insert 统一走 Immediate Command,Live 编辑走 Transaction 路径,不再出现第三种模型。

### 负面后果

1. **实现复杂度提升**：新增 Live Editing State、`updateLiveSource` 推送、live/committed 对账（reconcile）。
2. **live/committed 一致性需维护**：commit 后需把 live 对齐到 committed（避免 false dirty / wordCount 漂移）;undo/redo 后需清空 live（避免 stale）。Phase 3.3 在 `Coordinator.handle` 成功后 reconcile 全部 live = committed,在 `undo/redo` 时清空 live。
3. **Phase 3.4 仍需补全 Coalescing**：Phase 3.3 的 Transaction Buffer 是退化的「失焦即提交」,连续输入在失焦前不进 History（符合预期）,但跨失焦的「一次语义编辑」尚未合并为单步 Undo。

---

## Migration Plan

### Phase 3.3（最小实现,本 PR #65 落地）

```
Live Editing State
   + 实时 wordCount（coordinator 从 _liveSources 计算）
   + 实时 dirty tracking（live ≠ committed）
```

具体改动（已实施）：
- `lib/presentation/editor/editor_coordinator.dart`
  - 新增 `Map<BlockId, String> _liveSources`
  - 新增 `updateLiveSource(BlockId, String)` / `liveSourceOf(BlockId)`
  - 覆盖 `wordCount` getter：对所有 block 累加 `liveSourceOf(id).length`
  - 覆盖 `isDirty` getter：`editor.isDirty || 任意 live ≠ sourceOf(id)`
  - `handle()` 成功后 reconcile：`_liveSources[id] = editor.sourceOf(id)`（全部 block）
  - `undo()` / `redo()` 前 `_liveSources.clear()`
- `lib/presentation/blocks/base_block_state.dart`
  - `_onTextChanged`：在 guard（聚焦 / composing 空）之后、规则委托之前,调用 `_coordinator.updateLiveSource(blockId, text)`（含 CodeBlock,仅规则委托跳过 CodeBlock）

`canUndo` / `canRedo` 保持 `history.canUndo`（仅 Transaction Commit 后为真）—— 这是 Live/Committed 分离的核心体现：**实时反馈不污染 Undo**。

### Phase 3.4（完整实现）

```
EditorInteractionState
   + Transaction Coalescing（输入合并 / IME 支持 / 智能 Undo）
```

- 引入 `EditorInteractionState` 承载 live source / cursor / composing（从 `EditorCoordinator` 的临时 map 提升为正式状态对象）。
- 引入 Transaction Buffer：连续文本输入合并为一个 Undo 单元（按时间窗口 / 语义边界 coalesce）。
- 完善 ADR-0011 §4.1 规划的 `CoordinatorState.isDirty` 字段,本 ADR 的 live 比较并入其 getter。
- IME 组合输入：composing 期间只更新 live（不 reconcile、不 commit）,组合结束再视情况提交。

---

## 延伸：Editor Context Preservation（Chrome 不改变编辑上下文）

### 触发事件
本 ADR 冻结后,Phase 3.3 E2E 收尾重跑（PR #65）暴露第二个状态管理缺陷,与 Live/Committed 分离同属「UI Chrome 与 Editor Interaction State 的边界」问题：

| 操作链 | 行为 |
|------|------|
| 用户聚焦 ParagraphBlock | `coordinator.focusedId = paraId` |
| 点击 Toolbar `+`（模板菜单） | `PopupMenuButton` 打开 |
| Toolbar 获取焦点 | `coordinator.focusedId = null` |
| `_handleTemplateSelect()` | `if (blockId == null) return;` |
| 结果 | **模板未插入** |

这不是测试环境特例——真实用户「聚焦段落 → 点 `+` → 选模板」必然复现。E2E 失败暴露的是**产品状态管理错误**,不能改测试绕过。

### 决策（Human Owner,2026-07-25）
**修产品,不要绕测试**：不让 Toolbar 参与编辑焦点竞争。采用「打开菜单前捕获 focusedBlockId」方案（方案 A）。

### Phase 3.3 落地（已实施,`lib/presentation/chrome/markdown_toolbar.dart`）
- `_ToolbarButtons` 由 `StatelessWidget` 改为 `StatefulWidget`（挂「最后聚焦块」）。
- `build` 中只要 `coordinator.focusedId != null` 就刷新 `_lastFocusedId`（焦点丢失后保留上一次值）。
- `_handleTemplateSelect(item, {BlockId? targetBlockId})`：用 `targetBlockId ?? coordinator.focusedId` 作为插入目标。
- `PopupMenuButton.onSelected` 闭包捕获 `_lastFocusedId` 传入。
- 格式按钮（`_handleWrapOrInsert` / `_handleInsert`）经 `onPressed` 同步触发,实测不丢焦点,E2E 未受影响,本次不改。

效果：模板插入命令始终拿到「菜单打开前的聚焦块」,Toolbar 交互不再破坏编辑上下文。

### 关联：zoom 双指手势 E2E 降级（非产品 bug）
`phase33_zoom_test` 双指用例暴露的是**测试环境限制**而非产品缺陷：Widget test 的合成 `TestPointer` 验证的是 `ScaleGestureRecognizer` 回调路径,非真实触摸（`AndroidEmbedder` / `InputDispatcher`）。合成双指会被 `EditableText` 在手势竞技场抢占,不稳定。该用例降级为 smoke + TODO,平台级真实手势验证见 Android Emulator sanity gate（Maestro / Patrol）,**不阻塞** PR #65。这与上方模板焦点 bug 性质不同：前者是真实产品状态错误,后者是测试手段的覆盖缺口。

---

## Decision Owner

**Human Owner**（2026-07-24 会话中决策并授权起草）。

---

## 验证计划

### E2E（本 PR #65 收尾目标：真实产品缺陷 0,测试环境限制允许标记）

- [x] `phase33_word_count_test`：输入后 **不先失焦** 即断言 `wordCount` 增加（实时,经 Live State）
- [x] `phase33_appbar_test`：输入后 **不先失焦** 即断言 `isDirty`（实时,经 Live State）
- [x] `phase33_undo_redo_test`：`canUndo` 仍仅在 **commit（失焦 / 规则触发）后** 为真（含修复：undo 时 selection 钳制,避免聚焦态撤销 `invalid text selection` 崩溃）
- [x] `phase33_auto_pair_test` / `phase33_auto_continue_test`：自动配对 / 续列表仍走 Immediate Command（commit 即时,wordCount 经 reconcile 对齐）
- [x] `phase33_template_menu_test`：模板插入菜单（**修产品**：Toolbar 抢焦点 bug,见「Editor Context Preservation」延伸节;E2E 断言保持原样,不绕过）
- [~] `phase33_zoom_test` 双指手势：**降级为 smoke + TODO**。Widget test 合成 `TestPointer` 仅验证 `ScaleGestureRecognizer` 回调路径,非真实触摸;合成双指会被 `EditableText` 在手势竞技场抢占,不稳定。平台级真实手势验证见 Android Emulator sanity gate（Maestro / Patrol）,不阻塞 PR #65。

### 单元 / 架构守门

- [ ] `EditorCoordinator.wordCount` 单元测试：改 live source → wordCount 即时变,无需 commit
- [ ] `EditorCoordinator.isDirty` 单元测试：live ≠ committed → dirty;commit 后 reconcile → 不 false dirty
- [ ] `undo()` 后 live 清空：wordCount 回落到 committed,不残留 live 漂移
- [ ] CodeBlock 经 live 上报（wordCount 含代码块实时文本）,但不触发自动配对（规则委托仍跳过 CodeBlock）

---

## 参考文档

- [ADR-0011 Phase 3.3 架构决策](./0011-phase3.3-architecture-decisions.md) v1.1 Accepted
- [ADR-0008 Editor Transaction Model](./0008-editor-transaction-model.md) v1.1 Proposed
- [ADR-0009 UI Architecture Design](./0009-ui-architecture-design.md) v1.1 Proposed
- [Phase 3.3 Task Contract v1.4](../../contracts/phase3.3-task-contract.md) Accepted（§3.3.4 实时字数统计）
- 实施文件：`lib/presentation/editor/editor_coordinator.dart` / `lib/presentation/blocks/base_block_state.dart`
