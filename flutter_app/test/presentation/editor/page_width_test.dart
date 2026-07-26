/// Page Width 单元测试：Phase 3.4 Slice 5 / 3.4.8 页面宽度控制。
///
/// 落地 Phase 3.4 Task Contract §3.5（极简布局）：
/// `Workspace` 将 `EditorViewport` 包在 `Center` + `ConstrainedBox(maxWidth: 720)` 中，
/// 宽屏（> 720）下内容约束并居中，窄屏（< 720）不受影响。纯布局、无状态。
///
/// 覆盖范围：
/// - `kMaxPageWidth` 常量值为 720.0
/// - `Workspace` 渲染树中存在 `ConstrainedBox(maxWidth: 720)`，且 `EditorViewport` 为其后代
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/editing/block_types.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/editor_scope.dart';
import 'package:formula_fix/presentation/editor/editor_shell.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';

void main() {
  late InMemoryDocumentEditor editor;
  late EditorHistory history;
  late EditorCoordinator coordinator;

  setUp(() {
    editor = InMemoryDocumentEditor();
    history = EditorHistory();
    coordinator = EditorCoordinator(editor: editor, history: history);
  });

  /// 构造测试 widget：EditorScope 提供 Coordinator（BlockRenderer 经
  /// `EditorScope.of` 读取），Workspace 内嵌本切片新增的 Center + ConstrainedBox。
  Widget buildTestWidget() {
    return MaterialApp(
      home: Scaffold(
        body: EditorScope(
          coordinator: coordinator,
          child: Workspace(
            coordinator: coordinator,
            scrollController: null,
            blockKeys: const <BlockId, GlobalKey>{},
          ),
        ),
      ),
    );
  }

  test('kMaxPageWidth 常量值为 720.0', () {
    expect(kMaxPageWidth, equals(720.0));
  });

  testWidgets('Workspace 将 EditorViewport 约束在 maxWidth=720 并居中', (
    tester,
  ) async {
    editor.addParagraph('页面宽度控制：宽屏下内容应居中且限宽 720');
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // 应存在一个 maxWidth == kMaxPageWidth 的 ConstrainedBox（本切片新增）。
    final constrainedFinder = find.byWidgetPredicate(
      (w) => w is ConstrainedBox && w.constraints.maxWidth == kMaxPageWidth,
    );
    expect(constrainedFinder, findsWidgets);

    // EditorViewport 必须是该 ConstrainedBox 的后代（即被限宽包裹）。
    expect(
      find.descendant(of: constrainedFinder, matching: find.byType(EditorViewport)),
      findsOneWidget,
    );
  });
}
