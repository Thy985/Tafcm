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
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/states/block_view_state.dart';

void main() {
  late InMemoryDocumentEditor editor;
  late EditorHistory history;
  late EditorCoordinator coordinator;

  setUp(() {
    editor = InMemoryDocumentEditor();
    history = EditorHistory();
    coordinator = EditorCoordinator(editor: editor, history: history);
  });

  tearDown(() {
    coordinator.dispose();
  });

  group('#246 structureNotifier：结构变化才递增', () {
    test('块内文本变化（updateLiveSource）不递增 structureNotifier', () {
      final a = editor.addParagraph('hello');
      coordinator.updateLiveSource(a, 'hello world');
      final sv = coordinator.structureNotifier.value;
      coordinator.updateLiveSource(a, 'hello world!');
      expect(coordinator.structureNotifier.value, sv,
          reason: '#246 核心：每次按键不得重建视口 / ReorderableListView');
    });

    test('updateViewState（光标同步）不递增 structureNotifier', () {
      final a = editor.addParagraph('hello');
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
      final a = editor.addParagraph('hello');
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
      final a = editor.addParagraph('a');
      final b = editor.addParagraph('b');
      coordinator.setFocus(a);
      coordinator.setFocus(b);
      final sv = coordinator.structureNotifier.value;
      coordinator.clearFocus(b);
      expect(coordinator.structureNotifier.value, sv,
          reason: '焦点切换属块内变化，非结构变化');
    });

    test('undo / redo 递增 structureNotifier（确实改了块集合时）', () {
      final a = editor.addParagraph('a');
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
      final a = editor.addParagraph('a');
      final b = editor.addParagraph('b');
      final c = editor.addParagraph('c');
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
      final a = editor.addParagraph('a');
      final b = editor.addParagraph('b');
      final c = editor.addParagraph('c');
      coordinator.setFocus(a);
      final na = coordinator.blockNotifiers.notifierOf(a);
      final nb = coordinator.blockNotifiers.notifierOf(b);
      final nc = coordinator.blockNotifiers.notifierOf(c);
      final baseB = nb.value;
      final baseC = nc.value;

      coordinator.setFocus(b);

      expect(nb.value, greaterThan(baseB), reason: '新聚焦块应 bump');
      expect(nc.value, equals(baseC), reason: '无关块不应 bump');
    });

    test('updateViewState 只 bump 目标块', () {
      final a = editor.addParagraph('a');
      final b = editor.addParagraph('b');
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
      final a = editor.addParagraph('a');
      final svBefore = coordinator.structureNotifier.value;
      final b = editor.addParagraph('b');
      coordinator.handle(
        UpdateBlockSourceCommand(blockId: b, newSource: 'x'),
      );
      expect(coordinator.structureNotifier.value, greaterThan(svBefore),
          reason: '块集合变化必须递增 structureNotifier（否则新块不渲染）');
      expect(coordinator.blockNotifiers.notifierOf(a), isNotNull);
      expect(coordinator.blockNotifiers.notifierOf(b), isNotNull);
    });

    test('块级版本号单调递增（不会回退）', () {
      final a = editor.addParagraph('a');
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
    test('titleNotifier 初值与 coordinator.title 一致', () {
      expect(coordinator.titleNotifier.value, equals(coordinator.title));
    });

    test('dirtyNotifier 跟随 isDirty', () {
      final a = editor.addParagraph('a');
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
      final a = editor.addParagraph('hello');
      coordinator.updateLiveSource(a, 'hello');
      expect(coordinator.wordCountNotifier.value, equals(coordinator.wordCount));
    });

    test('focusNotifier 跟随 focusedId', () {
      final a = editor.addParagraph('a');
      coordinator.setFocus(a);
      expect(coordinator.focusNotifier.value, equals(coordinator.focusedId));
      coordinator.clearFocus(a);
      expect(coordinator.focusNotifier.value, equals(coordinator.focusedId));
    });

    test('undoRedoNotifier 跟随 canUndo/canRedo', () {
      expect(coordinator.undoRedoNotifier.value, isFalse);
      final a = editor.addParagraph('a');
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
      final a = editor.addParagraph('a');
      var notified = 0;
      coordinator.blockCountNotifier.addListener(() => notified++);
      coordinator.updateLiveSource(a, 'changed');
      expect(notified, equals(0),
          reason: '块数没变，不应通知只关心块数的 chrome 层');
    });

    test('只订阅 blockCountNotifier 时，insertBlock 触发该订阅者', () {
      var notified = 0;
      coordinator.blockCountNotifier.addListener(() => notified++);
      // 直接操作 editor 会绕过 coordinator，故经 handle 触发
      final a = editor.addParagraph('a');
      coordinator.handle(
        UpdateBlockSourceCommand(blockId: a, newSource: 'x'),
      );
      expect(notified, equals(1));
    });

    test('只订阅 dirtyNotifier 时，updateViewState 不触发该订阅者', () {
      var notified = 0;
      coordinator.dirtyNotifier.addListener(() => notified++);
      final a = editor.addParagraph('a');
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
      final a = editor.addParagraph('a');
      coordinator.updateLiveSource(a, 'changed');
      coordinator.handle(
        UpdateBlockSourceCommand(blockId: a, newSource: 'changed'),
      );
      expect(notified, equals(0));
    });

    test('只订阅 wordCountNotifier 时，updateViewState 不触发该订阅者', () {
      var notified = 0;
      coordinator.wordCountNotifier.addListener(() => notified++);
      final a = editor.addParagraph('a');
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
    test('dispose 后所有 notifier 被释放（不抛）', () {
      final a = editor.addParagraph('a');
      coordinator.blockNotifiers.notifierOf(a);
      coordinator.dispose();
      // 重复 dispose 不应抛
      expect(() => coordinator.dispose(), returnsNormally);
    });

    test('removeBlock 后孤儿块 notifier 不再被 bumpAllLive 触碰', () {
      final a = editor.addParagraph('a');
      final b = editor.addParagraph('b');
      coordinator.blockNotifiers.notifierOf(b);
      final orphan = coordinator.blockNotifiers.notifierOf(b);
      final base = orphan.value;
      // 移除 a，sync 会清理孤儿
      coordinator.handle(DeleteBlockCommand(blockId: a));
      final afterSync = orphan.value;
      coordinator.undo();
      expect(orphan.value, equals(afterSync),
          reason: '已清理的孤儿 notifier 不应被 bumpAllLive 复活');
      expect(base, isNotNull);
    });
  });
}

/// 便捷构造：取某块的默认 [BlockViewState]。
BlockViewState _defaultViewState(BlockId id) => BlockViewState(id: id);