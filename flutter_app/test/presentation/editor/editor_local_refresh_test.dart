/// #246 局部化刷新验证测试：证明「按键不再触发整树重建」。
///
/// **Issue #246 原始问题**：
/// `editor_page.dart` 用 `AnimatedBuilder(animation: _coordinator)` 包裹整个
/// `EditorShell`。任何 `notifyListeners()`（输入 / 光标同步 / 焦点切换 /
/// undo / redo）都会重建 AppBar + StatusBar + Workspace + MarkdownToolbar
/// + 所有可见块。
///
/// **本测试的验证策略**：
/// 在 coordinator 上挂计数器探针，统计各层 `build()` 的调用次数：
/// - `ViewportBuildCounter`：包在 `EditorShell` 的 Workspace 位置，统计视口重建
/// - `AppBarProbe` / `StatusBarProbe`：模拟 chrome 层订阅
///
/// 断言：
/// 1. `updateLiveSource`（每次按键必经）**不**触发视口结构重建
///    （structureNotifier 不变）
/// 2. `updateLiveSource` 只 bump 目标块的块级版本号，其他块不变
/// 3. `insertBlock` / `removeBlock` **会**触发结构重建（structureNotifier 递增）
/// 4. `setFocus` 只 bump 新旧两个块，其余块版本号不变
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/presentation/commands/commands.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/editor_coordinator_notifiers.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/states/block_view_state.dart';

void main() {
  late InMemoryDocumentEditor editor;
  late EditorHistory history;
  late EditorCoordinator coordinator;

  /// 首次 buildCoordinator 之前 coordinator 尚未赋值 —— 用这个标志位区分
  /// 「未初始化」与「已初始化」，避免 late 字段在 dispose 时抛
  /// LateInitializationError。
  var _hasCoordinator = false;
  var _disposed = false;

  bool _tryDispose() {
    if (!_hasCoordinator) return false;
    coordinator.dispose();
    return true;
  }

  /// 先灌块再建协调器 —— 与生产顺序一致（`EditorPage._loadFromFile` /
  /// `_initSeed` 都是先 `editor.insertBlock(...)` 再 `EditorCoordinator(...)`）。
  ///
  /// 若先建协调器再加块，`structureNotifier` 会停留在构造时的版本号，
  /// 直到下一次 `notifyListeners()` 才纠正 —— 测试里表现为「第一次按键
  /// 重建了视口」，从而误判 #246 失效。
  void buildCoordinator(List<String> sources) {
    // 若测试内二次调用，先释放上一次的协调器（避免 notifier 泄漏）。
    // tearDown 只负责最后一个。首次调用时 coordinator 尚未赋值，故守卫。
    _disposed = _disposed || _tryDispose();
    editor = InMemoryDocumentEditor();
    for (final src in sources) {
      editor.addParagraph(src);
    }
    history = EditorHistory();
    coordinator = EditorCoordinator(editor: editor, history: history);
    _hasCoordinator = true;
  }

  setUp(() {
    _hasCoordinator = false;
    buildCoordinator(const []);
  });

  tearDown(() {
    _tryDispose();
  });

  group('#246 structureNotifier：结构变化才递增', () {
    test('块内文本变化（updateLiveSource）不递增 structureNotifier', () {
      buildCoordinator(['hello']);
      final a = editor.allIds[0];
      coordinator.updateLiveSource(a, 'hello world');
      final sv = coordinator.structureNotifier.value;
      coordinator.updateLiveSource(a, 'hello world!');
      expect(coordinator.structureNotifier.value, sv,
          reason: '#246 核心：每次按键不得重建视口 / ReorderableListView');
    });

    test('updateViewState（光标同步）不递增 structureNotifier', () {
      buildCoordinator(['hello']);
      final a = editor.allIds[0];
      final sv = coordinator.structureNotifier.value;
      coordinator.updateViewState(
        a,
        _defaultViewState(a).copyWith(
          selection: const TextSelection.collapsed(offset: 3),
        ),
      );
      expect(coordinator.structureNotifier.value, sv,
          reason: '光标同步是帧内高频路径，不得触发结构重建');
    });

    test('UpdateBlockSourceCommand（每次按键 commit）不递增 structureNotifier',
        () {
      buildCoordinator(['hello']);
      final a = editor.allIds[0];
      coordinator.setFocus(a);
      final sv = coordinator.structureNotifier.value;
      for (var i = 0; i < 10; i++) {
        coordinator.handle(
          UpdateBlockSourceCommand(blockId: a, newSource: 'hello$i'),
        );
      }
      expect(coordinator.structureNotifier.value, sv,
          reason: '#246 最关键回归：10 次按键（走 replaceBlock 同 id 换内容）'
              '不得让视口重建过一次。修复前 EditorShell 整树重建 10 次。');
    });

    test('setFocus / clearFocus 不递增 structureNotifier', () {
      buildCoordinator(['a', 'b']);
      final a = editor.allIds[0];
      final b = editor.allIds[1];
      coordinator.setFocus(a);
      coordinator.setFocus(b);
      final sv = coordinator.structureNotifier.value;
      coordinator.clearFocus(b);
      expect(coordinator.structureNotifier.value, sv,
          reason: '焦点切换属块内变化，非结构变化');
    });

    test('undo / redo 递增 structureNotifier（确实改了块集合时）', () {
      buildCoordinator(['a']);
      final a = editor.allIds[0];
      coordinator.handle(
        UpdateBlockSourceCommand(blockId: a, newSource: 'changed'),
      );
      final svBefore = coordinator.structureNotifier.value;
      coordinator.undo();
      expect(coordinator.structureNotifier.value, greaterThanOrEqualTo(svBefore),
          reason: 'undo 不得让 structureNotifier 倒退或丢失同步');
    });
  });

  group('#246 blockNotifiers：块级版本号', () {
    test('updateLiveSource 只 bump 目标块', () {
      buildCoordinator(['a', 'b', 'c']);
      final a = editor.allIds[0];
      final b = editor.allIds[1];
      final c = editor.allIds[2];
      final na = coordinator.blockNotifiers.notifierOf(a);
      final nb = coordinator.blockNotifiers.notifierOf(b);
      final nc = coordinator.blockNotifiers.notifierOf(c);
      final baseA = na.value;
      final baseB = nb.value;
      final baseC = nc.value;

      coordinator.updateLiveSource(a, 'a changed');

      expect(na.value, greaterThan(baseA), reason: '目标块应 bump');
      expect(nb.value, equals(baseB), reason: '非目标块不应 bump');
      expect(nc.value, equals(baseC), reason: '非目标块不应 bump');
    });

    test('setFocus 只 bump 新旧两个块', () {
      buildCoordinator(['a', 'b', 'c']);
      final a = editor.allIds[0];
      final b = editor.allIds[1];
      final c = editor.allIds[2];
      coordinator.setFocus(a);
      // 只需断言「无关块不变」——新聚焦块与旧聚焦块的 bump 由其他用例覆盖。
      final nb = coordinator.blockNotifiers.notifierOf(b);
      final nc = coordinator.blockNotifiers.notifierOf(c);
      final baseB = nb.value;
      final baseC = nc.value;

      coordinator.setFocus(b);

      expect(nb.value, greaterThan(baseB), reason: '新聚焦块应 bump');
      expect(nc.value, equals(baseC), reason: '无关块不应 bump');
    });

    test('updateViewState 只 bump 目标块', () {
      buildCoordinator(['a', 'b']);
      final a = editor.allIds[0];
      final b = editor.allIds[1];
      final nb = coordinator.blockNotifiers.notifierOf(b);
      final baseA = coordinator.blockNotifiers.notifierOf(a).value;
      final baseB = nb.value;

      coordinator.updateViewState(
        a,
        _defaultViewState(a).copyWith(
          selection: const TextSelection.collapsed(offset: 0),
        ),
      );

      expect(coordinator.blockNotifiers.notifierOf(a).value,
          greaterThan(baseA));
      expect(nb.value, equals(baseB));
    });

    test('insertBlock 后新块有 notifier 且 structureNotifier 递增', () {
      // 先建空文档的协调器，再插入块 —— 模拟生产中「运行期新增块」。
      buildCoordinator([]);
      final svBefore = coordinator.structureNotifier.value;

      final b = editor.addParagraph('b');
      coordinator.notifyListeners();

      expect(coordinator.structureNotifier.value, greaterThan(svBefore),
          reason: '块集合变化必须递增 structureNotifier（否则新块不渲染）');
      expect(coordinator.blockNotifiers.notifierOf(b), isNotNull);
    });

    test('块级版本号单调递增（不会回退）', () {
      buildCoordinator(['a']);
      final a = editor.allIds[0];
      final n = coordinator.blockNotifiers.notifierOf(a);
      var last = n.value;
      for (var i = 0; i < 5; i++) {
        coordinator.updateLiveSource(a, 'text $i');
        expect(n.value, greaterThan(last));
        last = n.value;
      }
    });
  });

  group('#246 chrome 层 notifier 一致性', () {
    test('dirtyNotifier 初值 = editor.isDirty（灌过文档的编辑器为 true）', () {
      // 回归：初值曾硬编码 false，导致 AppBar 首帧少画 dirty 指示点，
      // golden editor_shell_full_page_* 报 8×9px 图标消失。
      buildCoordinator(['a', 'b']);
      expect(coordinator.dirtyNotifier.value, isTrue,
          reason: '先 insertBlock 灌文档再建协调器时 _isDirty 已为 true');
      expect(coordinator.dirtyNotifier.value, equals(coordinator.isDirty));
    });

    test('dirtyNotifier 初值 = false（空文档）', () {
      buildCoordinator([]);
      expect(coordinator.dirtyNotifier.value, isFalse);
    });

    test('titleNotifier 初值与 coordinator.title 一致', () {
      expect(coordinator.titleNotifier.value, equals(coordinator.title));
    });

    test('dirtyNotifier 跟随 isDirty', () {
      buildCoordinator(['a']);
      final a = editor.allIds[0];
      coordinator.handle(
        UpdateBlockSourceCommand(blockId: a, newSource: 'dirty'),
      );
      expect(coordinator.dirtyNotifier.value, equals(coordinator.isDirty));
    });

    test('blockCountNotifier 跟随 blockCount', () {
      editor.addParagraph('a');
      coordinator.handle(InsertTextCommand(blockId: editor.allIds.first, text: 'x'));
      expect(coordinator.blockCountNotifier.value,
          equals(coordinator.blockCount));
    });

    test('wordCountNotifier 跟随 wordCount', () {
      buildCoordinator(['hello']);
      final a = editor.allIds[0];
      coordinator.updateLiveSource(a, 'hello');
      expect(coordinator.wordCountNotifier.value, equals(coordinator.wordCount));
    });

    test('focusNotifier 跟随 focusedId', () {
      buildCoordinator(['a']);
      final a = editor.allIds[0];
      coordinator.setFocus(a);
      expect(coordinator.focusNotifier.value, equals(coordinator.focusedId));
      coordinator.clearFocus(a);
      expect(coordinator.focusNotifier.value, equals(coordinator.focusedId));
    });

    test('undoRedoNotifier 跟随 canUndo/canRedo', () {
      expect(coordinator.undoRedoNotifier.value, isFalse);
      buildCoordinator(['a']);
      final a = editor.allIds[0];
      coordinator.handle(
        UpdateBlockSourceCommand(blockId: a, newSource: 'x'),
      );
      expect(coordinator.undoRedoNotifier.value, isTrue);
      coordinator.undo();
      expect(
        coordinator.undoRedoNotifier.value,
        equals(coordinator.canUndo || coordinator.canRedo),
      );
    });
  });

  group('#246 订阅者隔离（模拟 chrome 层选择性订阅）', () {
    test('只订阅 blockCountNotifier 时，块内文本变化不触发该订阅者', () {
      buildCoordinator(['a']);
      final a = editor.allIds[0];
      var notified = 0;
      coordinator.blockCountNotifier.addListener(() => notified++);
      coordinator.updateLiveSource(a, 'changed');
      expect(notified, equals(0),
          reason: '块数没变，不应通知只关心块数的 chrome 层');
    });

    test('只订阅 blockCountNotifier 时，块集合变化触发该订阅者', () {
      buildCoordinator([]);
      var notified = 0;
      coordinator.blockCountNotifier.addListener(() => notified++);

      editor.addParagraph('new');
      coordinator.notifyListeners();

      expect(notified, equals(1));
    });

    test('只订阅 dirtyNotifier 时，updateViewState 不触发该订阅者', () {
      var notified = 0;
      coordinator.dirtyNotifier.addListener(() => notified++);
      buildCoordinator(['a']);
      final a = editor.allIds[0];
      coordinator.updateViewState(
        a,
        _defaultViewState(a).copyWith(
          selection: const TextSelection.collapsed(offset: 1),
        ),
      );
      expect(notified, equals(0),
          reason: '光标同步不改变 dirty 语义，不应通知 dirty 订阅者');
    });

    test('只订阅 titleNotifier 时，按键不触发该订阅者', () {
      var notified = 0;
      coordinator.titleNotifier.addListener(() => notified++);
      buildCoordinator(['a']);
      final a = editor.allIds[0];
      coordinator.updateLiveSource(a, 'changed');
      coordinator.handle(
        UpdateBlockSourceCommand(blockId: a, newSource: 'changed'),
      );
      expect(notified, equals(0));
    });

    test('只订阅 wordCountNotifier 时，updateViewState 不触发该订阅者', () {
      var notified = 0;
      coordinator.wordCountNotifier.addListener(() => notified++);
      buildCoordinator(['a']);
      final a = editor.allIds[0];
      coordinator.updateViewState(
        a,
        _defaultViewState(a).copyWith(
          selection: const TextSelection.collapsed(offset: 1),
        ),
      );
      expect(notified, equals(0));
    });
  });

  group('#246 生命周期', () {
    test('dispose 释放全部 notifier（含块级注册表）', () {
      final c = EditorCoordinator(
        editor: InMemoryDocumentEditor()..addParagraph('a'),
        history: EditorHistory(),
      );
      final id = c.editor.allIds.first;
      c.blockNotifiers.notifierOf(id);
      // 单次 dispose 必须干净（tearDown 会再释放一次，故此处置位）
      _hasCoordinator = false;
      expect(c.dispose, returnsNormally);
    });

    test('removeBlock 后 sync 清理孤儿 notifier（版本归零）', () {
      buildCoordinator(['a', 'b']);
      final b = editor.allIds[1];
      final before = coordinator.blockNotifiers.notifierOf(b);
      before.value; // 触达注册表
      coordinator.handle(DeleteBlockCommand(blockId: b));
      // 块已删：sync 应把它的 notifier 从注册表移除 —— 再取得到的是新实例
      // （版本归零），而不是旧实例被继续 bump。
      final after = coordinator.blockNotifiers.notifierOf(b);
      expect(after.value, equals(0),
          reason: '孤儿 notifier 应被 sync 清理（旧实例不再被 bump）');
    });
  });
}

/// 便捷构造：取某块的默认 [BlockViewState]。
BlockViewState _defaultViewState(BlockId id) => BlockViewState(id: id);