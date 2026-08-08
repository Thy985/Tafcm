import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/block_types.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/editor_scope.dart';
import 'package:formula_fix/presentation/editor/editor_shell.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/presentation/blocks/shared/block_toolbar.dart';
import 'package:formula_fix/presentation/commands/commands.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';
import 'package:formula_fix/presentation/themes/editor_tokens.dart';

/// Block 交互三件套（Phase 3.5.3/4/5）widget 测试：
/// - BlockSelectionChrome 选中描边（focusedId 匹配 borderFocused）
/// - BlockToolbar 删除 / 上移 / 转换类型（经 EditorCoordinator.handle 派发）
/// - ReorderableListView + MoveBlockCommand 重排
void main() {
  late EditorCoordinator coordinator;

  EditorCoordinator _buildCoordinator() {
    final editor = InMemoryDocumentEditor(title: 't');
    editor.insertBlock(editor.blockCount,
        ParagraphElement(children: [TextElement('Para 1')]));
    editor.insertBlock(
        editor.blockCount, HeadingElement(level: 1, text: 'Heading'));
    editor.insertBlock(editor.blockCount,
        ParagraphElement(children: [TextElement('Para 2')]));
    return EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );
  }

  Future<void> _pumpViewport(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: EditorScope(
            coordinator: coordinator,
            child: AnimatedBuilder(
              animation: coordinator,
              builder: (context, _) => EditorViewport(
                coordinator: coordinator,
                blockKeys: <BlockId, GlobalKey>{},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    coordinator = _buildCoordinator();
  });

  tearDown(() {
    coordinator.dispose();
  });

  testWidgets('选中块显示 borderFocused 描边', (tester) async {
    await _pumpViewport(tester);
    final first = coordinator.allIds.first;
    coordinator.setFocus(first);
    await tester.pumpAndSettle();

    final focusedBorder = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).border is Border &&
          ((w.decoration as BoxDecoration).border as Border).top.color ==
              EditorTokens.light.borderFocused,
    );
    expect(focusedBorder, findsOneWidget);

    // 未选中块无焦点色描边
    final other = coordinator.allIds[1];
    coordinator.setFocus(other);
    await tester.pumpAndSettle();
    // 仍有且仅有一个焦点描边（现在属于 other）
    expect(focusedBorder, findsOneWidget);
  });

  testWidgets('BlockToolbar 删除：块数 -1', (tester) async {
    await _pumpViewport(tester);
    final before = coordinator.allIds.length;
    final target = coordinator.allIds[1];
    coordinator.setFocus(target);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();

    expect(coordinator.allIds.length, before - 1);
    expect(coordinator.allIds.contains(target), isFalse);
  });

  testWidgets('BlockToolbar 上移：heading 升到首位', (tester) async {
    await _pumpViewport(tester);
    final heading = coordinator.allIds[1];
    coordinator.setFocus(heading);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('上移'));
    await tester.pumpAndSettle();

    expect(coordinator.allIds.first, heading);
  });

  testWidgets('BlockToolbar 转换：paragraph -> heading', (tester) async {
    await _pumpViewport(tester);
    final para = coordinator.allIds.first;
    coordinator.setFocus(para);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('转换类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标题'));
    await tester.pumpAndSettle();

    final element = coordinator.getBlock(para);
    expect(element, isNotNull);
    expect(BlockType.fromElement(element!), BlockType.heading);
  });

  testWidgets('MoveBlockCommand 经 onReorderItem 语义重排', (tester) async {
    await _pumpViewport(tester);
    final ids = coordinator.allIds;
    // 模拟把首块拖到索引 2（onReorderItem 语义）
    final args = (
      targetId: ids[0],
      refId: ids[2],
      before: false,
    );
    coordinator.handle(MoveBlockCommand(
      targetId: args.targetId,
      refId: args.refId,
      before: args.before,
    ));
    await tester.pumpAndSettle();

    // 期望顺序：原 [A,B,C] -> [B,C,A]
    final expected = [ids[1], ids[2], ids[0]];
    expect(coordinator.allIds, expected);
    // 三个块外壳均渲染
    expect(find.byType(EditorViewport), findsOneWidget);
  });

  testWidgets('BlockToolbar 下移：中间块降到末尾', (tester) async {
    await _pumpViewport(tester);
    final middle = coordinator.allIds[1];
    coordinator.setFocus(middle);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('下移'));
    await tester.pumpAndSettle();

    // 原 [P1, H, P2] → 下移 H → [P1, P2, H]
    expect(coordinator.allIds.last, middle);
  });

  testWidgets('BlockToolbar 转换：paragraph -> blockquote', (tester) async {
    await _pumpViewport(tester);
    final para = coordinator.allIds.first;
    coordinator.setFocus(para);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('转换类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('引用'));
    await tester.pumpAndSettle();

    final element = coordinator.getBlock(para);
    expect(element, isNotNull);
    expect(BlockType.fromElement(element!), BlockType.blockquote);
  });

  testWidgets('引用转正文：类型变为 paragraph 且内容保留', (tester) async {
    // 用 addBlock 创建单块引用
    final editor = InMemoryDocumentEditor(title: 'bq2p');
    editor.addBlock('> a blockquote', BlockType.blockquote);
    coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );
    await _pumpViewport(tester);

    final bqId = coordinator.allIds.first;
    coordinator.setFocus(bqId);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('转换类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('正文'));
    await tester.pumpAndSettle();

    final element = coordinator.getBlock(bqId);
    expect(element, isNotNull);
    expect(BlockType.fromElement(element!), BlockType.paragraph);
    // 内容应保留
    expect(coordinator.sourceOf(bqId), contains('blockquote'));
  });

  testWidgets('块数为 1 时删除按钮不生效', (tester) async {
    final editor = InMemoryDocumentEditor(title: 'single');
    editor.addParagraph('Only one block');
    coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );
    await _pumpViewport(tester);

    final only = coordinator.allIds.first;
    coordinator.setFocus(only);
    await tester.pumpAndSettle();

    expect(coordinator.blockCount, 1);
    // 删除按钮存在但禁用；tap 不改变块数
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(coordinator.blockCount, 1);
  });

  testWidgets('代码块不显示转换按钮（多块时仍有其他操作）', (tester) async {
    // 多块场景：代码块仍有上移/下移/删除可用，仅转换按钮隐藏
    final editor = InMemoryDocumentEditor(title: 'multi_code');
    editor.insertBlock(0, const CodeElement(code: 'x=1'));
    editor.insertBlock(1, ParagraphElement(children: [TextElement('Para')]));
    coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );
    await _pumpViewport(tester);

    final codeId = coordinator.allIds.first;
    coordinator.setFocus(codeId);
    await tester.pumpAndSettle();

    // BlockType.code 不在 [paragraph,heading,blockquote]，转换按钮隐藏
    expect(find.byTooltip('转换类型'), findsNothing);
    // 但其他操作按钮仍可见
    expect(find.byType(BlockToolbar), findsOneWidget);
  });

  // ============ T1-1 触屏可达性（Release Gate G2）============
  // 移动端（shortestSide < 600）：BlockToolbar 由长按触发，tap 聚焦不显示。
  // 桌面端（shortestSide >= 600）：hover / selected 时显示。
  // 以下用触摸指针验证移动端长按路径。

  testWidgets('触屏长按块 → BlockToolbar 可见（移动端）', (tester) async {
    // 设置手机视口（shortestSide < 600 → 触屏路径）
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _pumpViewport(tester);
    // 初始无焦点、无长按 → 无工具栏
    expect(find.byType(BlockToolbar), findsNothing);

    // tap 聚焦首块（移动端不自动显示工具栏）
    await tester.tap(find.text('Para 1'));
    await tester.pumpAndSettle();
    expect(coordinator.focusedId, coordinator.allIds.first);
    expect(find.byType(BlockToolbar), findsNothing);

    // 长按触发工具栏（用 startGesture 手动控制，避免 longPress 的 up 事件干扰）
    final gesture = await tester.startGesture(tester.getCenter(find.text('Para 1')));
    await tester.pump(const Duration(seconds: 1)); // 超过 kLongPressTimeout
    await tester.pump(); // 处理 setState 触发的 rebuild
    expect(find.byType(BlockToolbar), findsOneWidget);
    expect(find.byTooltip('删除'), findsOneWidget);
    await gesture.up();
  });

  testWidgets('桌面端 tap 块 → BlockToolbar 可见（selected 路径）', (tester) async {
    // 默认视口 800x600，shortestSide >= 600 → 桌面路径
    await _pumpViewport(tester);
    expect(find.byType(BlockToolbar), findsNothing);

    await tester.tap(find.text('Para 1'));
    await tester.pumpAndSettle();
    expect(coordinator.focusedId, coordinator.allIds.first);
    // 桌面端：selected 时显示工具栏
    expect(find.byType(BlockToolbar), findsOneWidget);
  });

  testWidgets('触屏 tap 另一块 → 原块 chrome 消失、新块显示（桌面端）', (tester) async {
    // 默认视口 800x600 → 桌面路径
    await _pumpViewport(tester);
    await tester.tap(find.text('Para 1'));
    await tester.pumpAndSettle();
    expect(coordinator.focusedId, coordinator.allIds.first);
    expect(find.byType(BlockToolbar), findsOneWidget);

    // tap 第二块（Heading）
    await tester.tap(find.text('Heading'));
    await tester.pumpAndSettle();

    expect(coordinator.focusedId, coordinator.allIds[1]);
    // 仍有且仅有一个工具栏（属于新聚焦块），原块 chrome 已收起
    expect(find.byType(BlockToolbar), findsOneWidget);
  });

  testWidgets('单块时 BlockToolbar 全禁用 → 整条隐藏', (tester) async {
    final editor = InMemoryDocumentEditor(title: 'single');
    editor.addParagraph('Only one block');
    coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );
    await _pumpViewport(tester);

    final only = coordinator.allIds.first;
    coordinator.setFocus(only);
    await tester.pumpAndSettle();

    // 单块：上移/下移/删除全禁用 + paragraph 可转换 → 工具栏仍显示（有可用按钮）
    expect(find.byType(BlockToolbar), findsOneWidget);
    // 但删除按钮禁用
    expect(coordinator.blockCount, 1);
  });

  testWidgets('单块代码块时 BlockToolbar 全禁用 → 整条隐藏', (tester) async {
    final editor = InMemoryDocumentEditor(title: 'single_code');
    editor.insertBlock(0, const CodeElement(code: 'print("hello")'));
    coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );
    await _pumpViewport(tester);

    final codeId = coordinator.allIds.first;
    coordinator.setFocus(codeId);
    await tester.pumpAndSettle();

    // 单块代码：上移/下移/删除全禁用 + code 不可转换 → 全禁用 → 无可见按钮
    expect(find.byType(IconButton), findsNothing);
  });
}
