/// ListBlock WYSIWYG 渲染测试（P0-1 UI/UX 修复）。
///
/// 验证：
/// - 无序列表渲染 `•` 标记 + 行内文本（不再显示原始 Markdown 源码）
/// - 有序列表按连续兄弟位置编号（1. / 2.）
/// - 有序列表被非列表块打断后重新从 1 编号
/// - ADR-0029 嵌套子项递归渲染
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/blocks/list/list_block.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/editor_scope.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/states/block_view_state.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';

void main() {
  late EditorCoordinator coordinator;

  EditorCoordinator _build(List<DocumentElement> blocks) {
    final editor = InMemoryDocumentEditor(title: 't');
    for (var i = 0; i < blocks.length; i++) {
      editor.insertBlock(editor.blockCount, blocks[i]);
    }
    return EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 50),
    );
  }

  Future<void> _pumpBlock(WidgetTester tester, BlockId id) async {
    final element = coordinator.getBlock(id)!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: EditorScope(
            coordinator: coordinator,
            child: ListBlock(
              state: BlockViewState(id: id),
              element: element as ListElement,
              coordinator: coordinator,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() => coordinator.dispose());

  testWidgets('无序列表：渲染 • 标记 + 文本，不显示源码', (tester) async {
    coordinator = _build([
      ListElement(children: [TextElement('苹果')]),
    ]);
    await _pumpBlock(tester, coordinator.allIds.first);

    expect(find.text('•'), findsOneWidget);
    expect(find.text('苹果'), findsOneWidget);
    expect(find.text('- 苹果'), findsNothing);
  });

  testWidgets('有序列表：连续两项编号 1. / 2.', (tester) async {
    coordinator = _build([
      ListElement(children: [TextElement('第一')], ordered: true),
      ListElement(children: [TextElement('第二')], ordered: true),
    ]);
    final ids = coordinator.allIds;

    await _pumpBlock(tester, ids[0]);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('第一'), findsOneWidget);

    await _pumpBlock(tester, ids[1]);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('第二'), findsOneWidget);
  });

  testWidgets('有序列表：被段落打断后重新从 1 编号', (tester) async {
    coordinator = _build([
      ListElement(children: [TextElement('a')], ordered: true),
      ParagraphElement(children: [TextElement('分隔')]),
      ListElement(children: [TextElement('b')], ordered: true),
    ]);
    final ids = coordinator.allIds;

    await _pumpBlock(tester, ids[2]);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    expect(find.text('2.'), findsNothing);
  });

  testWidgets('嵌套列表：子项递归渲染（ADR-0029）', (tester) async {
    coordinator = _build([
      ListElement(
        children: [TextElement('父项')],
        nested: [
          ListElement(children: [TextElement('子项')], indent: 1),
        ],
      ),
    ]);
    await _pumpBlock(tester, coordinator.allIds.first);

    expect(find.text('父项'), findsOneWidget);
    expect(find.text('子项'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(2));
  });
}
