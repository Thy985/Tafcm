/// EditorCoordinator：UI 层对编辑内核的协调器（Phase 3.0 production 路径）。
/// 落地 ADR-0009 §3.5 + Phase 3.0 §2.4（避免 God Object）+ ADR-0012（Live State）
/// + ADR-0013（实现 DirtyStateSource，委托 DirtyStateTracker）。只协调不持有业务状态。
/// 
/// #246 局部化刷新：拆分 notifyListeners 为 3 个 ValueNotifier，
/// 让 chrome 层（AppBar / StatusBar）只订阅自己关心的字段，
/// 避免每次按键触发整棵 EditorShell 重建。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show TextSelection;
import '../../core/editing/block_types.dart';
import '../../core/editing/editor_history.dart';
import '../../core/editing/transaction.dart';
import '../../core/observability/models.dart' as obs;
import '../../core/observability/observability_service.dart';
import '../../core/observability/trace_context.dart';
import '../../data/models/document.dart';
import '../commands/command_handler.dart';
import '../commands/editor_command.dart';
import '../states/block_view_state.dart';
import '../states/coordinator_state.dart';
import 'block_state_notifiers.dart';
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

  /// #246：块数变化通知（仅 StatusBar 订阅）。
  final ValueNotifier<int> blockCountNotifier;
  /// #246：字数变化通知（仅 StatusBar 订阅）。
  final ValueNotifier<int> wordCountNotifier;
  /// #246：标题变化通知（仅 AppBar 订阅，避免整树重建）。
  final ValueNotifier<String> titleNotifier;
  /// #246：Dirty 变化通知（仅 AppBar 订阅）。
  final ValueNotifier<bool> dirtyNotifier;
  /// #246：Undo/Redo 可用性变化通知（仅 AppBar + StatusBar 订阅）。
  final ValueNotifier<bool> undoRedoNotifier;
  /// #246：聚焦块变化通知（仅 BlockSelectionChrome 订阅，用于选中描边）。
  ///
  /// 跨块联动只需让「旧聚焦块 + 新聚焦块」两个 chrome 重建——
  /// `setFocus` / `clearFocus` 会 bump 对应块的块级 notifier，
  /// 这里的 [focusNotifier] 只是额外的短路信号，避免 N 个块全部比对。
  final ValueNotifier<BlockId?> focusNotifier;
  /// #246：Toolbar 相关状态聚合通知（MarkdownToolbar 订阅）。
  ///
  /// Toolbar 的按钮启用态取决于四类输入的组合：
  /// - `focusedId`（有聚焦块才能格式化）
  /// - `focusedBlockType`（CodeBlock 时整体禁用）
  /// - `lastFocusedId`（失焦后模板菜单仍可用，ADR-0012）
  /// - `focusedSelection`（InsertText vs WrapSelection 路径）
  ///
  /// 这四者都不属于「块内容」也不属于「chrome 标量」，故用独立的
  /// 合成版本号通知，避免 Toolbar 订阅 4 个 notifier 或退回全局监听。
  final ValueNotifier<int> toolbarNotifier;
  /// #246：文档结构变化通知（块增删 / 顺序变更 / BlockId 迁移）。
  ///
  /// 值恒等于 [editor.blockSetVersion]（单调递增）。`EditorViewport` 只订阅
  /// 它——结构没变就不重建 `ReorderableListView`，是 #246 的核心优化点。
  ///
  /// **刻意不用 [editor.structureVersion]**：后者会被 `replaceBlock`
  /// （每次按键 commit 都走）递增，若据此重建视口则 #246 的优化完全失效。
  final ValueNotifier<int> structureNotifier;
  /// #246：块级状态通知注册表（每块一个 notifier）。
  ///
  /// `EditorViewport.itemBuilder` 为每块包 `ValueListenableBuilder<int>`，
  /// 使「块内文本 / 焦点 / 选区变化」只重建该块，而非整棵视口。
  final BlockStateNotifierRegistry blockNotifiers;

  /// ADR-0012：Live Editing State（实时文本 / 字数 / 脏标记），抽出独立类避免膨胀。
  late final LiveEditingState _live;
  /// ADR-0012 §Editor Context Preservation：最后聚焦的编辑块，不随 [clearFocus] 清空。
  BlockId? _lastFocusedId;
  late final DirtyStateTracker _dirty;
  /// ADR-0021：可观测服务（可选，LIGHT 模式下默认开启）。
  final ObservabilityService? observability;

  /// 只读查看模式（#240）：外部 URI 无持久化路径，编辑命令统一 no-op 防丢内容。
  bool isReadOnly = false;

  EditorCoordinator({
    required this.editor,
    required this.history,
    this.observability,
  }) : _state = const CoordinatorState.empty(),
        titleNotifier = ValueNotifier<String>(editor.title),
        dirtyNotifier = ValueNotifier<bool>(false),
        undoRedoNotifier = ValueNotifier<bool>(false),
        focusNotifier = ValueNotifier<BlockId?>(null),
        toolbarNotifier = ValueNotifier<int>(0),
        blockCountNotifier = ValueNotifier<int>(editor.blockCount),
        wordCountNotifier = ValueNotifier<int>(_initialWordCount(editor)),
        structureNotifier = ValueNotifier<int>(editor.blockSetVersion),
        blockNotifiers = BlockStateNotifierRegistry(editor) {
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
    undoRedoNotifier.value = history.canUndo || history.canRedo;
    blockNotifiers.sync();
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
      _recordInteractionForCommand(command);
      final result = CommandSelectionSync.apply(_state, command,
          editor: editor, oldSource: oldSource, oldIds: oldIds);
      _state = result.state;
      if (result.newFocus != null) _lastFocusedId = result.newFocus;
      _live.reconcile(result.affectedIds); // 受影响块对齐到 committed
      // #246：仅 bump 受影响块的版本号，让视口只重建这些块。
      // 结构变化已由 notifyListeners 的 structureNotifier 分发。
      blockNotifiers.bumpAll(result.affectedIds);
      // #246：命令可能转移焦点（SplitBlock / MergeWithPrevious 等）。
      if (_state.focusedId != focusNotifier.value) {
        focusNotifier.value = _state.focusedId;
      }
      toolbarNotifier.value++;
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
    // #246：同步推送局部化通知
    titleNotifier.value = editor.title;
    dirtyNotifier.value = isDirty;
    undoRedoNotifier.value = canUndo || canRedo;
    blockCountNotifier.value = editor.blockCount;
    wordCountNotifier.value = _live.wordCount;
    notifyListeners();
  }
  void updateLiveSource(BlockId id, String source) {
    _live.update(id, source);
    // #246：live source 变化只需通知 dirtyNotifier（wordCount 由 LiveEditingState 内部差量维护）
    dirtyNotifier.value = isDirty;
    wordCountNotifier.value = _live.wordCount;
    // #246：bump 该块 —— 该块的 wordCount / dirty 展示确实变了。
    blockNotifiers.bump(id);
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
    // #246：块内状态变化只 bump 该块版本号，不触发结构重建。
    blockNotifiers.bump(id);
    // #246：selection 影响 Toolbar 的 InsertText vs WrapSelection 路径。
    toolbarNotifier.value++;
    notifyListeners();
  }
  BlockId? get focusedId => _state.focusedId;
  /// 最后聚焦的编辑块（ADR-0012 §Editor Context Preservation）：实时聚焦优先，失焦后回退到 [_lastFocusedId]，chrome 层以此为编辑目标。
  BlockId? get lastFocusedId => _state.focusedId ?? _lastFocusedId;
  /// 聚焦指定块。旧块切回渲染态，新块切到编辑态。
  void setFocus(BlockId id) {
    beginUserInteraction();
    _recordInteraction(obs.UserTap(target: 'Block($id)', timestamp: DateTime.now()));
    if (_state.focusedId == id) return;
    final wasMissing = !_state.viewStates.containsKey(id);
    final prevFocused = _state.focusedId;
    _state = _state.focusOn(id);
    if (wasMissing) {
      observability?.recordRender(
          obs.FocusOnViewStateCreatedEvent(blockId: id.value, timestamp: DateTime.now()));
    }
    _lastFocusedId = id;
    // #246：焦点切换只 bump 新旧两个块的版本号（旧块切回 rendered、
    // 新块切到 editing），其余块不重建。
    if (prevFocused != null) blockNotifiers.bump(prevFocused);
    blockNotifiers.bump(id);
    focusNotifier.value = id;
    // #246：聚焦块变化会改 Toolbar 的 enabled / templateEnabled 与 BlockType。
    toolbarNotifier.value++;
    notifyListeners();
  }
  /// 清除指定块的焦点（切回渲染态）。
  void clearFocus(BlockId id) {
    final next = _state.clearFocusOf(id);
    if (identical(next, _state)) return;
    _state = next;
    // #246：仅 bump 该块。
    blockNotifiers.bump(id);
    if (_state.focusedId != focusNotifier.value) {
      focusNotifier.value = _state.focusedId;
    }
    toolbarNotifier.value++;
    notifyListeners();
  }
  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;
  /// Undo/Redo：回环真实事务（lastOrNull / redoLastOrNull）携带可重放 ops（修复 Phase 3.3 空 ops 问题）。
  Transaction? undo() {
    beginUserInteraction();
    _recordInteraction(obs.UserUndoRedo(isUndo: true, timestamp: DateTime.now()));
    final target = history.lastOrNull;
    if (target == null) return null;
    final tx = history.undo(target);
    if (tx == null) return null;
    _live.clear();
    for (final op in tx.ops.reversed) {
      op.revert(editor);
    }
    _syncViewStates();
    // #246：undo 可能改变块集合与多块内容 —— bump 全部存活块，
    // 结构变化由 notifyListeners 的 structureNotifier 分发。
    blockNotifiers.sync();
    blockNotifiers.bumpAllLive();
    if (_state.focusedId != focusNotifier.value) {
      focusNotifier.value = _state.focusedId;
    }
    toolbarNotifier.value++;
    notifyListeners();
    return tx;
  }
  Transaction? redo() {
    beginUserInteraction();
    _recordInteraction(obs.UserUndoRedo(isUndo: false, timestamp: DateTime.now()));
    final target = history.redoLastOrNull;
    if (target == null) return null;
    final tx = history.redo(target);
    if (tx == null) return null;
    _live.clear();
    for (final op in tx.ops) {
      op.apply(editor);
    }
    _syncViewStates();
    // #246：同 undo —— redo 也可能改变块集合与多块内容。
    blockNotifiers.sync();
    blockNotifiers.bumpAllLive();
    if (_state.focusedId != focusNotifier.value) {
      focusNotifier.value = _state.focusedId;
    }
    toolbarNotifier.value++;
    notifyListeners();
    return tx;
  }
  void _syncViewStates() => _state = _state.syncViewStates(editor.allIds);

  /// ADR-0021 §2.6：开始新的用户交互，生成新 traceId。
  ///
  /// 在 dispatch / setFocus / undo / redo 等用户交互入口调用，
  /// 不在 handle() 内调用（一次交互可能派发多个 command，共享同一 traceId）。
  @override
  void beginUserInteraction() {
    final svc = observability;
    if (svc?.isEnabled == true) {
      svc!.setTraceContext(EditorTraceContext(
        sessionId: svc.sessionId,
        traceId: TraceIdGenerator.traceId(),
        spanId: TraceIdGenerator.commandSpanId(),
      ));
    }
  }

  /// 记录用户交互事件（Phase 3.7.3）。
  void _recordInteraction(obs.EditorInteractionEvent event) {
    observability?.recordInteraction(event);
  }

  /// 公开交互记录入口（供 [BaseBlockState] 等组件调用）。
  void recordInteraction(obs.EditorInteractionEvent event) {
    _recordInteraction(event);
  }

  /// 导出诊断数据 zip（Phase 3.7.3）。
  ///
  /// 委托给 [ObservabilityService.exportDiagnosticZip]。
  /// 返回 zip 文件路径，失败或未启用时返回 null。
  Future<String?> exportDiagnosticZip({String? outputDir}) {
    if (observability == null) return Future.value(null);
    return observability!.exportDiagnosticZip(outputDir: outputDir);
  }

  /// 根据 Command 类型记录交互事件。
  ///
  /// **P1 信噪比修复（2026-08-06）**：UserInput 改用 [UserInput.fromText]
  /// 工厂，仅记录 length/hasNewline/isAscii 三项脱敏元信息，
  /// 不再传入原始 [InsertTextCommand.text]。
  void _recordInteractionForCommand(EditorCommand command) {
    final now = DateTime.now();
    switch (command) {
      case InsertTextCommand c:
        _recordInteraction(
            obs.UserInput.fromText(c.text, now));
      case WrapSelectionCommand c:
        _recordInteraction(obs.UserFormatToggle(
          format: '${c.prefix}${c.suffix}',
          timestamp: now,
        ));
      default:
        break;
    }
  }
  @override
  void notifyListeners() {
    _dirty.sync();
    // #246：同步推送局部化通知，让 chrome 层不必等待整树重建
    titleNotifier.value = editor.title;
    dirtyNotifier.value = isDirty;
    undoRedoNotifier.value = canUndo || canRedo;
    blockCountNotifier.value = editor.blockCount;
    wordCountNotifier.value = _live.wordCount;
    // #246：块集合版本同步 —— 仅块集合/顺序真的变了才递增，EditorViewport
    // 据此决定是否重建 ReorderableListView。同步块集合（新块补建 / 孤儿清理）。
    final sv = editor.blockSetVersion;
    if (sv != structureNotifier.value) {
      structureNotifier.value = sv;
      blockNotifiers.sync();
    }
    super.notifyListeners();
  }
  @override
  void dispose() {
    _dirty.dispose();
    // #246：释放块级 notifier 注册表 + 各字段级 notifier（ADR-0013 同规）。
    blockNotifiers.dispose();
    structureNotifier.dispose();
    titleNotifier.dispose();
    dirtyNotifier.dispose();
    undoRedoNotifier.dispose();
    focusNotifier.dispose();
    toolbarNotifier.dispose();
    blockCountNotifier.dispose();
    wordCountNotifier.dispose();
    super.dispose();
  }

  @override
  String toString() => 'EditorCoordinator(blocks=$blockCount, focused=${_state.focusedId})';
}

/// 初始字数（#246：[wordCountNotifier] 构造初值）。
///
/// 不能硬编码 0 —— 打开已有内容的文档时，StatusBar 首帧会先显示"字数: 0"，
/// 直到下一次 `notifyListeners()` 才纠正。[LiveEditingState] 在协调器构造
/// 之后才创建，故此处直接按 committed source 累加一次作为初值
/// （O(n) 只在构造时发生一次，稳态按键走 [LiveEditingState] 的差量路径）。
int _initialWordCount(InMemoryDocumentEditor editor) {
  var total = 0;
  for (final source in editor.allSources) {
    total += source.length;
  }
  return total;
}
