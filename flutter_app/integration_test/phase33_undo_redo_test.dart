/// 3.3.5 撤销/重做按钮接入 UI E2E。
///
/// 覆盖 §12.3 三条链：
/// - 链 1（用户操作）：点击 Toolbar/AppBar 按钮（真实）→ coordinator.handle / undo / redo
/// - 链 2（状态同步）：canUndo/canRedo → AppBar Undo/Redo 按钮 enabled；
///   undo() → 文档恢复到输入前
/// - 链 3（持久化）：N/A（内存 EditorHistory，无磁盘持久化；
///   redo 恢复由 EditorHistory 保证，非存档）
library;

import 'package:flutter/material.dart' show EditableText, TextInputAction;
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/editor/editor_scope.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/core/editing/block_types.dart';
import 'helpers/test_fixture.dart';

EditorCoordinator _coordinator(WidgetTester tester) =>
    tester.widget<EditorScope>(find.byType(EditorScope)).coordinator;

Future<BlockId> _focusFirstParagraph(
    WidgetTester tester, EditorCoordinator c) async {
  final id = c.allIds.firstWhere((i) => c.getBlock(i) is ParagraphElement);
  await tester.tap(find.text('Hello, Block Editor!'));
  await tester.pumpAndSettle();
  return id;
}

void main() {
  group('3.3.5 撤销/重做', () {
    testWidgets('输入后 Undo 按钮启用；点击 Undo 内容恢复', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      final paraId = await _focusFirstParagraph(tester, c);
      final editable = find.byType(EditableText);
      final current = c.sourceOf(paraId);

      // 初始 Undo 禁用
      expect(c.canUndo, isFalse);
      expect(find.byTooltip('撤销'), findsOneWidget);

      // 链 1：真实输入
      await tester.enterText(editable, '$current X');
      await tester.pumpAndSettle();
      // ADR-0012：canUndo 仅在 Transaction Commit 后为真。
      // 纯文本输入不进 History,需先失焦提交。
      // （AppBar 标题与正文首块同名 → tap 命中 2 个 widget,改为键盘 done 动作）
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.canUndo, isTrue);

      // 链 1+2：点击 AppBar Undo 按钮
      await tester.tap(find.byTooltip('撤销'));
      await tester.pumpAndSettle();
      expect(c.canRedo, isTrue);
      // 文档恢复到输入前
      expect(c.sourceOf(paraId), equals(current));
    });

    testWidgets('Undo 后 Redo 按钮启用；点击 Redo 内容重新出现', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      final paraId = await _focusFirstParagraph(tester, c);
      final editable = find.byType(EditableText);
      final current = c.sourceOf(paraId);
      await tester.enterText(editable, '$current X');
      await tester.pumpAndSettle();
      // ADR-0012：失焦提交后 Undo 才可用（否则撤销按钮 disabled）。
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('撤销'));
      await tester.pumpAndSettle();
      expect(c.canRedo, isTrue);
      await tester.tap(find.byTooltip('重做'));
      await tester.pumpAndSettle();
      expect(c.sourceOf(paraId), equals('$current X'));
    });
  });
}
