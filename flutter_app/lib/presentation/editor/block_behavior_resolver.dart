/// BlockBehaviorResolver：Intent → Command 的唯一裁决点（ADR-0019 + Human Owner 评审）。
///
/// **架构铁律**：禁止在 Block 子类写 per-block 行为方法（如
/// `ParagraphBlock.onEnter()` / `CodeBlock.onEnter()`）。所有"回车 / 退格 / 工具栏"
/// 的行为映射集中在本类的 `switch` 中。未来新增 Table / MathBlock / Callout /
/// Image Caption，只需在对应 `resolve*` 方法的 `switch` 增加分支，
/// 无需改动任何 Block 组件 —— 这正是集中裁决相比 per-block 写法的核心价值。
library;

import 'package:flutter/painting.dart' show TextSelection;

import '../../core/editing/block_types.dart';
import '../commands/editor_command.dart';
import 'editor_intent.dart';

/// Block 行为解析器（无状态，纯函数式，便于单测）。
class BlockBehaviorResolver {
  const BlockBehaviorResolver();

  /// 回车意图 → Command（Enter 矩阵，规范 §3）。
  ///
  /// 决策原则：Enter 产生"当前块类型的兄弟单元"；仅 Code 块内换行、
  /// 空列表 / 引用退出时例外（后者 Phase B）。
  EditorCommand? resolveEnter(
    IntentCoordinator c,
    BlockId id,
    TextSelection sel,
  ) {
    final element = c.getBlock(id);
    if (element == null) return null;
    final type = BlockType.fromElement(element);
    switch (type) {
      case BlockType.paragraph:
      case BlockType.heading:
        // 光标处拆出新兄弟块（标题回车落为段落）。
        return SplitBlockCommand(blockId: id, offset: sel.baseOffset);
      case BlockType.code:
        // 代码块内换行，不分块（底层 Markdown 保留 \n）。
        return InsertTextCommand(
          blockId: id,
          text: '\n',
          cursorOffset: 0,
          selection: sel,
        );
      case BlockType.listItem:
      case BlockType.taskListItem:
      case BlockType.blockquote:
      // Phase B：列表续项 / 引用续行；Phase A 暂退化为分块以保持可用。
      case BlockType.table:
      case BlockType.mermaid:
      case BlockType.horizontalRule:
        return SplitBlockCommand(blockId: id, offset: sel.baseOffset);
    }
  }

  /// 块首退格 → Command（§4.1）。
  EditorCommand? resolveBackspaceAtStart(IntentCoordinator c, BlockId id) {
    final element = c.getBlock(id);
    if (element == null) return null;
    final type = BlockType.fromElement(element);
    switch (type) {
      case BlockType.paragraph:
      case BlockType.heading:
        return MergeWithPreviousCommand(blockId: id);
      case BlockType.listItem:
      case BlockType.taskListItem:
      case BlockType.blockquote:
        // Phase B：先退出列表 / 引用标记；Phase A 退化为合并。
        return MergeWithPreviousCommand(blockId: id);
      case BlockType.code:
      case BlockType.table:
      case BlockType.mermaid:
      case BlockType.horizontalRule:
        return null; // 首块 / 不可合并类型不处理
    }
  }

  /// 工具栏动作 → Command（§4.4）。用户语义 → 底层 Markdown。
  EditorCommand? resolveToolbarAction(
    IntentCoordinator c,
    BlockId id,
    ToolbarActionKind kind,
    TextSelection sel,
  ) {
    final hasSelection = sel.baseOffset != sel.extentOffset;
    switch (kind) {
      case ToolbarActionKind.bold:
        return _wrap(id, sel, hasSelection, '**', '**', '****', -2);
      case ToolbarActionKind.italic:
        return _wrap(id, sel, hasSelection, '*', '*', '**', -1);
      case ToolbarActionKind.code:
        return _wrap(id, sel, hasSelection, '`', '`', '``', -1);
      case ToolbarActionKind.link:
        return _wrap(id, sel, hasSelection, '[', ']()', '[]()', -3);
      case ToolbarActionKind.h1:
        return _prefix(id, sel, '# ');
      case ToolbarActionKind.h2:
        return _prefix(id, sel, '## ');
      case ToolbarActionKind.h3:
        return _prefix(id, sel, '### ');
      case ToolbarActionKind.quote:
        return _prefix(id, sel, '> ');
      case ToolbarActionKind.ol:
        return _prefix(id, sel, '1. ');
      case ToolbarActionKind.ul:
        return _prefix(id, sel, '- ');
      case ToolbarActionKind.task:
        return _prefix(id, sel, '- [ ] ');
    }
  }

  EditorCommand _wrap(
    BlockId id,
    TextSelection sel,
    bool hasSelection,
    String prefix,
    String suffix,
    String noSel,
    int cursorOffset,
  ) =>
      hasSelection
          ? WrapSelectionCommand(
              blockId: id,
              prefix: prefix,
              suffix: suffix,
              selection: sel,
            )
          : InsertTextCommand(
              blockId: id,
              text: noSel,
              cursorOffset: cursorOffset,
              selection: sel,
            );

  EditorCommand _prefix(BlockId id, TextSelection sel, String text) =>
      InsertTextCommand(
        blockId: id,
        text: text,
        cursorOffset: 0,
        selection: sel,
      );
}
