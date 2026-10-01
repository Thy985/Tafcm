/// #246 Widget 级验证：证明「块级重建隔离」在真实 widget 树生效。
///
/// **背景**（Issue #246）：`EditorPage` 曾用 `AnimatedBuilder(animation: coordinator)`
/// 重建整棵 `EditorShell`，每次按键都重建 AppBar + StatusBar + Workspace +
/// MarkdownToolbar + 所有可见块。
///
/// **本测试做法**：在树中插入重建计数探针，模拟 chrome 层订阅结构，
/// 然后触发输入路径，断言：
/// 1. `updateLiveSource` **不**触发结构级重建探针
/// 2. `updateLiveSource` **只**触发目标块的探针，其他块探针不动
/// 3. 块增删**会**触发结构级探针
///
/// **不依赖真实 EditorShell**：直接搭最小树（视口 + 块级 ValueListenableBuilder），
/// 与 `workspace.dart` / `editor_shell.dart` 中的订阅结构一一对应，
/// 避免把整个编辑器的依赖（Riverpod / GoRouter / 文件树）拖进单测。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/presentation/commands/commands.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';

/// 重建计数探针（记录自身 build() 被调用的次数）。
class BuildCounter {
  int count = 0;
}

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

  /// 搭建与 `EditorViewport` 同构的最小树：
  /// - 外层订阅 `structureNotifier`（结构变化）
  /// - 每块包一层 `ValueListenableBuilder`（块级变化）
  Widget buildViewport({
    required BuildCounter structureCounter,
    required Map<BlockId, BuildCounter> blockCounters,
  }) {
    return ValueListenableBuilder<int>(
      valueListenable: coordinator.structureNotifier,
      builder: (context, _, __) {
        structureCounter.count++;
        final ids = coordinator.allIds;
        return Column(
          children: [
            for (final id in ids)
              ValueListenableBuilder<int>(
                key: ValueKey(id),
                valueListenable: coordinator.blockNotifiers.notifierOf(id),
                builder: (context, _, ___) {
                  blockCounters.putIfAbsent(id, BuildCounter.new).count++;
                  return SizedBox(height: 20, child: Text(coordinator.sourceOf(id)));
                },
              ),
          ],
        );
      },
    );
  }

  testWidgets('#246 输入不触发结构级重建，仅目标块重建', (tester) async {
    final a = editor.addParagraph('hello');
    final b = editor.addParagraph('world');
    final c = editor.addParagraph('third');

    final structureCounter = BuildCounter();
    final blockCounters = <BlockId, BuildCounter>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildViewport(
            structureCounter: structureCounter,
            blockCounters: blockCounters,
          ),
        ),
      ),
    );

    // 首帧已 build 一次
    expect(structureCounter.count, 1);
    expect(blockCounters[a]!.count, 1);
    expect(blockCounters[b]!.count, 1);
    expect(blockCounters[c]!.count, 1);

    // —— 模拟一次按键：updateLiveSource —— //
    coordinator.updateLiveSource(a, 'hello!');
    await tester.pump();

    // 结构未变：视口不重建
    expect(structureCounter.count, 1,
        reason: '#246 核心断言：块内文本变化不得重建视口 / ReorderableListView');

    // 仅目标块重建
    expect(blockCounters[a]!.count, 2, reason: '目标块应重建');
    expect(blockCounters[b]!.count, 1, reason: '非目标块不应重建');
    expect(blockCounters[c]!.count, 1, reason: '非目标块不应重建');
  });

  testWidgets('#246 连续 10 次按键：结构重建 0 次，仅焦点块重建 10 次',
      (tester) async {
    final a = editor.addParagraph('a');
    final b = editor.addParagraph('b');
    final c = editor.addParagraph('c');

    final structureCounter = BuildCounter();
    final blockCounters = <BlockId, BuildCounter>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildViewport(
            structureCounter: structureCounter,
            blockCounters: blockCounters,
          ),
        ),
      ),
    );

    for (var i = 0; i < 10; i++) {
      coordinator.updateLiveSource(a, 'a$i');
      await tester.pump();
    }

    expect(structureCounter.count, 1,
        reason: '10 次按键后结构仍不应重建（修复前为 10 次整树重建）');
    expect(blockCounters[a]!.count, 11);
    expect(blockCounters[b]!.count, 1);
    expect(blockCounters[c]!.count, 1);
  });

  testWidgets('#246 焦点切换只重建新旧两块', (tester) async {
    final a = editor.addParagraph('a');
    final b = editor.addParagraph('b');
    final c = editor.addParagraph('c');

    final structureCounter = BuildCounter();
    final blockCounters = <BlockId, BuildCounter>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildViewport(
            structureCounter: structureCounter,
            blockCounters: blockCounters,
          ),
        ),
      ),
    );

    coordinator.setFocus(a);
    await tester.pump();
    expect(blockCounters[a]!.count, 2);
    expect(blockCounters[b]!.count, 1);
    expect(blockCounters[c]!.count, 1);

    // a → b
    coordinator.setFocus(b);
    await tester.pump();
    expect(blockCounters[a]!.count, 3, reason: '旧聚焦块应重建（切回 rendered）');
    expect(blockCounters[b]!.count, 2, reason: '新聚焦块应重建（切到 editing）');
    expect(blockCounters[c]!.count, 1, reason: '无关块不应重建');
    expect(structureCounter.count, 1, reason: '焦点切换不是结构变化');
  });

  testWidgets('#246 insertBlock 触发结构重建，新块可见', (tester) async {
    final structureCounter = BuildCounter();
    final blockCounters = <BlockId, BuildCounter>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildViewport(
            structureCounter: structureCounter,
            blockCounters: blockCounters,
          ),
        ),
      ),
    );

    expect(find.byType(Text), findsNothing);

    // 直接 insertBlock：块集合变化 → structureNotifier 递增 → 视口重建
    editor.addParagraph('new block');
    coordinator.notifyListeners();
    await tester.pump();

    expect(structureCounter.count, 2, reason: '块集合变化必须重建视口');
    expect(find.text('new block'), findsOneWidget,
        reason: '结构变化后新块必须真的渲染出来');
  });

  testWidgets('#246 走 handle(UpdateBlockSourceCommand) 不重建视口', (tester) async {
    // 对应真实按键路径：BaseBlockState._commitSource → handle → replaceBlock
    final structureCounter = BuildCounter();
    final blockCounters = <BlockId, BuildCounter>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildViewport(
            structureCounter: structureCounter,
            blockCounters: blockCounters,
          ),
        ),
      ),
    );

    final a = editor.addParagraph('a');
    coordinator.notifyListeners();
    await tester.pump();
    final afterInsert = structureCounter.count;

    // 模拟连续按键
    for (var i = 0; i < 5; i++) {
      coordinator.handle(
        UpdateBlockSourceCommand(blockId: a, newSource: 'a$i'),
      );
      await tester.pump();
    }

    expect(structureCounter.count, afterInsert,
        reason: '#246 核心：5 次按键 commit 后视口重建次数不变');
    expect(find.text('a4'), findsOneWidget,
        reason: '目标块内容确实更新了（局部刷新有效）');
  });

  testWidgets('#246 chrome 层选择订阅：只关心块数的不被按键唤醒', (tester) async {
    final a = editor.addParagraph('a');
    var blockCountRebuilds = 0;
    var wordCountRebuilds = 0;
    var titleRebuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ValueListenableBuilder<int>(
                valueListenable: coordinator.blockCountNotifier,
                builder: (context, v, _) {
                  blockCountRebuilds++;
                  return Text('blocks: $v');
                },
              ),
              ValueListenableBuilder<int>(
                valueListenable: coordinator.wordCountNotifier,
                builder: (context, v, _) {
                  wordCountRebuilds++;
                  return Text('words: $v');
                },
              ),
              ValueListenableBuilder<String>(
                valueListenable: coordinator.titleNotifier,
                builder: (context, v, _) {
                  titleRebuilds++;
                  return Text('title: $v');
                },
              ),
            ],
          ),
        ),
      ),
    );

    expect(blockCountRebuilds, 1);
    expect(wordCountRebuilds, 1);
    expect(titleRebuilds, 1);

    coordinator.updateLiveSource(a, 'a changed');
    await tester.pump();

    expect(titleRebuilds, 1, reason: '标题没变，不该重建');
    expect(blockCountRebuilds, 1, reason: '块数没变，不该重建');
    // wordCount 确实变了（live source 长度变化）→ 应重建
    expect(wordCountRebuilds, 2, reason: '字数变了，应重建');

    expect(find.text('blocks: 1'), findsOneWidget);
    expect(find.text('title: 未命名'), findsOneWidget);
  });

  testWidgets('#246 wordCountNotifier 首帧即为真实字数（非 0）', (tester) async {
    editor.addParagraph('hello'); // 5
    editor.addParagraph('world'); // 5

    var initialWords = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: coordinator.wordCountNotifier,
            builder: (context, v, _) {
              if (initialWords == -1) initialWords = v;
              return Text('words: $v');
            },
          ),
        ),
      ),
    );

    expect(initialWords, 10,
        reason: '打开已有内容的文档时，首帧字数不能显示 0');
    expect(find.text('words: 10'), findsOneWidget);
  });
}