/// CoordinatorChangeNotifier（#246 局部化刷新）。
///
/// **为什么抽出来**：`EditorCoordinator` 原有硬性约束 —— 文件 ≤ 260 行
/// （TC-ARCH-UI-4 God Object 守门，见 `test/architecture/ui_god_object_test.dart`）。
/// #246 要加 9 个字段级 notifier + 块级注册表 + 各自的同步 / 释放逻辑，
/// 全部塞进 `editor_coordinator.dart` 会把文件推到 400+ 行，直接破门。
///
/// 故把「变更广播」这一独立职责抽成纯工具类：调用方（`EditorCoordinator`）
/// 把当前领域状态传进来，本类只负责「该通知谁」，不含任何业务判断。
///
/// **刻意不写成 `mixin ... on EditorCoordinator`**：那会让本文件 import
/// `editor_coordinator.dart`，而后者也要 import 本文件，形成循环依赖 ——
/// Dart 在解析 `on` 子句时会因循环而拿不到成员，编译报
/// "The method 'syncChangeNotifiers' isn't defined"。
/// 改为「普通类 + 显式参数」，单向依赖，无循环。
///
/// **依赖方向**：editor/ → core/editing/（单向）。本类只 import
/// `block_state_notifiers.dart`，不 import `editor_coordinator.dart`。
library;

import 'package:flutter/foundation.dart';

import '../../core/editing/block_types.dart';
import '../../data/models/document.dart';
import 'block_state_notifiers.dart';
import 'in_memory_document_editor.dart';

/// #246：把「状态变化」广播到各字段级 notifier。
///
/// 每个 notifier 的订阅方（谁关心什么）：
/// | notifier | 订阅方 | 触发时机 |
/// |---|---|---|
/// | [titleNotifier] | EditorAppBar | 文档标题变化（极少） |
/// | [dirtyNotifier] | EditorAppBar | 有未保存修改 |
/// | [undoRedoNotifier] | EditorAppBar + EditorStatusBar | undo/redo 栈可用性 |
/// | [blockCountNotifier] | EditorStatusBar | 块数变化 |
/// | [wordCountNotifier] | EditorStatusBar | 字数变化（含 live 输入） |
/// | [focusNotifier] | BlockSelectionChrome | 聚焦块变化（跨块描边） |
/// | [toolbarNotifier] | MarkdownToolbar + TocPanel | 聚焦/选区/块类型 |
/// | [structureNotifier] | EditorViewport + TocPanel | 块集合或顺序变化 |
/// | [blockNotifiers] | EditorViewport 每项 + BlockSelectionChrome | 单块变化 |
///
/// 关键性质：**按键路径不触发 [structureNotifier]**。按键走
/// `UpdateBlockSourceCommand` → `replaceBlock`（同 id 换内容），既不改变
/// 块集合也不改变顺序，只 bump 该块的 [blockNotifiers] 版本号 —— 这是
/// #246 的核心收益（视口与 chrome 都不重建）。
class CoordinatorChangeNotifier {
  /// 文档标题变化（仅 AppBar 订阅）。
  final ValueNotifier<String> titleNotifier;

  /// 未保存标记变化（仅 AppBar 订阅）。
  final ValueNotifier<bool> dirtyNotifier;

  /// Undo/Redo 可用性变化（AppBar + StatusBar 订阅）。
  final ValueNotifier<bool> undoRedoNotifier;

  /// 聚焦块变化（BlockSelectionChrome 订阅，用于跨块选中描边）。
  final ValueNotifier<BlockId?> focusNotifier;

  /// Toolbar 相关状态聚合信号（MarkdownToolbar + TocPanel 订阅）。
  ///
  /// 合成而非直接暴露：Toolbar 关心 `focusedId` / `focusedBlockType` /
  /// `lastFocusedId` / `focusedSelection` 四者的**组合**，用单一版本号
  /// 让订阅者只比对一次。
  final ValueNotifier<int> toolbarNotifier;

  /// 块数变化（StatusBar 订阅）。
  final ValueNotifier<int> blockCountNotifier;

  /// 字数变化（StatusBar 订阅）。
  final ValueNotifier<int> wordCountNotifier;

  /// 块集合 / 顺序变化（EditorViewport + TocPanel 订阅）。
  ///
  /// 值恒等于 [InMemoryDocumentEditor.blockSetVersion]。**刻意不用
  /// [InMemoryDocumentEditor.structureVersion]**：后者会被 `replaceBlock`
  /// （每次按键 commit 都走）递增，若据此重建视口则 #246 的优化完全失效。
  final ValueNotifier<int> structureNotifier;

  /// 块级状态通知注册表（每块一个 notifier）。
  ///
  /// `EditorViewport.itemBuilder` 为每块包 `ValueListenableBuilder<int>`，
  /// 使「块内文本 / 焦点 / 选区变化」只重建该块，而非整棵视口。
  final BlockStateNotifierRegistry blockNotifiers;

  /// 构造并绑定底层编辑器（读取初始状态）。
  CoordinatorChangeNotifier(this._editor)
      : titleNotifier = ValueNotifier<String>(_editor.title),
        dirtyNotifier = ValueNotifier<bool>(false),
        undoRedoNotifier = ValueNotifier<bool>(false),
        focusNotifier = ValueNotifier<BlockId?>(null),
        toolbarNotifier = ValueNotifier<int>(0),
        blockCountNotifier = ValueNotifier<int>(_editor.blockCount),
        wordCountNotifier = ValueNotifier<int>(initialWordCount(_editor)),
        structureNotifier = ValueNotifier<int>(_editor.blockSetVersion),
        blockNotifiers = BlockStateNotifierRegistry(_editor) {
    blockNotifiers.sync();
  }

  final InMemoryDocumentEditor _editor;

  /// 构造后补一次 undo/redo 可用性（需要 `history`，故不进构造器）。
  void initUndoRedo(bool canUndoOrRedo) {
    undoRedoNotifier.value = canUndoOrRedo;
  }

  /// 全量同步：把当前领域状态推给各 notifier。
  ///
  /// 在每次 `EditorCoordinator.notifyListeners()` 时调用。绝大多数 notifier
  /// 是「值未变则不通知」——`ValueNotifier` 的 `==` 语义保证不会触发多余
  /// 重建，所以全量赋值不会退化成「每次按键全部重建」。
  void syncAll(bool isDirty, bool canUndoOrRedo, int wordCount,
      BlockId? focusedId) {
    titleNotifier.value = _editor.title;
    dirtyNotifier.value = isDirty;
    undoRedoNotifier.value = canUndoOrRedo;
    blockCountNotifier.value = _editor.blockCount;
    wordCountNotifier.value = wordCount;
    toolbarNotifier.value++;
    syncFocus(focusedId);
    // 结构版本单独判定：稳态按键时 blockSetVersion 不变，
    // 不递增即可让 EditorViewport 保持不动（#246 的核心）。
    final sv = _editor.blockSetVersion;
    if (sv != structureNotifier.value) {
      structureNotifier.value = sv;
      blockNotifiers.sync();
    }
  }

  /// 只推 dirty + wordCount（`updateLiveSource` 高频路径：其余 chrome 字段未变）。
  void syncDirtyOnly(bool isDirty, int wordCount) {
    dirtyNotifier.value = isDirty;
    wordCountNotifier.value = wordCount;
  }

  /// 焦点变化时同步 focus + toolbar 两个信号。
  void syncFocus(BlockId? focusedId) {
    if (focusedId != focusNotifier.value) {
      focusNotifier.value = focusedId;
    }
  }

  /// 命令 / undo / redo 完成后广播「受影响块 + 焦点 + toolbar」。
  ///
  /// 折叠了原先散落在 `handle` / `setFocus` / `clearFocus` / `undo` / `redo`
  /// 五处的重复序列，既省行数也避免以后新增 mutator 时漏掉某个 notifier。
  ///
  /// [affected] 传 `null` 表示「块集合可能变了」（undo/redo）——
  /// 此时先 `blockNotifiers.sync()` 补建新块 / 清理孤儿，再全量 bump。
  void broadcastBlockChange(Iterable<BlockId>? affected, BlockId? focusedId) {
    if (affected == null) {
      blockNotifiers.sync();
      blockNotifiers.bumpAllLive();
    } else {
      blockNotifiers.bumpAll(affected);
    }
    syncFocus(focusedId);
    toolbarNotifier.value++;
  }

  /// 单块变化 + toolbar（`updateViewState` 的 selection 同步用）。
  void broadcastSingleBlock(BlockId id) {
    blockNotifiers.bump(id);
    toolbarNotifier.value++;
  }

  /// 释放全部 notifier（`EditorCoordinator.dispose` 调用）。
  void dispose() {
    blockNotifiers.dispose();
    structureNotifier.dispose();
    titleNotifier.dispose();
    dirtyNotifier.dispose();
    undoRedoNotifier.dispose();
    focusNotifier.dispose();
    toolbarNotifier.dispose();
    blockCountNotifier.dispose();
    wordCountNotifier.dispose();
  }
}

/// 初始字数。
///
/// 不能硬编码 0 —— 打开已有内容的文档时，StatusBar 首帧会先显示"字数: 0"，
/// 直到下一次 `notifyListeners()` 才纠正。
///
/// **必须跳过 [EmptyLineElement]**：它是 MarkdownParser 产出的空行分隔符，
/// 既不可编辑也不可序列化 —— `editor.sourceOf(id)` 内部走 `fromElement`，
/// 对该类型会抛
/// `EmptyLineElement is not serializable as a Block (it is a block separator)`。
/// 生产路径（`EditorPage._loadFromFile`）本来就用 `if (element is
/// EmptyLineElement) continue;` 过滤，但测试可直接构造含分隔符的 editor，
/// 故此处显式跳过。
///
/// 与 `LiveEditingState.wordCount` 语义一致：live-first，分隔符不计入字数。
int initialWordCount(InMemoryDocumentEditor editor) {
  var total = 0;
  for (final id in editor.allIds) {
    final element = editor.getBlock(id);
    if (element is EmptyLineElement) continue;
    total += editor.sourceOf(id).length;
  }
  return total;
}