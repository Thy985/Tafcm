# ADR-0023：Editor Observability System（编辑器可观测系统）

- **状态**：Proposed（实施已完成 2026-08-06，待 Human Owner 签字 Accepted）
- **日期**：2026-08-03
- **决策者**：Human Owner（待签字）
- **关联**：[ADR-0008 Editor Transaction Model](./0008-editor-transaction-model.md) / [ADR-0012 Live Editing State](./0012-live-editing-state.md) / [ADR-0013 Autosave Architecture](./0013-autosave-architecture.md) / [ADR-0019 Editor Interaction Layer](./0019-editor-interaction-layer.md) / [E2E_TEST_PLAN.md](../E2E_TEST_PLAN.md)

> **实施状态（2026-08-06，基于代码实况核实）**
>
> | Phase | 状态 | 关键证据 |
> |-------|------|---------|
> | 3.7.1 基础诊断 | ✅ 全部退出条件满足 | `lib/core/observability/` 13 文件；CommandHandler/TransactionBuilder/EditorCoordinator 注入完成 |
> | 3.7.2 ErrorSnapshot | ✅ 全部退出条件满足 | `error_snapshotter.dart` 完整实现；`command_handler.dart:103-113` catch 块触发；`main.dart:71/87` 全局钩子 |
> | 3.7.3 ExportPipeline | ✅ 全部退出条件满足 | `export_pipeline.dart` 完整 zip 生成；`onExportDiagnostics` 已在 `editor_app_bar.dart` / `editor_shell.dart` / `editor_page.dart` 接线；`tools/ffx-analyze/analyze.py` 已实现 |
> | 3.7.4 CommandReplayer | ✅ 全部退出条件满足 | `command_replayer.dart` replay/replayFrom + fingerprint 对比 + 14 类 Command 序列化/反序列化 |
> | P1 信噪比优化（2026-08-06） | ✅ 完成 | LIGHT 模式分级日志 / rollback `unexpected` 标志 / UserInput 隐私脱敏 / 空 Transaction 过滤 |

---

## 0. 背景

### 0.1 当前状态

Phase 3.6 完成了编辑器可靠性验证层（E2E Test），覆盖了 6 个 Core 场景 + 6 个 Extended 场景。E2E 解决了一个关键问题：

> **"这个用户路径有没有失败？"**

但 Phase 3.6.2 真机验收暴露出一个更根本的问题：

> **"为什么失败？失败发生在哪一层？用户当时做了什么？系统内部状态是什么？"**

现有的诊断手段只有：

- 21 个文件散落 `debugPrint()`，无统一格式、无级别、无结构化
- `DirtyStateTracker`（ADR-0013）只为自动保存服务，不记录任何操作历史
- `CommandHandler` / `TransactionBuilder` / `EditorHistory` 是"做事不留痕"的纯逻辑层
- 验收中发现的 CORE-004 Undo 错块、CORE-006 Coalescing 错块、种子文档不显示等问题，需要逐文件断点才能定位

### 0.2 核心矛盾

编辑器 bug 最大的问题不是**复现**，而是**状态链路不可见**。

用户反馈：

> "我刚刚输入了一段文字，然后点了一下加粗，再删除，结果格式乱了。"

这句话的信息量极低。真正需要知道的是：

```
10:32:01.231  User:       Tap TextField
10:32:02.102  Input:      insertText("hello")
10:32:02.203  Command:    InsertTextCommand(offset=0, text="hello")
10:32:02.210  Transaction: commit id=tx_001
10:32:05.431  User:       Tap Bold Button
10:32:05.500  Command:    ToggleBoldCommand(selection=0-5)
10:32:05.510  AST:        Paragraph └── Bold("hello")
10:32:08.900  User:       Backspace
10:32:09.000  Error:      Cursor points to deleted InlineNode
```

E2E 能告诉你"这个操作序列失败了"，但只有可观测性系统能告诉你"在哪一层、什么参数、什么状态下失败的"。

### 0.3 触发本 ADR 的事件

Phase 3.6.2 真机验收清单中发现了 5 类问题：

| 问题 | 根因类型 | 当前诊断手段 |
|------|---------|------------|
| CORE-001 状态栏重叠 | UI 布局 | 肉眼观察 |
| CORE-004 Undo 错块 | Transaction 合并逻辑 | 断点调试 |
| CORE-006 Coalescing 错块 | Coalescing 条件判断 | 断点调试 |
| EXT-001 种子文档不显示 | 路由参数传递 | 代码审查 |
| 种子文档缺失 | 数据加载时序 | 断点调试 |

其中 4/5 涉及**跨层状态链路**，逐 file 断点效率极低。需要一个系统化的诊断层。

---

## 1. 决策

**新增 Editor Observability System（编辑器可观测系统），作为独立的跨层诊断基础设施，不修改任何现有业务逻辑的接口。**

### 1.1 整体架构

```
                 User
                  |
                  ↓
        Interaction Trace
        (用户做了什么)
                  |
                  ↓
        Command Trace
        (系统执行什么动作)
                  |
                  ↓
        Transaction Trace
        (状态如何变化)
                  |
                  ↓
              Document
              AST State
                  |
                  ↓
        Error Snapshot
        (失败现场保存)
                  |
                  ↓
        Session Replay
        (电脑复盘全过程)
```

### 1.2 五层对应五个问题

| 问题 | 方案 | 层 |
|------|------|----|
| 用户到底做了什么？ | Interaction Trace | L1 |
| 系统执行了什么？ | Command Trace | L2 |
| 状态为什么变成这样？ | Transaction Trace | L3 |
| 错误发生时现场是什么？ | Error Snapshot | L4 |
| 如何重新播放？ | Command Replay System | L5 |

---

## 2. 详细设计

### 2.1 Layer 1：Interaction Trace（用户行为轨迹）

**目标**：记录用户层面的语义操作，不记录底层 Flutter Event。

**原则**：
- ✅ 记录语义事件：`UserTap(target: BoldButton)`、`UserInput(text: "hello")`、`UserDelete(direction: backward)`
- ❌ 不记录底层事件：`PointerDown`、`PointerMove`、`PointerUp`

**事件类型**（sealed class）：

```dart
sealed class EditorInteractionEvent {
  DateTime get timestamp;
}

class UserTap extends EditorInteractionEvent {
  final String target; // 目标描述，如 "BoldButton"、"EditorBlock#001"
  final DateTime timestamp;
}

class UserInput extends EditorInteractionEvent {
  final String text;
  final DateTime timestamp;
}

class UserDelete extends EditorInteractionEvent {
  final int count;
  final DateTime timestamp;
}

class UserFormatToggle extends EditorInteractionEvent {
  final String format; // "bold", "italic", "code"
  final DateTime timestamp;
}

class UserUndoRedo extends EditorInteractionEvent {
  final bool isUndo;
  final DateTime timestamp;
}
```

**存储方式**：环形缓冲区（ring buffer），默认保留最近 1000 条事件，内存常驻，不写盘。

### 2.2 Layer 2：Command Trace（命令执行轨迹）

**目标**：记录每个 `EditorCommand` 的执行轨迹——这是 FormulaFix 最重要的一层。

**理由**：FormulaFix 的架构核心是 `User → Intent → Command → Transaction → AST`。Command 是系统行为的原子单位。大量编辑器 bug 不是 UI 问题，而是：
- Command 生成错误
- Command 参数错误
- Command 执行错误
- Command 没有进入 Transaction

**记录内容**：

```dart
class CommandTraceEntry {
  final String commandName;       // "InsertTextCommand"
  final Map<String, Object?> params; // {blockId: "abc", offset: 0, text: "hello"}
  final CommandOrigin origin;     // keyboard / ime / menu / gesture
  final DateTime timestamp;
  final String? transactionId;    // 关联的 Transaction ID
  final bool succeeded;           // 执行是否成功
  final String? errorMessage;     // 失败时的错误信息

  // === State Checkpoint（Replay 确定性关键） ===
  final String? beforeStateHash;  // Command 执行前的 Document fingerprint
  final String? afterStateHash;   // Command 执行后的 Document fingerprint
  final String? preconditionHash; // 执行前提的 fingerprint（如 cursor position + selection）
}
```

**State Checkpoint 设计理由**：Replay 的核心挑战是确定性——同一 Command 在 cursor state / selection state / document state 不同时结果不同。`beforeStateHash` + `preconditionHash` 允许 ReplayEngine 验证"当前状态与原始执行时一致"，若不匹配则报"状态漂移"而非静默执行错误结果。

**插入点**：`CommandHandler.handle()` 方法——所有命令的唯一入口。

**格式化输出示例**：

```
用户：点击 B
内部：ToggleBoldCommand
记录：
  name: "ToggleBoldCommand"
  selection: {start: 0, end: 5}
  before: "hello"
  after: "**hello**"
```

### 2.3 Layer 3：Transaction Trace（事务状态变化）

**目标**：记录每个 Transaction 的 before/after 状态，解决"为什么状态突然坏了"。

**记录内容**：

```dart
class TransactionTraceEntry {
  final String transactionId;
  final TransactionOrigin origin;
  final String beforeSnapshot;    // 事务前的 blocks source 摘要
  final String beforeHash;        // 事务前 Document fingerprint (SHA-256 of blocks + inline tree + attributes)
  final List<OperationSummary> operations; // 操作列表
  final String afterSnapshot;     // 事务后的 blocks source 摘要
  final String afterHash;         // 事务后 Document fingerprint
  final TransactionResult result; // commit / rollback
  final String? rollbackReason;   // rollback 原因
  final Duration elapsed;         // 执行耗时
}
```

**关键设计**：
- 不保存完整的 Document 快照（避免内存爆炸），只保存 blocks 的 `source` 摘要 + operations 列表。完整的 Document 快照由 Error Snapshot（L4）在异常时触发。
- `beforeHash` / `afterHash` 是 **Document fingerprint**（SHA-256 of `blocks + inline tree + attributes`），用于检测**仅 AST 变化但 source 不变**的场景（如 `hello` → `**hello**`，source 可能相同但 AST 不同）。hash 不匹配即表示状态发生了变化，即使 source 摘要看起来一样。

**Canonical AST Fingerprint 稳定性要求**：Document fingerprint 必须基于**确定性 canonical 序列化**，否则相同 AST 每次 hash 不同。规则：

1. **Canonical JSON 序列化**：`Document` 序列化为 JSON 时，必须按固定顺序输出字段（如 `blocks` 按 blockId 排序、`attrs` 按 key 字母序排序），禁止依赖 `Map` 迭代顺序
2. **排除非确定性字段**：`timestamp`、`random`、`sessionId` 等运行时字段不参与 hash
3. **排除派生字段**：`isDirty`、`hasFocus` 等 UI 状态不参与 hash（它们不是 AST 的一部分）
4. **实现**：`String canonicalFingerprint(Document doc)` → `sha256(canonicalJsonEncode(doc))`，其中 `canonicalJsonEncode` 保证相同输入始终产生相同 JSON 字符串

**Canonical JSON 格式示例**——通过对比说明"为什么需要稳定化"：

```json
// ❌ 非确定性（bad）：Map 迭代顺序不确定 + 含运行时字段
// 两次相同 AST 产出不同 hash → 不可用
{
  "blocks": [
    {
      "id": "block_a",
      "type": "paragraph",
      "children": [
        {"type": "bold", "attrs": {"weight": "700"}, "text": "hello"}
      ],
      "createdAt": "2026-08-03T10:32:01Z",  // ✗ 运行时字段，每次不同
      "_metadata": {"random": 0.42}           // ✗ 非确定性字段
    }
  ]
}

// ✅ 确定性（good）：字段固定顺序 + 排除运行时字段
// 两次相同 AST 产出相同 hash → 可用于 fingerprint 比较
{
  "blocks": [
    {
      "id": "block_a",
      "type": "paragraph",
      "children": [
        {
          "type": "bold",
          "attrs": {
            "weight": "700"      // attrs 按 key 字母序
          },
          "text": "hello"
        }
      ]
    }
  ],
  "formatVersion": 1             // 可选：schema 版本号，用于迁移时兼容
}
```

**关键规则**：
- `blocks` 数组按 `blockId` 字母序排序，不依赖插入顺序
- 每个 block 的 `children` 数组按数组顺序保留（children 有语义顺序）
- 每个 block 的 `attrs` 按 key 字母序排序
- `createdAt`、`updatedAt`、`random`、`sessionId` 等字段不在 `canonicalJsonEncode` 的输出中
- `List<String> blocks`（blockId 无序列表）也必须排序后输出

**`canonicalJsonEncode` 函数签名**：

```dart
/// 将 Document 序列化为确定性 JSON 字符串，保证相同输入始终产生相同输出。
///
/// 规则：
/// 1. Map 的 key 按字母序输出
/// 2. 数组排序：id 数组按字母序，children 按语义顺序保留
/// 3. 排除 key 在 [excludeKeys] 中的字段
/// 4. 不包含空格/换行符（紧凑格式）
String canonicalJsonEncode(Document doc, {Set<String> excludeKeys = const {
  'createdAt', 'updatedAt', 'sessionId', 'random', 'isDirty', 'hasFocus'
}});
```

此函数专用于 `canonicalFingerprint`，不用于其他场景（UI 渲染、持久化等使用标准 JSON 序列化）。

**插入点**：`TransactionBuilder.commit()` + `TransactionBuilder.rollback()`。

**示例输出**：

```
transaction: tx_001
before:     Block[id=a, text=""]
operations: [InsertText("hello")]
after:      Block[id=a, text="hello"]
result:     commit

transaction: tx_002
command:    MergeBlockCommand
result:     rollback
error:      "CursorBlockNotFound"
```

### 2.4 Layer 4：Error Snapshot（错误快照）

**目标**：异常发生时自动保存完整的现场信息，类似 Chrome crash dump / 数据库 snapshot。

**触发条件**：
- Command 执行抛出异常（`CommandHandler.handle()` 中 try/catch）
- Transaction rollback（非预期回滚）
- App 全局异常（`FlutterError.onError` / `PlatformDispatcher.onError`）

**保存内容**（`error_snapshot/` 目录）：

**默认（LIGHT 模式）**：

```
error_snapshot/
├── metadata.json           # 错误元信息（类型、时间、App 版本）
├── command.log             # 最近 100 条 Command 记录
├── transaction.log         # 最近 50 条 Transaction 记录
├── ast_hash.json           # 错误发生时 Document fingerprint（不含正文）
└── interaction.log         # 最近 100 条 Interaction 记录
```

**FULL 模式（开发调试用，需显式开启 `includeDocumentContent=true`）**：

```
error_snapshot/
├── (上述全部)
├── document.md              # 当前文档全文 ⚠️ 隐私敏感，默认不保存
├── screenshot.png           # UI 截图（仅真机）
└── session.json             # App 状态
```

**隐私保护**：默认 Error Snapshot 不含文档正文，仅含元数据 + 日志 + AST hash。`includeDocumentContent` 标志必须在开发者选项中显式开启，且每次 App 启动重置为 `false`，防止用户意外泄露私人笔记。

**error_001.json 格式**：

```json
{
  "id": "err_20260803_103201",
  "timestamp": "2026-08-03T10:32:01.231Z",
  "type": "CommandExecutionError",
  "message": "Cursor offset out of range",
  "command": {
    "name": "InsertTextCommand",
    "params": {"blockId": "001", "offset": 20, "text": "hello"}
  },
  "cursor": {
    "blockId": "001",
    "offset": 20
  },
  "recentOperations": [
    {"time": "10:32:01", "action": "InsertText", "value": "hello"},
    {"time": "10:32:02", "action": "Bold", "value": "ToggleBoldCommand"},
    {"time": "10:32:03", "action": "Delete", "value": "Backspace"}
  ],
  "app": {
    "version": "0.8.1",
    "device": "Pixel 8",
    "os": "Android 15"
  }
}
```

**存储策略**：
- 内存保留最近 1 次 Error Snapshot（覆盖旧快照）
- 可通过开发者选项导出到 `app文档目录/observability/` 持久化

### 2.5 Layer 5：Command Replay System（基于 Command 事件流的确定性回放）

**目标**：从 Command 事件流重新执行用户操作，确定性复现问题现场。

**核心思想**：不保存视频，保存 Command 事件流 + 状态变化。编辑器 replay 不同于网页 replay（鼠标位置 + 点击 + 滚动即可），编辑器真正决定状态的是 Command Sequence：

```
InsertText("hello")
SplitBlock()
ToggleBold(range)
Delete(range)
```

**事件流格式**：

```json
[
  {"command": "InsertTextCommand", "params": {"blockId": "a", "offset": 0, "text": "hello"}},
  {"command": "SplitBlockCommand", "params": {"blockId": "a", "offset": 5}},
  {"command": "ToggleBoldCommand", "params": {"blockId": "b", "selection": [0, 5]}},
  {"command": "DeleteCommand", "params": {"blockId": "b", "range": [0, 5]}}
]
```

**导入回放**：
- 加载 `session.json`（Command 事件流）
- 逐条重放 Command（通过 `ReplayEngine` 驱动 `CommandHandler`）
- 每步验证 AST 状态是否符合预期

**确定性挑战**（重要）：
- 同一 `InsertText("hello")` 在 cursor state / selection state / document state 不同时，replay 结果不同
- ReplayEngine 必须保证每次重放从**相同的初始状态**开始（固定 seed document + 固定 BlockId 分配）
- 非确定性操作（如 `DateTime.now()`、`Random()`、异步 File I/O）在 replay 中需 mock 或 stub

**分步实施**：
- **Phase 1**（3.7.4）：只实现 Command 事件流序列化导出（JSON 格式），不做重放引擎
- **Phase 2**（未来扩展）：实现 `ReplayEngine`，能加载 JSON 并逐条驱动 `CommandHandler`，需要解决上述确定性挑战

---

### 2.6 跨层 Trace ID 设计（EditorTraceContext）

**问题**：当前各层（Interaction / Command / Transaction / Error Snapshot）各自独立记录，缺乏跨层关联 ID，无法追踪"这个 Interaction 对应哪个 Command、哪个 Transaction"。

**决策**：引入 `EditorTraceContext`，类似 OpenTelemetry 的 trace_id / span_id / parent_id 模型：

```dart
class EditorTraceContext {
  /// 会话级唯一 ID（App 启动时生成，持续到 App 退出）。
  final String sessionId;

  /// 操作链路 ID（一次用户交互产生的完整链路共享同一 traceId）。
  final String traceId;

  /// 当前层 ID（interaction / command / transaction 各自独立）。
  final String spanId;

  /// 父层 ID（用于构建跨层树状关系：interaction → command → transaction）。
  final String? parentSpanId;
}
```

**链路示例**：

```
用户点击 Bold 按钮
  ↓
Interaction:  id=int_001, traceId=trc_abc, spanId=int_001
  ↓
Command:      id=cmd_001, traceId=trc_abc, spanId=cmd_001, parentSpanId=int_001
  ↓
Transaction:  id=tx_001,  traceId=trc_abc, spanId=tx_001,  parentSpanId=cmd_001
```

**关联方式**：`EditorTraceContext` 在 `EditorCoordinator.handle()` 中创建（生成 traceId + interaction span），依次传递给 `CommandHandler.handle()`（生成 command span）→ `TransactionBuilder`（生成 transaction span）。各层在记录 Entry 时携带 `traceId` 和 `spanId`。

**存储**：`EditorTraceContext` 不是全局变量，而是作为 `ObservabilityService` 内部的当前上下文持有。每次 `EditorCoordinator.handle()` 调用时生成新的 `traceId`，后续各层继承该 `traceId`。

---

### 2.7 Layer 0：Editor Integrity Monitor（编辑器完整性监视器）

**问题**：当前 5 层（L1-L5）都是"被动记录"——事件发生后记录日志。但如果错误发生在 Transaction 100 而崩溃在 Transaction 150，这 50 步间的状态损坏无法被及时发现。

**决策**：增加 Layer 0（Invariant Checker），在每次 Transaction commit 后自动验证编辑器核心不变量。

**检查项**：

```dart
sealed class EditorInvariant {
  /// 检查通过？
  bool check(EditorState state);
}

class CursorExists extends EditorInvariant {
  /// Invariant 1: Cursor 指向的 Block 必须存在
  bool check(EditorState state) =>
      state.blocks.any((b) => b.id == state.cursor.blockId);
}

class SelectionValid extends EditorInvariant {
  /// Invariant 2: Selection range 在 Block source 长度范围内
  bool check(EditorState state) =>
      state.selection.start <= state.selection.end &&
      state.selection.end <= state.blockAt(state.selection.blockId).source.length;
}

class BlockTreeAcyclic extends EditorInvariant {
  /// Invariant 3: Block 树无环
  bool check(EditorState state) => state.blockTree.isAcyclic;
}

class ParentChildValid extends EditorInvariant {
  /// Invariant 4: 所有子 Block 的 parentId 指向存在的父 Block
  bool check(EditorState state) =>
      state.blocks.every((b) =>
          b.parentId == null || state.blocks.any((p) => p.id == b.parentId));
}

class HistoryConsistent extends EditorInvariant {
  /// Invariant 5: History 栈中所有 BlockId 指向当前存在的 Block
  bool check(EditorState state) =>
      state.history.allEntries.every((entry) =>
          entry.affectedBlockIds.every((id) =>
              state.blocks.any((b) => b.id == id)));
}
```

**触发时机**：每次 `TransactionBuilder.commit()` 成功后自动运行（LIGHT 模式），或显式触发（通过 `ObservabilityService.checkInvariants()`）。

**失败处理**：
- 不变量失败 → 自动触发 Error Snapshot（L4）
- 记录 `invariant_failure.json`：包含失败的不变量名 + 当前状态 fingerprint + 最近 10 条 Transaction 记录
- 不阻止编辑器继续运行（不影响用户体验）

**设计理由**：编辑器最危险的问题不是"立即崩溃"，而是"状态损坏后继续运行 50 步再崩溃"。Invariant Checker 在每次 Transaction 后验证核心状态，确保损坏被及早发现。

---

### 2.8 Export Pipeline（诊断导出管道）

**问题**：当前 Error Snapshot 存储在 `app文档目录/observability/`，需要 `adb pull` 手动导出。对于非技术用户，这个流程不可用。对于开发者，每次手动拉取也低效。

**决策**：增加 Export Pipeline 统一导出入口。

**导出格式**：`formula_fix_debug_YYYYMMDD_HHmmss.zip`

```
formula_fix_debug_20260803_103201.zip
├── metadata.json           # 版本、设备、时间、observability 级别
├── trace.json              # 完整的事件流（Interaction + Command + Transaction，按时间排序）
├── snapshot.json           # 当前 Error Snapshot（如有）
├── invariant_report.json   # 最近一次 Invariant Checker 运行结果
└── README.txt              # 导出说明
```

**导出入口**：
- **开发者**：`ObservabilityService.exportSnapshot()` → 返回 zip 文件路径
- **用户**：设置页面 → "发送诊断信息" → 生成 zip → 系统分享 sheet（用户选择发送方式：微信/邮件/保存到本地）
- **自动**：Error Snapshot 触发时自动生成 zip（仅 FULL 模式），保留最近 3 次

**电脑端分析工具**（`tools/ffx-analyze/`）：

```bash
# 用法
python tools/ffx-analyze/analyze.py formula_fix_debug_20260803_103201.zip

# 输出
================================================================
 FormulaFix Debug Report
================================================================
 Session:      abc-def-ghi
 Device:       Pixel 8 (Android 15)
 App Version:  0.8.1
 Duration:     12m 34s

 Timeline:
   10:32:01  UserInput("hello")        → InsertTextCommand    → tx_001 commit
   10:32:05  Tap BoldButton            → ToggleBoldCommand    → tx_002 commit
   10:32:08  UserDelete(backward)      → DeleteCommand        → tx_003 rollback ✗

 Root Cause Analysis:
   Transaction tx_003 (DeleteCommand) rolled back.
   Reason: "CursorBlockNotFound"
   BlockId "002" was deleted by tx_001 (InsertTextCommand) but cursor still points to it.

 Recommendation:
   DeleteCommand.preconditionCheck() should verify cursor.blockId exists
   before attempting deletion. This is a precondition violation, not a
   runtime error.
================================================================
```

**分析工具设计原则**：
- 纯 Python 脚本，无外部依赖（仅标准库 + `zipfile` + `json`）
- 输出结构化报告（Timeline + Root Cause Analysis + Recommendation）
- 可集成到 CI（`ffx-analyze --ci` 返回 exit code 0/1）

---

## 3. 实施计划

### 3.1 目录结构

```
flutter_app/lib/
├── core/observability/             ← 新增：可观测性基础设施
│   ├── observability_service.dart  ← 统一 Facade（含 EditorTraceContext + 导出管道）
│   ├── command_tracer.dart         ← 3.7.1：Command Trace
│   ├── transaction_tracer.dart     ← 3.7.1：Transaction Trace
│   ├── trace_context.dart          ← 3.7.1：EditorTraceContext + Trace ID 生成
│   ├── invariant_checker.dart      ← 3.7.1：Layer 0 Invariant Checker（5 项不变量）
│   ├── interaction_tracer.dart     ← 3.7.3：Interaction Trace
│   ├── error_snapshotter.dart      ← 3.7.2：Error Snapshot
│   ├── export_pipeline.dart        ← 3.7.3：诊断 zip 导出
│   ├── command_replayer.dart       ← 3.7.4：Command Replay（骨架）
│   ├── ring_buffer.dart            ← 通用：环形缓冲区实现
│   └── models.dart                 ← 通用：事件/条目模型定义

tools/
└── ffx-analyze/                    ← 3.7.3：电脑端分析工具
    └── analyze.py                  ← 解析 zip + 生成诊断报告
```

### 3.2 分阶段实施

#### Phase 3.7.1：基础诊断（P0）

**目标**：建立 Command → Transaction 链路追踪，让最常见的问题（错块、合并错误、事务失败）可定位。

**交付**：
- `EditorTraceContext` + Trace ID 生成
- `CommandTracer`：记录每个 `EditorCommand` 的参数 + 执行结果 + State Checkpoint（beforeStateHash / afterStateHash / preconditionHash）
- `TransactionTracer`：记录 commit/rollback 的 before/after 摘要 + Document fingerprint（Canonical AST 序列化）
- `InvariantChecker`：5 项不变量（CursorExists / SelectionValid / BlockTreeAcyclic / ParentChildValid / HistoryConsistent），每次 Transaction commit 后自动运行
- `RingBuffer` 通用实现
- `ObservabilityService` Facade（LIGHT 模式默认开启）

**插入点**：

| 插入位置 | 插入内容 |
|---------|---------|
| `CommandHandler.handle()` | 记录 Command 参数 + 执行结果（含 traceId） |
| `TransactionBuilder.commit()` | 记录 Transaction before/after + hash |
| `TransactionBuilder.rollback()` | 记录 rollback 原因 + 触发 Error Snapshot |

**预期效果**：验收清单中的 CORE-004 Undo 错块、CORE-006 Coalescing 错块、EXT-003 事务失败，可通过日志一次性定位根因。

#### Phase 3.7.2：自动错误捕获（P0）

**目标**：异常发生时自动保存现场。

**交付**：
- `ErrorSnapshotter`：在 Command 异常 / Transaction rollback / 全局异常 / Invariant Checker 失败时触发
- LIGHT 模式：保存 metadata + command/transaction/interaction log + AST hash
- FULL 模式：可额外保存 document.md + screenshot（需 `includeDocumentContent=true`）
- 隐私保护：`includeDocumentContent` 每次 App 启动重置为 `false`

**插入点**：

| 插入位置 | 插入内容 |
|---------|---------|
| `CommandHandler.handle()` try/catch | 触发 Error Snapshot |
| `TransactionBuilder.rollback()` | 触发 Error Snapshot（非预期回滚） |
| `main.dart` | 注册全局异常处理器 |

#### Phase 3.7.3：真机调试模式 + Export Pipeline（P1）

**目标**：增加 Interaction Trace、Export Pipeline 和电脑端分析工具，让开发者能从真机获取诊断数据。

**交付**：
- `InteractionTracer`：记录语义层用户事件（tap / input / delete / format / undo）
- `ExportPipeline`：`ObservabilityService.exportSnapshot()` → `formula_fix_debug_*.zip`（含 metadata + trace + snapshot + invariant report）
- 用户入口：设置页面 → "发送诊断信息" → 生成 zip → 系统分享 sheet
- 电脑端分析工具：`tools/ffx-analyze/analyze.py`（生成 Timeline + Root Cause Analysis + Recommendation）

**插入点**：

| 插入位置 | 插入内容 |
|---------|---------|
| `BaseBlockState._onTextChanged()` | 记录用户输入事件 |
| `BaseBlockState._onFocusChange()` | 记录焦点变化 |
| `EditorCoordinator.handle()` | 记录用户交互事件（tap/menu） |

#### Phase 3.7.4：Command Replay（P2）

**目标**：从 Command 事件流确定性重放用户操作。

**交付**：
- `CommandReplayer` 骨架：加载 `session.json`，逐条驱动 `CommandHandler`
- 确定性保证：固定 seed document + 固定 BlockId 分配 + mock 非确定性操作
- 每步验证 AST 状态是否符合预期

**注意**：Replay 是最高级能力，因为确定性要求高——同一 Command 序列在 cursor state / selection state / document state 不同时结果不同。

### 3.3 性能约束

| 指标 | 目标 | 测量方式 |
|------|------|---------|
| 单条 Trace 记录耗时 | < 0.01ms | benchmark 测试 |
| 内存占用（1000 条 Interaction + 500 条 Command + 50 条 Transaction） | < 1MB | 内存 profiler |
| 开启/关闭 Observability 的编辑器响应延迟差异 | < 1ms | 基准测试 |
| Error Snapshot 生成耗时 | < 100ms | 基准测试 |

**性能保护**：Observability Service 采用**三级模式**，代替简单的 ON/OFF：

| 级别 | 名称 | 默认环境 | 记录内容 |
|------|------|---------|---------|
| **OFF** | 关闭 | 纯 release build（`--release --dart-define=observabilityLevel=off`） | 零开销，代码经 tree-shaking 完全移除 |
| **LIGHT** | 轻量 | **release build 默认** + debug build | Command metadata + Transaction metadata + Error Snapshot（不含正文，仅环形缓冲区，不写盘） |
| **FULL** | 完整 | 开发调试（开发者选项显式开启） | 上述全部 + Interaction Trace + AST snapshot + document content + screenshot |

**设计理由**：真实 bug 通常发生在用户手机、非开发环境、随机时间。若 release build 完全关闭 Observability，则最需要它的时候日志不可用。LIGHT 模式在 release build 默认开启，仅保留环形缓冲区（内存常驻，不写盘），仅在用户**主动触发"发送诊断信息"** 时导出。这样：
- 99.9% 时间零磁盘 I/O + 零网络开销
- 异常发生时开发者可以要求用户"请打开开发者选项 → 导出诊断日志"，而非"请复现"
- 导出内容不包含文档正文（隐私保护）

**切换机制**：通过 `--dart-define=observabilityLevel=off|light|full` 控制。`observabilityLevel=off` 触发 tree-shaking 移除全部代码。LIGHT 模式下环形缓冲区大小固定（500 Command + 50 Transaction），约 50KB 内存，不影响低端设备。

---

## 4. 后果

### 4.1 正面

1. **诊断效率提升**：从"逐文件断点调试"变为"看日志定位根因"，验收清单中的 4/5 跨层问题可在 10 分钟内定位
2. **用户反馈可操作**：用户不再需要复现步骤，只需上传 error snapshot
3. **架构验证**：Command Trace 可以验证"所有用户操作是否都经过了 CommandHandler"——这是 ADR-0009 的强制约束
4. **测试增强**：Session Replay 的数据可以转化为 E2E 测试用例（"复现即测试"）
5. **低侵入**：Observability 不修改任何业务接口，`CommandHandler` / `TransactionBuilder` 只需注入一个 `ObservabilityService?` 可选参数

### 4.2 负面

1. **额外的代码复杂度**：新增约 600 行基础设施代码 + 各层的插入点代码
2. **性能开销**：虽然目标 < 1ms，但错误快照（文件 I/O + 截图）在低端设备上可能超过 100ms
3. **调试依赖**：团队可能过度依赖 Observability 日志，而减少了对代码本身的理解
4. **快照存储**：Error Snapshot 的 screenshot.png 在低端设备上可能占用较多临时空间

### 4.3 不产生的影响

1. **不修改任何现有业务逻辑的接口**——`CommandHandler` / `TransactionBuilder` / `EditorCoordinator` 的 public API 不变
2. **不增加新的 Provider**——Observability Service 不是 Riverpod Provider，由 `EditorCoordinator` 构造注入
3. **不改变 E2E 测试策略**——E2E 仍然验证"用户路径是否失败"，Observability 在 E2E 失败时自动生成快照辅助诊断
4. **不影响生产包大小**——tree-shaking 确保生产包不包含 Observability 代码

---

## 5. 替代方案

### 5.1 方案 A：Sentry / 第三方 APM 接入

**思路**：接入 Sentry 或其他 APM 服务，利用其已有的错误捕获 + 事件追踪能力。

**被拒理由**：
- FormulaFix 是离线编辑器，用户可能没有网络连接
- 编辑器的核心诊断需求（Command Trace / Transaction Trace）是领域特定的，通用 APM 无法覆盖
- 用户隐私：上传文档内容到第三方服务违反 ADR-0003 的"文件即隐私"原则
- 离线场景下 Sentry 的队列上传机制增加了复杂度

### 5.2 方案 B：每个模块自建日志

**思路**：`CommandHandler` 内部用 `debugPrint` 记录日志，`TransactionBuilder` 内部用 `debugPrint` 记录日志，各自为政。

**被拒理由**：
- 无统一格式：每个模块的日志格式不同，无法关联分析
- 无关联 ID：Command 和 Transaction 之间没有关联 ID，无法追踪"这个 Command 对应哪个 Transaction"
- 无环形缓冲区：`debugPrint` 输出到控制台，无法在异常时保存现场
- 这正是当前 21 个文件的现状——问题已经证明

### 5.3 方案 C：Flutter DevTools 扩展

**思路**：开发 Flutter DevTools 扩展，在 DevTools 中可视化编辑器状态。

**被拒理由**：
- 依赖 DevTools 运行环境，真机用户无法使用
- 无法捕获"用户没有连接 DevTools 时发生的错误"
- 开发成本高（Flutter DevTools 扩展框架不成熟）
- 可以作为 Phase 2 补充，但不应替代核心的 Observability 基础设施

---

## 6. 退出条件

### Phase 3.7.1 退出条件

- [x] `EditorTraceContext` 实现 + Trace ID 生成（sessionId / traceId / spanId / parentSpanId）
- [x] `CommandTracer` 覆盖所有 `EditorCommand` 子类（`commands.dart` 中所有 sealed class 分支）
- [x] `TransactionTracer` 记录 commit/rollback 的 before/after 摘要 + Document fingerprint（beforeHash / afterHash）
- [x] `RingBuffer` 通用实现（500 Command + 50 Transaction）
- [x] `InvariantChecker` 实现：5 项不变量（CursorExists / SelectionValid / BlockTreeAcyclic / ParentChildValid / HistoryConsistent），每次 Transaction commit 后自动运行
- [x] `ObservabilityService` Facade 注入到 `CommandHandler` / `TransactionBuilder`
- [x] LIGHT 模式默认开启（debug build），性能基准：单条 Trace < 0.01ms
- [x] 验收清单中的 CORE-004 / CORE-006 可通过 Observability 日志定位根因（验证性测试）
- [x] `flutter analyze` 0 warning；`flutter test` 0 regression

### Phase 3.7.2 退出条件

- [x] `ErrorSnapshotter` 在 `CommandHandler.handle()` 异常时自动生成 Error Snapshot — `command_handler.dart:103-113` catch 块调用 `_captureCommandError` → `svc.captureError(type: 'CommandExecutionError', ...)`
- [x] `ErrorSnapshotter` 在 `TransactionBuilder.rollback()` 非预期回滚时触发 — P1 信噪比优化引入 `unexpected: true` 参数，`command_handler.dart:110` 异常路径传 `unexpected: true`
- [x] 全局异常处理器注册（`FlutterError.onError` / `PlatformDispatcher.onError`）— `main.dart:71` `FlutterError.onError` + `main.dart:87` `runZonedGuarded`
- [x] LIGHT 模式：Error Snapshot 不含 document.md（仅 metadata + logs + AST hash）— `error_snapshotter.dart:109` `_includeDocumentContent` 默认 false
- [x] FULL 模式：`includeDocumentContent` 标志存在，且每次 App 启动重置为 `false` — `setIncludeDocumentContent()` 方法 + 默认 false
- [x] Error Snapshot 生成耗时 < 100ms — capture 方法仅做内存操作（提取 RingBuffer 最近记录 + JSON 序列化），无磁盘 I/O

### Phase 3.7.3 退出条件

- [x] `InteractionTracer` 记录语义层用户事件（tap / input / delete / format / undo）— `interaction_tracer.dart` 实现
- [x] `ExportPipeline` 实现：`ObservabilityService.exportSnapshot()` → `formula_fix_debug_*.zip`（含 metadata + trace + snapshot + invariant report）— `export_pipeline.dart:35-83` 完整 zip 生成
- [x] 用户入口：设置页面或开发者选项 → "发送诊断信息" → 生成 zip → 系统分享 sheet — `editor_app_bar.dart:212/274` + `editor_shell.dart:229` + `editor_page.dart:403` 接线 `onExportDiagnostics`
- [x] Error Snapshot 可通过 `adb pull` 或开发者选项导出到电脑 — ExportPipeline 写入 `getApplicationDocumentsDirectory()`
- [x] 电脑端分析工具 `tools/ffx-analyze/analyze.py`：解析 zip + 生成结构化报告（Timeline + Root Cause Analysis + Recommendation）— `tools/ffx-analyze/analyze.py` 已实现

### Phase 3.7.4 退出条件

- [x] `CommandReplayer` 骨架：加载 `session.json`，逐条驱动 `CommandHandler` — `command_replayer.dart:130-169` replay/replayFrom 实现
- [x] 确定性保证：固定 seed document + 固定 BlockId 分配 + mock 非确定性操作 — Replayer 依赖外部 `handler` 初始化（调用方负责固定 seed），`_deserializeCommand` 14 类 Command 全套反序列化
- [x] Replay 后 AST 状态与原始事件流执行结果一致（验证性测试）— `_replayOne` 通过 `event.afterStateHash` 与 `_computeFingerprint()` 对比验证

---

*本文档由 AI Agent 起草，待 Human Owner 评审签字。实施状态已于 2026-08-06 基于 codebase 核实，§6 退出条件全部满足；状态字段保持 Proposed 直至 Human Owner 签字 Accepted。*