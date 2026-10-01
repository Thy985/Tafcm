/// EditorCoordinator：UI 层对编辑内核的协调器（Phase 3.0 production 路径）。
/// 落地 ADR-0009 §3.5 + Phase 3.0 §2.4 + ADR-0012（Live State）+ ADR-0013（Dirty）。
///
/// **#246**：变更广播 / 可观测 / notifier getter 已拆到同目录另 3 个文件（守 260 行）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show TextSelection;
import '../../core/editing/block_types.dart';
import '../../core/editing/editor_history.dart';
import '../../core/editing/transaction.dart';
import '../../core/observability/models.dart' as obs;
import '../../core/observability/observability_service.dart';
import '../../data/models/document.dart';
import '../commands/command_handler.dart';
import '../commands/editor_command.dart';
import '../states/block_view_state.dart';
import '../states/coordinator_state.dart';
import 'command_selection_sync.dart';
import 'coordinator_change_notifier.dart';
import 'coordinator_observability.dart';
import 'editor_coordinator_notifiers.dart';
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

  // #246：变更广播 + 可观测上报（拆出以守住 TC-ARCH-UI-4 行数上限）。
  late final CoordinatorChangeNotifier changes;
  late final CoordinatorObservability telemetry;

  /// ADR-0012：Live Editing State（实时文本 / 字数 / 脏标记）。
  late final LiveEditingState _live;
  /// ADR-0012 §Editor Context Preservation：不随 clearFocus 清空。
  BlockId? _lastFocusedId;
  late final DirtyStateTracker _dirty;
  /// ADR-0021：可观测服务（可选，LIGHT 模式下默认开启）。
  final ObservabilityService? observability;

  /// 只读查看模式（#240）：编辑命令统一 no-op 防丢内容。
  bool isReadOnly = false;

  EditorCoordinator({
    required this.editor,
    required this.history,
    this.observability,
  }) : _state = const CoordinatorState.empty() {
    handler = CommandHandler(
      editor: editor,
      history: history,
      observability: observability,
    );
    _live = LiveEditingState(editor);
    _dirty = DirtyStateTracker(() => _live.isDirty);
    _intentDispatcher = EditorIntentDispatcher(this);
    _state = CoordinatorState.initial({
      for (final id in editor.allIds) id: BlockViewState(id: id),
    });
    // #246：初始化变更广播器与可观测转发层。
    changes = CoordinatorChangeNotifier(editor);
  changes.initUndoRedo(history.canUndo || history.canRedo);
  telemetry = CoordinatorObservability(observability);
  }

  bool handle(EditorCommand command) {
    if (isReadOnly) return false; // #240：查看模式，编辑命令统一 no-op
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
      recordInteractionForCommand(command);
      final result = CommandSelectionSync.apply(_state, command,
          editor: editor, oldSource: oldSource, oldIds: oldIds);
      _state = result.state;
      if (result.newFocus != null) _lastFocusedId = result.newFocus;
      _live.reconcile(result.affectedIds); // 受影响块对齐到 committed
      // #246：只 bump 受影响块（结构变化由 structureNotifier 另行分发）。
      changes.broadcastBlockChange(result.affectedIds, _state.focusedId);
      notifyListeners();
    }
    return ok;
  }

  int get blockCount => editor.blockCount;
  List<BlockId> get allIds => editor.allIds;
  DocumentElement? getBlock(BlockId id) => editor.getBlock(id);
  String sourceOf(BlockId id) => editor.sourceOf(id);
  /// ADR-0019：输入意图派发器（flush→resolve→handle）。
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
    // #246：live 输入只推 dirty + wordCount。
    changes.syncDirtyOnly(isDirty, wordCount);
    changes.blockNotifiers.bump(id);
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
  /// 聚焦块 selection（§2.7.1 强一致读取，Toolbar 用此值）。
  TextSelection? get focusedSelection => _state.focusedSelection;
  bool get hasSelection => _state.hasSelection;
  BlockViewState? viewStateOf(BlockId id) => _state.viewStateOf(id);
  void updateViewState(BlockId id, BlockViewState state) {
    _state = _state.updateViewState(id, state);
      // #246：selection 影响 Toolbar 的 Insert/Wrap 路径。
    changes.broadcastSingleBlock(id);
    notifyListeners();
  }
  BlockId? get focusedId => _state.focusedId;
  /// 最后聚焦的编辑块（ADR-0012）：实时聚焦优先，失焦后回退 [_lastFocusedId]。
  BlockId? get lastFocusedId => _state.focusedId ?? _lastFocusedId;
  /// 聚焦指定块。旧块切回渲染态，新块切到编辑态。
  void setFocus(BlockId id) {
    beginUserInteraction();
    telemetry.recordInteraction(
        obs.UserTap(target: 'Block($id)', timestamp: DateTime.now()));
    if (_state.focusedId == id) return;
    final wasMissing = !_state.viewStates.containsKey(id);
    final prevFocused = _state.focusedId;
    _state = _state.focusOn(id);
    if (wasMissing) {
      observability?.recordRender(
          obs.FocusOnViewStateCreatedEvent(blockId: id.value, timestamp: DateTime.now()));
    }
    _lastFocusedId = id;
    // #246：只 bump 新旧两块；broadcastBlockChange 内部同步 focus + toolbar。
    if (prevFocused != null) changes.blockNotifiers.bump(prevFocused);
    changes.broadcastBlockChange([id], id);
    notifyListeners();
  }
  /// 清除指定块的焦点（切回渲染态）。
  void clearFocus(BlockId id) {
    final next = _state.clearFocusOf(id);
    if (identical(next, _state)) return;
    _state = next;
    // #246：仅 bump 该块。
    changes.broadcastBlockChange([id], _state.focusedId);
    notifyListeners();
  }
  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;
  /// Undo/Redo：回环真实事务（携带可重放 ops，修复 Phase 3.3 空 ops）。
  Transaction? undo() {
    beginUserInteraction();
    telemetry.recordInteraction(
        obs.UserUndoRedo(isUndo: true, timestamp: DateTime.now()));
    final target = history.lastOrNull;
    if (target == null) return null;
    final tx = history.undo(target);
    if (tx == null) return null;
    _live.clear();
    for (final op in tx.ops.reversed) {
      op.revert(editor);
    }
    return _finishHistoryReplay(tx);
  }

  Transaction? redo() {
    beginUserInteraction();
    telemetry.recordInteraction(
        obs.UserUndoRedo(isUndo: false, timestamp: DateTime.now()));
    final target = history.redoLastOrNull;
    if (target == null) return null;
    final tx = history.redo(target);
    if (tx == null) return null;
    _live.clear();
    for (final op in tx.ops) {
      op.apply(editor);
    }
    return _finishHistoryReplay(tx);
  }

  /// undo / redo 收尾：同步 viewState + 广播。
  Transaction? _finishHistoryReplay(Transaction tx) {
    _syncViewStates();
    changes.broadcastBlockChange(null, _state.focusedId);
    notifyListeners();
    return tx;
  }
  // 曾写成 `mixin ... on EditorCoordinator`，会与本文件循环 import，故字段转发。
  @override
  void beginUserInteraction() => telemetry.beginUserInteraction();

  /// 公开交互记录入口（供 [BaseBlockState] 等组件调用）。
  void recordInteraction(obs.EditorInteractionEvent event) =>
      telemetry.recordInteraction(event);

  /// 根据 Command 类型记录交互事件（handle 内部调用）。
  void recordInteractionForCommand(EditorCommand command) =>
      telemetry.recordInteractionForCommand(command);

  /// 导出诊断数据 zip（Phase 3.7.3）。
  Future<String?> exportDiagnosticZip({String? outputDir}) =>
      telemetry.exportDiagnosticZip(outputDir: outputDir);
  void _syncViewStates() => _state = _state.syncViewStates(editor.allIds);

  @override
  void notifyListeners() {
    _dirty.sync();
    // #246：全量同步（值未变则不通知）
    changes.syncAll(
        isDirty, canUndo || canRedo, wordCount, _state.focusedId);
    super.notifyListeners();
  }
  @override
  void dispose() {
    _dirty.dispose();
    changes.dispose(); // #246：释放全部 notifier
    super.dispose();
  }

  @override
  String toString() =>
      'EditorCoordinator(blocks=$blockCount, focused=${_state.focusedId})';
}
