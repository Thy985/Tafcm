/// EditorCoordinator 的 notifier 转发 extension（#246 行数拆分）。
///
/// **为什么用 extension 而不是实例 getter**：`EditorCoordinator` 有
/// TC-ARCH-UI-4 硬约束 —— 文件 ≤ 260 行（见
/// `test/architecture/ui_god_object_test.dart`）。#246 新增 9 个 notifier
/// 转发 getter 会把文件推到上限之外，故移到本 extension。
///
/// extension 的成员与实例 getter 对调用方完全等价：
/// `coordinator.titleNotifier` 照常可用，无需改任何调用点。
library;

import 'package:flutter/foundation.dart';

import '../../core/editing/block_types.dart';
import 'block_state_notifiers.dart';
import 'editor_coordinator.dart';

/// #246：字段级 notifier 的转发 getter。
///
/// 让既有调用点（chrome 层 / blocks 层 / 测试）继续用
/// `coordinator.xxxNotifier`，无需改成 `coordinator.changes.xxxNotifier`。
extension EditorCoordinatorNotifiers on EditorCoordinator {
  /// 文档标题变化（AppBar 订阅）。
  ValueNotifier<String> get titleNotifier => changes.titleNotifier;

  /// 未保存标记变化（AppBar 订阅）。
  ValueNotifier<bool> get dirtyNotifier => changes.dirtyNotifier;

  /// Undo/Redo 可用性变化（AppBar + StatusBar 订阅）。
  ValueNotifier<bool> get undoRedoNotifier => changes.undoRedoNotifier;

  /// 聚焦块变化（BlockSelectionChrome 订阅，用于跨块选中描边）。
  ValueNotifier<BlockId?> get focusNotifier => changes.focusNotifier;

  /// Toolbar 相关状态聚合信号（MarkdownToolbar + TocPanel 订阅）。
  ValueNotifier<int> get toolbarNotifier => changes.toolbarNotifier;

  /// 块数变化（StatusBar 订阅）。
  ValueNotifier<int> get blockCountNotifier => changes.blockCountNotifier;

  /// 字数变化（StatusBar 订阅）。
  ValueNotifier<int> get wordCountNotifier => changes.wordCountNotifier;

  /// 块集合 / 顺序变化（EditorViewport + TocPanel 订阅）。
  ValueNotifier<int> get structureNotifier => changes.structureNotifier;

  /// 块级状态注册表（每块一个 notifier）。
  BlockStateNotifierRegistry get blockNotifiers => changes.blockNotifiers;
}
