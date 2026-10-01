/// BlockStateNotifierRegistry：块级状态通知注册表（#246）。
///
/// **问题背景**（Issue #246）：
/// `EditorCoordinator` 是单一 `ChangeNotifier`，任何 `notifyListeners()`（输入 /
/// 光标同步 / 焦点切换 / undo / redo）都会触发整棵 `EditorShell` 重建
/// （AppBar + MarkdownToolbar + StatusBar + Workspace + 所有可见块）。
/// 大文档下每次按键的重建深度与帧率直接相关。
///
/// **本方案**：把「结构性变化」与「块内变化」拆开。
/// - **结构性变化**（块增删 / 顺序变更 / 主题 / 缩放）→ [structureNotifier]
///   （`ValueNotifier<int>`，版本号单调递增）。`EditorViewport` 只订阅它，
///   仅结构真的变了才重建 `ReorderableListView`。
/// - **块内变化**（某块的文本 / 焦点 / 选区 / 模式）→ `Map<BlockId, ValueNotifier<int>>`
///   每块一个 notifier，版本号各自单调递增。`EditorViewport.itemBuilder` 为每块
///   包一层 `ValueListenableBuilder<int>`，只有该块版本变化才重建该块 widget。
///
/// **配合 [InMemoryDocumentEditor.structureVersion]**：`insertBlock` / `removeBlock` /
/// `replaceBlock` 会递增它，本注册表以它为结构版本的唯一真源，避免重复维护。
///
/// **依赖方向**（Hard Rule 8）：states/ + editor/ → core/editing/（单向依赖）。
library;

import 'package:flutter/foundation.dart';

import '../../core/editing/block_types.dart';
import 'in_memory_document_editor.dart';

/// 块级状态通知注册表（#246 局部化刷新基础设施）。
///
/// 生命周期由 [EditorCoordinator] 持有与释放；块增删时通过
/// [prune] 清理孤儿 notifier，避免长期编辑导致注册表无限膨胀。
class BlockStateNotifierRegistry {
  /// 每块一个 notifier，值为该块的「块内状态版本号」（单调递增）。
  final Map<BlockId, ValueNotifier<int>> _notifiers = {};

  /// 上一次同步时的块集合版本（来自 [InMemoryDocumentEditor.blockSetVersion]）。
  ///
  /// #246：必须用 `blockSetVersion` 而非 `structureVersion`——后者会被
  /// `replaceBlock`（同 id 换内容，每次按键都走）递增，导致视口被误判为
  /// 「结构变化」而整体重建，局部化刷新完全失效。
  int _lastBlockSetVersion = -1;

  /// 构造并绑定底层编辑器（读取初始结构版本）。
  BlockStateNotifierRegistry(this._editor);

  final InMemoryDocumentEditor _editor;

  /// 当前块集合版本（与编辑器一致）。
  int get blockSetVersion => _editor.blockSetVersion;

  /// 同步块集合：新增块补建 notifier，移除块清理 notifier。
  ///
  /// 幂等且廉价——仅在 [structureVersion] 变化时做实际工作；
  /// 版本未变时直接返回（稳态按键路径 O(1) 无分配）。
  void sync() {
    final version = _editor.blockSetVersion;
    if (version == _lastBlockSetVersion) return;
    _lastBlockSetVersion = version;

    // 移除孤儿：编辑器中已不存在的块。
    final liveIds = _editor.allIds.toSet();
    _notifiers.removeWhere((id, _) => !liveIds.contains(id));

    // 补建：新增块。putIfAbsent 保证已有块的版本号不被打断。
    for (final id in _editor.allIds) {
      _notifiers.putIfAbsent(id, () => ValueNotifier<int>(0));
    }
  }

  /// 取某块的 notifier（不存在则补建）。
  ///
  /// [EditorViewport.itemBuilder] 用它包 `ValueListenableBuilder`，
  /// 实现「只有该块状态变了才重建该块」。
  ValueNotifier<int> notifierOf(BlockId id) {
    return _notifiers.putIfAbsent(id, () => ValueNotifier<int>(0));
  }

  /// 递增某块的版本号（由 [EditorCoordinator] 在块内状态变化时调用）。
  ///
  /// 无变化时是 no-op —— 由 `ValueNotifier` 的 `==` 语义保证不会触发多余重建。
  void bump(BlockId id) {
    notifierOf(id).value++;
  }

  /// 递增**一组**块的版本号（commit / reconcile / undo 影响多块时调用）。
  void bumpAll(Iterable<BlockId> ids) {
    for (final id in ids) {
      bump(id);
    }
  }

  /// 递增所有存活块的版本号（整树级回滚时调用，如 undo 改变块集合）。
  void bumpAllLive() {
    for (final notifier in _notifiers.values) {
      notifier.value++;
    }
  }

  /// 释放全部 notifier（EditorCoordinator.dispose 时调用）。
  void dispose() {
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
  }
}