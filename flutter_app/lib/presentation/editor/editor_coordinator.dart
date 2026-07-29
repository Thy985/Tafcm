/// EditorCoordinator：UI 层对编辑内核的协调器（Phase 3.0 production 路径）。
/// 落地 ADR-0009 §3.5 + Phase 3.0 §2.4（避免 God Object）+ ADR-0012（Live State）
/// + ADR-0013（实现 DirtyStateSource，委托 DirtyStateTracker）。只协调不持有业务状态。
library;

import 'dart:async';

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
import 'dirty_state_source.dart';
import 'editor_intent.dart';
import 'editor_intent_dispatcher.dart';
import 'in_memory_document_editor.dart';
import 'live_editing_state.dart';

/// UI 层对编辑内核的协调器（ADR-0009/0012/0013）。
class EditorCoordinator extends ChangeNotifier
    implements DirtyStateSource, IntentCoordinator {
  final InMemoryDocumentEditor editor;
  final EditorHistory history;
  late final CommandHandler handler;
  CoordinatorState _state;

  /// ADR-0012：Live Editing State（实时文本 / 字数 / 脏标记），抽出独立类避免膨胀。
  late final LiveEditingState _live;

  /// ADR-0012 §Editor Context Preservation：最后聚焦的编辑块，不随 [clearFocus] 清空。
  BlockId? _lastFocusedId;

  late final DirtyStateTracker _dirty;

  EditorCoordinator({
    required this.editor,
    required this.history,
  }) : _state = const CoordinatorState.empty() {
    handler = CommandHandler(editor: editor, history: history);
    _live = LiveEditingState(editor);
    _dirty = DirtyStateTracker(() => _live.isDirty);
    _intentDispatcher = EditorIntentDispatcher(this);
    _state = CoordinatorState.initial({
      for (final id in editor.allIds) id: BlockViewState(id: id),
    });
  }

  bool handle(EditorCommand command) {
    final (oldSource, oldIds) = switch (command) {
      InsertTextCommand c => (editor.sourceOf(c.blockId), null),
      InsertTemplateCommand c when c.mode == TemplateInsertMode.insert =>
        (editor.sourceOf(c.blockId), null),
      InsertTemplateCommand c when c.mode == TemplateInsertMode.newBlock =>
        (null, editor.allIds.toSet()),
      InsertNewLineWithPrefixCommand c => (editor.sourceOf(c.blockId), null),
      InsertBlockAfterCommand c => (editor.sourceOf(c.blockId), editor.allIds.toSet()),
      MergeWithPreviousCommand c => (null, editor.allIds.toSet()),
      _ => (null, null),
    };
    final ok = handler.handle(command);
    if (ok) {
      final result = CommandSelectionSync.apply(_state, command,
          editor: editor, oldSource: oldSource, oldIds: oldIds);
      _state = result.state;
      if (result.newFocus != null) _lastFocusedId = result.newFocus;
      _live.reconcile(result.affectedIds); // 受影响块对齐到 committed
      notifyListeners();
    }
    return ok;
  }

  int get blockCount => editor.blockCount;
  List<BlockId> get allIds => editor.allIds;
  DocumentElement? getBlock(BlockId id) => editor.getBlock(id);
  String sourceOf(BlockId id) => editor.sourceOf(id);

  /// ADR-0019：输入意图派发器。UI 事件统一经此 flush→resolve→handle。
  late final EditorIntentDispatcher _intentDispatcher;

  EditorIntentDispatcher get intents => _intentDispatcher;

  String get title => editor.title;

  int get wordCount => _live.wordCount;
  @override
  bool get isDirty => _dirty.isDirty;
  @override
  Stream<bool> get dirtyChanges => _dirty.dirtyChanges;

  @override
  void markSaved() {
    editor.markSaved();
    _live.clear(); // ADR-0012：保存即已提交，清除 live 漂移，dirty 归 false。
    notifyListeners();
  }

  void updateLiveSource(BlockId id, String source) {
    _live.update(id, source);
    notifyListeners();
  }

  String liveSourceOf(BlockId id) => _live.sourceOf(id);

  /// 聚焦块的 [BlockType]（null = 无聚焦，§2.8 CodeBlock 禁用工具栏）。
  BlockType? get focusedBlockType {
    final id = _state.focusedId;
    if (id == null) return null;
    final element = editor.getBlock(id);
    return element == null ? null : BlockType.fromElement(element);
  }

  /// 聚焦块是否为 CodeBlock（消除 Toolbar 对 core/editing/ 的依赖）。
  bool get isFocusedOnCodeBlock => focusedBlockType == BlockType.code;
  /// 聚焦块的 selection（§2.7.1 强一致读取，Toolbar 用此值）。
  TextSelection? get focusedSelection => _state.focusedSelection;
  bool get hasSelection => _state.hasSelection;

  BlockViewState? viewStateOf(BlockId id) => _state.viewStateOf(id);

  void updateViewState(BlockId id, BlockViewState state) {
    _state = _state.updateViewState(id, state);
    notifyListeners();
  }

  BlockId? get focusedId => _state.focusedId;

  /// 最后聚焦的编辑块（ADR-0012 §Editor Context Preservation）：实时聚焦优先，失焦后回退到 [_lastFocusedId]，chrome 层以此为编辑目标。
  BlockId? get lastFocusedId => _state.focusedId ?? _lastFocusedId;

  /// 聚焦指定块。旧块切回渲染态，新块切到编辑态。
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

  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  /// Undo/Redo：回环真实事务（lastOrNull / redoLastOrNull）携带可重放 ops（修复 Phase 3.3 空 ops 问题）。
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
  void notifyListeners() {
    _dirty.sync();
    super.notifyListeners();
  }

  @override
  void dispose() {
    _dirty.dispose();
    super.dispose();
  }

  @override
  String toString() => 'EditorCoordinator(blocks=$blockCount, focused=${_state.focusedId})';
}
