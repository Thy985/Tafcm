# Editor Interaction Specification（编辑交互规范）

> **状态**：Proposed（随本规范提交，Human Owner 签字即成为编辑器内核实现依据）
> **版本**：v1.0（2026-07-29）
> **作者**：AI 协作开发者（基于 Human Owner Phase 3.5 真机评审结论）
> **关联**：ADR-0018（App Shell 导航/数据流）· ADR-0012（Live Editing State）· 真机问题报告 `phase3.5-realdevice-issues.md`（#1/#3/#4/#5）

---

## 0. 为什么需要本规范

Phase 3.5 真机测试暴露的不是"块设计失败"，而是 **编辑器内核缺失"输入意图层（Editing Intent Layer）"**：

- Document Model（块结构）✅ 已落地
- Rendering（渲染）✅ 已落地
- **Editing Intent（输入 → 行为映射）❌ 缺失**

后果（真机实测）：

1. **回车不知道干什么**——`onSubmitted` 接 `SplitBlockCommand`，但多行 `TextField` 的软键盘回车插入 `\n` 且**不触发 `onSubmitted`**，真机上回车只是往同一块塞换行（问题 #1）。
2. **格式按钮读旧状态**——工具栏命令未先 flush live，删掉的文本随格式"复活"（问题 #4）。
3. **块工具条像外挂**——每块常驻上/下移/删除，单块时全禁用，无语意（问题 #3）。
4. **工具栏按钮不可达**——OL/UL/Task/+ 横向溢出无提示（问题 #5）。

本规范定义：**所有输入事件先过 Intent 层，再按 block 类型映射到 Command**。补的是缺失的第三层，而非推翻 Block Model。

**架构铁律（Human Owner 评审补充）**：Intent → Command 的映射**必须集中在单一 `BlockBehaviorResolver`**，禁止在各 Block 子类写 `ParagraphBlock.onEnter()` / `CodeBlock.onEnter()` 这类 per-block 行为方法。原因：未来新增 Table / MathBlock / Callout / Image Caption 时，per-block 写法需改遍每个 Block 类；集中 resolver 只需在其 `switch` 增加一个分支。统一入口为 `EditorIntentDispatcher.dispatch(Intent)`（由 `EditorCoordinator` 暴露），Enter / 工具栏 / 退格 / 粘贴全部走这一条路，杜绝在 `_enter()` / `_toolbar()` / `_backspace()` 三处各修一遍。

> **核心结论（Human Owner）**：分块不是错的，但"把所有回车都变成分块"是错的。回车只是"创建兄弟块"的一种触发，应受 block 类型约束。

---

## 1. 三层模型

```
┌─────────────────────────────────────────────┐
│ Document Model  (blocks[], Block{id,type,    │  ✅ 已落地
│                  source,metadata})           │
├─────────────────────────────────────────────┤
│ Editing Intent  (Raw Event → Intent →        │  ❌ 本次补
│                  BlockBehavior → Command)    │
├─────────────────────────────────────────────┤
│ Rendering       (edit/rendered 双态)         │  ✅ 已落地
└─────────────────────────────────────────────┘
```

输入事件**禁止直接操作 Command**，必须先经 Intent 层。Intent 层是新抽象 `EditorIntentDispatcher`（由 `EditorCoordinator` 提供 `dispatch(Intent)` 入口），替换当前散落在 `base_block_state.dart` / `markdown_toolbar.dart` 的 ad-hoc 处理。其中 **Intent → Command 的映射集中在 `BlockBehaviorResolver`**（单一 `switch(blockType)`），**禁止在 Block 子类写 `ParagraphBlock.onEnter()` 这类 per-block 行为方法**——否则未来新增 Table / MathBlock / Callout 需改遍每个 Block 类。

---

## 2. 输入事件 → Intent 映射

| 原始事件 | Intent | 触发源 |
|---|---|---|
| 软键盘回车（插入 `\n`）/ 物理 Enter | `EnterPressedIntent` | TextField 内换行输入 |
| 光标在块首且 Backspace（无选区/选区在起点） | `BackspaceAtStartIntent` | onChanged 检测 |
| 光标在块尾且 Delete 键 | `DeleteAtEndIntent` | RawKeyEvent |
| Tab 键 | `TabPressedIntent` | RawKeyEvent（Phase C） |
| 行首输入 `# ` / `- ` / `> ` / ```` ``` ```` 等 | `MarkdownShortcutIntent` | onChanged 检测 |
| 工具栏按钮点击 | `ToolbarActionIntent(kind)` | markdown_toolbar |
| 粘贴 | `PasteIntent` | 粘贴回调（Phase C） |

**硬规则**：

- `composing` 态（IME 组合输入中）不触发任何 Intent（沿用 ADR-0012 / §2.1.1）。
- 软键盘回车**必须**在输入层拦截（见 §4 实现注），不得依赖 `onSubmitted`（多行字段 `onSubmitted` 在真机不触发——这是 P0 修复翻车根因）。

---

## 3. Enter 行为矩阵（核心）

回车 ≠ 无脑分块。按当前块类型决定行为：

| Block 类型 | Enter 行为 | Command | 备注 |
|---|---|---|---|
| Paragraph | 光标处拆出新 Paragraph | `SplitBlockCommand` | 默认兄弟块 |
| Heading (H1–H3) | 拆出 Paragraph（标题后接普通段） | `SplitBlockCommand` | 标题回车后落为段落 |
| Code | **块内换行**，不分块 | `InsertNewLineCommand`（非 Split） | 代码块允许多行 |
| List item | 续出下一个同类型 List item | `InsertNewLineWithPrefixCommand`（同块续行）/ `CreateNextListItemCommand`（TODO，逐 item 块） | 保持 `- `/`1. ` 标记 |
| 空 List item + Enter | **退出列表** → Paragraph | `ExitListCommand`（TODO） | 避免"空白段落" |
| Quote | 续出下一行 Quote（保持 `> ` 前缀） | `InsertNewLineWithPrefixCommand` | |
| 空 Quote + Enter | **退出引用** → Paragraph | `ExitQuoteCommand`（TODO） | |

决策原则：**Enter 产生"当前块类型的兄弟单元"**，仅当 Code 块内换行、或空列表/引用项退出时例外。

---

## 4. 其他关键行为

### 4.1 Backspace 在块首
- 与上一块合并：`MergeWithPreviousCommand`。
- 规则：Paragraph + Heading 合并结果为 Paragraph；首块不合并（保持原样）。
- 列表项在块首 Backspace：退出列表标记变 Paragraph（与 merge 协同）。

### 4.2 Delete 在块尾
- 与下一块合并（TODO，`MergeWithNextCommand`）。

### 4.3 Markdown 快捷输入
- 行首 `# `→ `TransformBlockCommand(heading1)`；`## `→ heading2；`### `→ heading3。
- `- `/`* `/`+ space`→ 无序列表；`1. `→ 有序列表；`[] `/`[ ] `/`[x] `→ 任务项。
- `> `→ 引用；```` ``` ````→ 代码块。
- 已存在 `TransformBlockCommand` 可复用。

### 4.4 Toolbar 动作（用户层语义封装，底层 Markdown）
| 按钮 | 语义操作 | Command |
|---|---|---|
| B / I / Code | 包裹选区 | `WrapSelectionCommand` |
| H1–H3 | 转标题 | `TransformBlockCommand` |
| OL / UL / Task | 行首前缀 / 转列表 | 前缀插入 / `TransformBlockCommand` |
| Quote | 行首 `> ` 前缀 | 前缀插入 |
| Link | 包裹为 `[text](url)` | `WrapSelectionCommand`（url 模板） |
| + 模板 | 插入块模板 | `InsertTemplateCommand` |

原则：**用户想"要标题/要粗体"，不手写 Markdown 语法**（移动端效率）。

### 4.5 Paste
- 纯文本粘贴按换行拆分为多块（Phase C，TODO）。

---

## 5. Live/Domain 同步硬规则（呼应问题 #4）

- **所有 Command 派发前必须 `coordinator.flushLiveSource(blockId)`**：live 文本先对齐 domain，命令处理器只读 domain 状态。
- 禁止在 live 未 flush 时构造 `WrapSelectionCommand` / `InsertTextCommand`（这正是 #4"复活已删文本"根因）。
- `flushLiveSource` 已实现于 `EditorCoordinator`（P0 临时补丁的可复用资产，纳入本规范）。

---

## 6. 视觉模型（呼应问题 #3）

- **默认文档流，无每块明显边框**。边界仅在 hover / focus / 长按 时显示。
- 块级操作（上移/下移/删除）= **长按触发**，非常驻；单块或全禁用态整条隐藏。
- 此条覆盖原 #3 修复方向，并消除"右上角无用工具条遮视线"。

---

## 7. 工具栏布局（呼应问题 #5，移动端两级）

手机可视宽度约 393px，无法平铺桌面全按钮。采用两级：

- **一级（高频固定，始终可见）**：`B` `I` `H`（标题）`Code` `+`（模板）。
- **二级（`⋯` 溢出菜单收纳）**：`H2` `H3` `Link` `Quote` `OL` `UL` `Task`。

所有按钮经 `ToolbarActionIntent` 走 `EditorIntentDispatcher`（§4.4 + ADR-0019）。补手机视口 golden 覆盖全按钮（含 `⋯` 内项）。

---

## 8. 与已推送 `fix/editor-kernel` 的关系

- `fix/editor-kernel` 的 `_handleEnter` 接 `onSubmitted` 是**错误层（真机死代码）**，**不按现状合并**。
- 其 `flushLiveSource` 与 `command_selection_sync` 的 `SplitBlockCommand` / `InsertBlockAfterCommand` focus case 是**可复用资产**，纳入 §4/§5 实现。
- `realdevice_p0_test.dart` 中"命令层分块"测试保留（验证 Split 逻辑），但"回车分块"验收改为真机软键盘 E2E（见 §9）。

---

## 9. 验收标准（须真机回归）

> **关键教训**：P0 用模拟器 `receiveAction(TextInputAction.done)` 验证回车**不可靠**（`onSubmitted` 不触发）。回车类验收**必须在真机软键盘**跑，模拟器仅作辅助。

| 编号 | 行为 | 方法 | 标准 |
|---|---|---|---|
| AS-I.1 | 段落回车分块 | 真机软键盘：输入文字→回车 | 产生 ≥2 块，光标落新块（AS-1.1/1.2） |
| AS-I.2 | 点空白追加块 | 真机/模拟器：点视口尾部空白 | 末尾插入空 Paragraph 并聚焦（AS-1.3） |
| AS-I.3 | 上块失焦渲染 | 真机：输入后切走焦点 | 原块进入 rendered 态（AS-1.4/1.5） |
| AS-I.4 | Code 块回车换行不分块 | 真机：代码块内回车 | 仍在同一 Code 块，插入 `\n` |
| AS-I.5 | 列表回车续项 | 真机：`- 苹果` 回车 | 续出 `- ` 新项，非空白段 |
| AS-I.6 | 空列表项回车退出 | 真机：空 `- ` 回车 | 变 Paragraph，退出列表 |
| AS-I.7 | 块首 Backspace 合并 | 真机：块首退格 | 与上一块合并（MergeWithPrevious） |
| AS-I.8 | 工具栏格式不复活 | 真机：删字→点 B | 渲染 `**abf**`，无已删文本复活（AS-4.4） |
| AS-I.9 | 块工具条不常驻 | 真机：单块 | 无上/下移/删除常驻条；长按才出 |
| AS-I.10 | 工具栏全按钮可达 | 真机窄屏 | 全部按钮可触达 |

---

## 10. 实现分期

- **Phase A（P0 内核，重排）**：
  - **P0-1（先行）**：建立 `EditorIntentDispatcher` + `BlockBehaviorResolver`（唯一裁决点），所有输入事件统一经 `dispatch(Intent)`；删除 `onSubmitted` 错误路径（§8）。
  - **P0-2**：Enter 矩阵（Paragraph/Heading → Split；Code → 块内换行）经 dispatcher 落地；软键盘 `\n` 由 `TextField` 的 `TextInputFormatter` 拦截（真机正确通路，替换 `onSubmitted`）。
  - **P0-3**：Backspace 块首合并经 dispatcher（§4.1），焦点移到连接点。
  - **P0-4**：ToolbarActionIntent 经 dispatcher；**两级工具栏**（一级 B/I/H/Code/+，二级 ⋯ 收纳 H2/H3/Link/Quote/OL/UL/Task）。
  - 含 §5 flush 硬规则。
- **Phase B（P1）**：List/Quote 续行与退出（§3 TODO）、Markdown shortcut（§4.3）、ToolbarAction 全映射（§4.4）、视觉去边框（§6）、工具栏可见性（§7）。
- **Phase C（P2）**：Tab 缩进、Delete 合并、Paste 分块。

---

## 11. 被否决方案

| 方案 | 理由 |
|---|---|
| 继续在 `onSubmitted` 接 `SplitBlockCommand` | 多行 TextField 软键盘回车不触发 `onSubmitted`，真机死代码（P0 已翻车） |
| 在 `onChanged` 检测 `\n` 无脑 split | 无 block 类型判断，Code/List/Quote 全部错乱，灾难 |
| 取消 Block，退回单 TextField | 违背 Block Model 设计，丧失语义单元与 WYSIWYG 目标 |
| 工具栏让用户手写 `#`/`**` | 移动端效率低，违背语义操作原则（§4.4） |
| 在 Block 子类写 `onEnter()`/`onBackspace()` 等 per-block 行为方法 | 未来新增 Table/MathBlock/Callout 需改遍每个 Block 类；集中 `BlockBehaviorResolver.switch` 才是唯一裁决点 |
| 工具栏全按钮平铺（桌面布局搬移动端） | 手机 393px 宽度无法承载，必须两级（§7） |
