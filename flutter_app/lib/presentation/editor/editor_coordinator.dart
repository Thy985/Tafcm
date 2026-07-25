/// EditorCoordinator：UI 层对编辑内核的协调器（Phase 3.0 production 路径）。
/// 落地 ADR-0009 §3.5 + Phase 3.0 §2.4（避免 God Object）+ ADR-0012（Live State）。
/// 职责：持有 editor / history / handler，管理 [CoordinatorState]，只协调不持有业务状态。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show TextSelection;
import '../../core/editing/block_types.dart';
import '../../core/editing/editor_history.dart';
import '../../core/editing/transaction.dart';
import '../../data/models/document.dart';
import '../commands/command_handler.dart';
import '../commands/editor_command.dart';
import '../states/block_view_state.dart';
import '../states/coordinator_state.dart';
import 'command_selection_sync.dart';
import 'in_memory_document_editor.dart';
import 'live_editing_state.dart';

/// UI 层对编辑内核的协调器。Widget 通过 [EditorScope] 获取实例。
class EditorCoordinator extends ChangeNotifier {
  final InMemoryDocumentEditor editor;
  final EditorHistory history;
  late final CommandHandler handler;
  CoordinatorState _state;

  /// ADR-0012：Live Editing State（实时文本 / 字数 / 脏标记）。抽出独立类避免膨胀。
  late final LiveEditingState _live;

  /// ADR-0012 §Editor Context Preservation：最后聚焦的编辑块。不随 [clearFocus] 清空，
  /// chrome 层（模板菜单等）以它为编辑目标，避免焦点被弹层抢走后目标为 null。
  BlockId? _lastFocusedId;

  EditorCoordinator({
    required this.editor,
    required this.history,
  }) : _state = const CoordinatorState.empty() {
    handler = CommandHandler(editor: editor, history: history);
    _live = LiveEditingState(editor);
    _state = CoordinatorState.initial({
      for (final id in editor.allIds) id: BlockViewState(id: id),
    });
  }

  // ============ Command 入口 ============

  /// 处理 [EditorCommand]（成功后同步 selection 到 [BlockViewState]）。
  /// oldSource 捕获：cursorOffset 计算需要插入前的 source 长度（tryTransform 可能改变序列化结果）。
  bool handle(EditorCommand command) {
    final (oldSource, oldIds) = switch (command) {
      InsertTextCommand c => (editor.sourceOf(c.blockId), null),
      InsertTemplateCommand c when c.mode == TemplateInsertMode.insert =>
        (editor.sourceOf(c.blockId), null),
      InsertTemplateCommand c when c.mode == TemplateInsertMode.newBlock =>
        (null, editor.allIds.toSet()),
      InsertNewLineWithPrefixCommand c => (editor.sourceOf(c.blockId), null),
      _ => (null, null),
    };
    final ok = handler.handle(command);
    if (ok) {
      // 命令后 selection / focus 计算委托 [CommandSelectionSync]（R1+R2 + PR #2C）。
      final result = CommandSelectionSync.apply(_state, command,
          editor: editor, oldSource: oldSource, oldIds: oldIds);
      _state = result.state;
      if (result.newFocus != null) _lastFocusedId = result.newFocus;
      _live.reconcile(result.affectedIds); // 受影响块对齐到 committed
      notifyListeners();
    }
    return ok;
  }

  // ============ 查询接口（转发到 editor） ============

  int get blockCount => editor.blockCount;
  List<BlockId> get allIds => editor.allIds;
  DocumentElement? getBlock(BlockId id) => editor.getBlock(id);
  String sourceOf(BlockId id) => editor.sourceOf(id);

  // ============ Phase 3.3 chrome 接线（ADR-0012：Live / Committed 双状态）============

  String get title => editor.title;

  /// 实时字数 / 脏标记（ADR-0012 Live Editing State，委托 [LiveEditingState]）。
  int get wordCount => _live.wordCount;
  bool get isDirty => _live.isDirty;

  void markSaved() {
    editor.markSaved();
    _live.clear(); // ADR-0012：保存即已提交,清除 live 漂移,dirty 归 false。
    notifyListeners();
  }

  // ============ ADR-0012：Live Editing State 接口（委托）============

  /// 推入某 block 的实时编辑文本（由 `BaseBlockState._onTextChanged` 高频调用）。
  void updateLiveSource(BlockId id, String source) {
    _live.update(id, source);
    notifyListeners();
  }

  /// 读取某 block 的实时文本（live 优先,fallback 到已提交 source）。
  String liveSourceOf(BlockId id) => _live.sourceOf(id);

  // ============ Phase 3.3 PR #2B: Toolbar 便捷查询 ============

  /// 聚焦块的 [BlockType]（null = 无聚焦,§2.8 CodeBlock 禁用工具栏）。
  BlockType? get focusedBlockType {
    final id = _state.focusedId;
    if (id == null) return null;
    final element = editor.getBlock(id);
    return element == null ? null : BlockType.fromElement(element);
  }

  /// 聚焦块是否为 CodeBlock（消除 Toolbar 对 core/editing/ 的依赖）。
  bool get isFocusedOnCodeBlock => focusedBlockType == BlockType.code;
  /// 聚焦块的 selection（§2.7.1 强一致读取,Toolbar 用此值）。
  TextSelection? get focusedSelection => _state.focusedSelection;
  bool get hasSelection => _state.hasSelection;

  // ============ UI 视图状态（Hard Rule 1：AST 零污染）============

  BlockViewState? viewStateOf(BlockId id) => _state.viewStateOf(id);

  /// 更新指定块的 [BlockViewState],触发 [notifyListeners]。
  void updateViewState(BlockId id, BlockViewState state) {
    _state = _state.updateViewState(id, state);
    notifyListeners();
  }

  BlockId? get focusedId => _state.focusedId;

  /// 最后聚焦的编辑块（ADR-0012 §Editor Context Preservation）：实时聚焦优先，
  /// 失焦后回退到 [_lastFocusedId]（不被 [clearFocus] 清空）。chrome 层以此为编辑目标。
  BlockId? get lastFocusedId => _state.focusedId ?? _lastFocusedId;

  /// 聚焦指定块。旧块切回渲染态,新块切到编辑态。
  void setFocus(BlockId id) {
    if (_state.focusedId == id) return;
    _state = _state.focusOn(id);
    _lastFocusedId = id;
    notifyListeners();
  }

  /// 清除指定块的焦点（切回渲染态）。
  void clearFocus(BlockId id) {
    final next = _state.clearFocusOf(id);
    if (identical(next, _state)) return;
    _state = next;
    notifyListeners();
  }

  // ============ Undo / Redo ============
  // 修复（Phase 3.3）：[HistoryManager] 为快照交换模型，旧实现传空占位事务导致
  // redo 重放空 ops 无效。现回环真实事务（lastOrNull / redoLastOrNull）携带可重放 ops。

  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  /// Undo：回滚栈顶事务的 ops，并把同一事务回环压入 redo 栈。
  Transaction? undo() {
    final target = history.lastOrNull;
    if (target == null) return null;
    final tx = history.undo(target);
    if (tx == null) return null;
    _live.clear();
    for (final op in tx.ops.reversed) {
      op.revert(editor);
    }
    _syncViewStates();
    notifyListeners();
    return tx;
  }

  /// Redo：重放 redo 栈顶事务的 ops，并把同一事务回环压回 undo 栈。
  Transaction? redo() {
    final target = history.redoLastOrNull;
    if (target == null) return null;
    final tx = history.redo(target);
    if (tx == null) return null;
    _live.clear();
    for (final op in tx.ops) {
      op.apply(editor);
    }
    _syncViewStates();
    notifyListeners();
    return tx;
  }

  void _syncViewStates() => _state = _state.syncViewStates(editor.allIds);

  @override
  String toString() => 'EditorCoordinator(blocks=$blockCount, focused=${_state.focusedId})';
}
