/// EditorIntentDispatcher：输入意图派发器（ADR-0019 核心抽象）。
///
/// 所有输入事件统一入口：[dispatch] 先 flush live→domain（防 #4 文本复活），
/// 再交 [BlockBehaviorResolver] 解析为 [EditorCommand]，最后经
/// [EditorCoordinator.handle] 执行。焦点 / 选区由既有 [CommandSelectionSync]
/// 自动处理，dispatcher 不感知 UI。
library;

import '../../core/editing/block_types.dart';
import '../../data/models/document.dart';
import '../commands/editor_command.dart';
import 'block_behavior_resolver.dart';
import 'editor_intent.dart';

/// 编辑器输入意图派发器。
class EditorIntentDispatcher {
  final IntentCoordinator coordinator;
  final BlockBehaviorResolver resolver;

  EditorIntentDispatcher(
    this.coordinator, {
    BlockBehaviorResolver? resolver,
  }) : resolver = resolver ?? const BlockBehaviorResolver();

  /// 派发任意 [EditorIntent]。
  void dispatch(EditorIntent intent) {
    switch (intent) {
      case EnterPressedIntent i:
        _dispatchEnter(i);
      case DeleteIntent i:
        _dispatchDelete(i);
      case ToolbarActionIntent i:
        _dispatchToolbar(i);
      case InsertTemplateIntent i:
        _dispatchTemplate(i);
      case PasteIntent i:
        _dispatchPaste(i);
    }
  }

  void _dispatchEnter(EnterPressedIntent i) {
    flushLiveSource(i.blockId);
    final cmd = resolver.resolveEnter(coordinator, i.blockId, i.selection);
    if (cmd != null) coordinator.handle(cmd);
  }

  void _dispatchDelete(DeleteIntent i) {
    final sel = i.selection;
    final len = coordinator.sourceOf(i.blockId).length;
    final atBoundary = i.isBackspace
        ? sel.isCollapsed && sel.baseOffset == 0
        : sel.isCollapsed && sel.baseOffset >= len;
    if (!atBoundary) return; // 仅块边界触发合并
    flushLiveSource(i.blockId);
    final cmd = resolver.resolveBackspaceAtStart(coordinator, i.blockId);
    if (cmd != null) coordinator.handle(cmd);
  }

  void _dispatchToolbar(ToolbarActionIntent i) {
    flushLiveSource(i.blockId);
    final cmd = resolver.resolveToolbarAction(
      coordinator,
      i.blockId,
      i.kind,
      i.selection,
    );
    if (cmd != null) coordinator.handle(cmd);
  }

  void _dispatchPaste(PasteIntent i) {
    // Phase C：纯文本按换行拆分多块。
  }

  void _dispatchTemplate(InsertTemplateIntent i) {
    flushLiveSource(i.blockId);
    final cmd = resolver.resolveTemplateInsert(
      coordinator,
      i.blockId,
      i.template,
      i.mode,
      i.selection,
      i.cursorOffset,
    );
    if (cmd != null) coordinator.handle(cmd);
  }

  /// 将某 block 的 live 文本刷新为已提交 domain source（#4 工具栏复活修复）。
  ///
  /// 聚焦态打字只更新 live 层，domain 要到失焦才提交；工具栏格式命令在聚焦态
  /// 执行、命令处理器读的是 domain source。派发格式命令前调用本方法可对齐两者，
  /// 避免被删除的文本随旧 domain 复活。仅用 [IntentCoordinator] 公开能力。
  void flushLiveSource(BlockId id) {
    final live = coordinator.liveSourceOf(id);
    final domain = coordinator.sourceOf(id);
    if (live != domain) {
      coordinator.handle(UpdateBlockSourceCommand(blockId: id, newSource: live));
    }
  }

  /// 在文档末尾追加一个空段落块（#1 即点即插，AS-1.3）。
  ///
  /// 复用 [InsertBlockAfterCommand]；调用方（workspace 点击区）随后显式
  /// [EditorCoordinator.setFocus] 新块以进入编辑态（见 [CommandSelectionSync]
  /// 对 InsertBlockAfterCommand 的 default 分支不转移焦点，保留既有契约）。
  BlockId appendBlock() {
    final lastId = coordinator.allIds.last;
    coordinator.handle(InsertBlockAfterCommand(
      blockId: lastId,
      element: const ParagraphElement(children: [TextElement('')]),
    ));
    return coordinator.allIds.last;
  }
}
