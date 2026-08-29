/// TaskListBlock WYSIWYG 渲染 + 勾选翻转测试（P0-1 UI/UX 修复）。
///
/// 验证：
/// - 未勾选：outline checkbox + 文本（不再显示原始 Markdown 源码）
/// - 已勾选：filled checkbox + 删除线文本
/// - 点击 checkbox 翻转勾选（source `- [ ]` ↔ `- [x]`，经 Command 走 undo 栈）
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/block_types.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/blocks/task/task_list_block.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/editor_scope.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';
import 'package:formula_fix/presentation/states/block_view_state.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';

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
    // 用 AnimatedBuilder 包裹：勾选后 coordinator notifyListeners → 块以新 element 重建
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: EditorScope(
            coordinator: coordinator,
            child: AnimatedBuilder(
              animation: coordinator,
              builder: (context, _) => TaskListBlock(
                state: BlockViewState(id: id),
                element: coordinator.getBlock(id)! as TaskListItemElement,
                coordinator: coordinator,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() => coordinator.dispose());

  testWidgets('未勾选：outline checkbox + 文本，不显示源码', (tester) async {
    coordinator = _build([
      TaskListItemElement(children: [TextElement('买牛奶')], checked: false),
    ]);
    await _pumpBlock(tester, coordinator.allIds.first);

    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    expect(find.text('买牛奶'), findsOneWidget);
    expect(find.text('- [ ] 买牛奶'), findsNothing);
  });

  testWidgets('已勾选：filled checkbox + 删除线文本', (tester) async {
    coordinator = _build([
      TaskListItemElement(children: [TextElement('完成')], checked: true),
    ]);
    await _pumpBlock(tester, coordinator.allIds.first);

    expect(find.byIcon(Icons.check_box), findsOneWidget);
    final rich = tester.widget<Text>(find.text('完成'));
    expect(rich.textSpan?.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('点击 checkbox 翻转勾选（source 更新 + 图标切换）', (tester) async {
    coordinator = _build([
      TaskListItemElement(children: [TextElement('买牛奶')], checked: false),
    ]);
    final id = coordinator.allIds.first;
    await _pumpBlock(tester, id);

    expect(coordinator.sourceOf(id), '- [ ] 买牛奶');
    await tester.tap(find.byIcon(Icons.check_box_outline_blank));
    await tester.pumpAndSettle();

    expect(coordinator.sourceOf(id), '- [x] 买牛奶');
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);
  });
}
