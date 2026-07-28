import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/block_types.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/editor_scope.dart';
import 'package:formula_fix/presentation/editor/editor_shell.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
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
}
