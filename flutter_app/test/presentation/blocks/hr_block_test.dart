/// HorizontalRuleBlock WYSIWYG 渲染测试（P0-1 UI/UX 修复）。
///
/// 验证：渲染分割线容器，不再显示原始 Markdown 源码 `---`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/block_types.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/blocks/hr/hr_block.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/editor_scope.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';
import 'package:formula_fix/presentation/states/block_view_state.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';
import 'package:formula_fix/presentation/themes/editor_tokens.dart';

void main() {
  late EditorCoordinator coordinator;

  EditorCoordinator _build() {
    final editor = InMemoryDocumentEditor(title: 't');
    editor.insertBlock(editor.blockCount, const HorizontalRuleElement());
    return EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 50),
    );
  }

  Future<void> _pump(WidgetTester tester, BlockId id) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: EditorScope(
            coordinator: coordinator,
            child: HorizontalRuleBlock(
              state: BlockViewState(id: id),
              element: coordinator.getBlock(id)! as HorizontalRuleElement,
              coordinator: coordinator,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() => coordinator.dispose());

  testWidgets('分隔线：渲染分割线容器，不显示 --- 源码', (tester) async {
    coordinator = _build();
    await _pump(tester, coordinator.allIds.first);

    expect(find.text('---'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is Container && w.color == EditorTokens.light.borderDefault,
      ),
      findsOneWidget,
    );
  });
}
