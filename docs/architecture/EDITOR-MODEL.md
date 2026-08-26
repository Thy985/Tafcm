# Editor Model（编辑模型）

**定位（L2 架构真相）**：当前编辑系统的数据流与状态模型——只讲"现在是什么"，
"为什么这么设计"见 [ADR-0008](../decisions/ADR/0008-editor-transaction-model.md) /
[ADR-0012](../decisions/ADR/0012-live-editing-state.md)（均需复审，见 A-001）。

## 数据流

```
Markdown
   ↓
Parser（手写，AST 驱动，lib/core/parser/markdown_parser.dart）
   ↓
Document AST（sealed DocumentElement，lib/data/models/document.dart）
   ↓
Live / Committed 双状态（ADR-0012：live_editing_state.dart）
   ↓
Transaction（操作日志 / commit-rollback / coalescing，ADR-0008）
   ↓
History（Undo/Redo，editor_history.dart）
   ↓
Renderer（Block → Widget）
```

## 关键组件

| 组件 | 文件 | 职责 |
|------|------|------|
| `MarkdownParser` | `lib/core/parser/markdown_parser.dart` | 文本 → Document AST（容错 + fuzz 守护） |
| `DocumentElement` | `lib/data/models/document.dart` | sealed AST（含 ListElement.nested，ADR-0029） |
| `LiveEditingState` | `lib/presentation/editor/live_editing_state.dart` | live source/cursor/composing |
| `TransactionBuilder` | `lib/core/editing/transaction_builder.dart` | 操作日志 + commit-rollback |
| `EditorHistory` | `lib/core/editing/editor_history.dart` | undo/redo + coalescing 规则 |

## 已知张力（A-001 复审范围）

- Live/Committed 分离与 Undo / Coalescing / Focus / Selection 的张力（DEBT-014）
- IME Transaction Coalescing 未实现（DEBT-006）
- 空 Transaction 守卫已以 no-op 实现（DEBT-005）

详见 [ENGINEERING-BASELINE](../engineering/ENGINEERING-BASELINE.md) DEBT 表。
