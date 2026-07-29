/// EditorIntent：编辑器输入意图（Editing Intent Layer 入口抽象）。
///
/// 落地 ADR-0019 + Human Owner Phase 3.5 评审：所有输入事件（回车 / 退格 /
/// 工具栏 / 粘贴）先构造为 [EditorIntent] 子类，再经
/// [EditorIntentDispatcher.dispatch] 统一派发。UI 层禁止直接
/// `coordinator.handle(SplitBlockCommand(...))`（TC-ARCH-EDITOR-1），必须经
/// Intent → [BlockBehaviorResolver] → Command。
library;

import 'package:flutter/painting.dart' show TextSelection;

import '../../core/editing/block_types.dart';
import '../../data/models/document.dart';
import '../commands/editor_command.dart';

/// 派发所需的协调器能力（抽象，避免 dispatcher ↔ coordinator 导入环）。
///
/// [EditorCoordinator] 实现本接口；[BlockBehaviorResolver] / [EditorIntentDispatcher]
/// 仅依赖本接口，不依赖具体 coordinator 类，从而打破导入环（否则 Dart 循环导入
/// 会使 [EditorIntentDispatcher] 类型无法解析）。接口仅声明公开能力，
/// 具体实现（flush / append）下沉到 [EditorIntentDispatcher]。
abstract class IntentCoordinator {
  /// 执行命令（返回是否成功）。
  bool handle(EditorCommand command);

  /// 块的源元素（集中裁决读取，resolver 由此推导 [BlockType]）。
  DocumentElement? getBlock(BlockId id);

  /// 块 source 文本（[BlockType] / 长度推导用）。
  String sourceOf(BlockId id);

  /// 块实时文本（live 优先，flush 比对用）。
  String liveSourceOf(BlockId id);

  /// 文档块 id 列表。
  List<BlockId> get allIds;

  /// 文档块数量。
  int get blockCount;

  /// 聚焦块选区（§2.7.1 强一致读取）。
  TextSelection? get focusedSelection;

  /// 聚焦块是否有非空选区。
  bool get hasSelection;
}

/// 编辑器输入意图（纯数据，不含执行逻辑）。
sealed class EditorIntent {
  /// 目标块 ID。
  final BlockId blockId;
  const EditorIntent(this.blockId);
}

/// 软键盘 / 物理回车。
///
/// 由 [BaseBlockState] 的多行 [TextField] 输入拦截器捕获插入的 `\n` 后派发，
/// 或由桌面 RawKeyEvent 的 Enter 派发。不再依赖 `onSubmitted`（多行字段真机不触发）。
final class EnterPressedIntent extends EditorIntent {
  /// 回车时光标处的选区（[TextSelection.isCollapsed] = 单光标点）。
  final TextSelection selection;
  const EnterPressedIntent(super.blockId, this.selection);
}

/// 块边界删除（退格 / Delete 键）。
///
/// 仅当光标位于块首（退格）或块尾（Delete）时由 [BaseBlockState] 派发，
/// resolver 决定是否合并（规范 §4.1）。
final class DeleteIntent extends EditorIntent {
  /// true = 退格（块首）；false = Delete 键（块尾）。
  final bool isBackspace;
  final TextSelection selection;
  const DeleteIntent(super.blockId, this.isBackspace, this.selection);
}

/// 工具栏语义动作（用户层封装，底层 Markdown）。
///
/// 一级（高频固定）：[bold] / [italic] / [h1] / [code]；
/// 二级（⋯ 收纳）：[h2] / [h3] / [link] / [quote] / [ol] / [ul] / [task]。
enum ToolbarActionKind {
  bold,
  italic,
  code,
  link,
  h1,
  h2,
  h3,
  quote,
  ol,
  ul,
  task;
}

/// 工具栏按钮点击意图。
final class ToolbarActionIntent extends EditorIntent {
  final ToolbarActionKind kind;
  final TextSelection selection;
  const ToolbarActionIntent(super.blockId, this.kind, this.selection);
}

/// 粘贴意图（Phase C：纯文本按换行拆分多块）。
final class PasteIntent extends EditorIntent {
  final String text;
  final TextSelection selection;
  const PasteIntent(super.blockId, this.text, this.selection);
}
