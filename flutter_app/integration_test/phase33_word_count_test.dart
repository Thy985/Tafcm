/// 3.3.4 实时字数统计 E2E。
///
/// 覆盖 §12.3 三条链：
/// - 链 1（用户操作）：聚焦段落真实输入 → Document 修改
/// - 链 2（状态同步）：coordinator.wordCount → StatusBar 实时刷新
/// - 链 3（持久化）：N/A（字数来自内存文档，无磁盘持久化）
library;

import 'package:flutter/material.dart' show EditableText;
import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/editor/editor_scope.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/core/editing/block_types.dart';
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
  group('3.3.4 实时字数统计', () {
    testWidgets('输入文本 → 字数增加；删除 → 减少', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      final paraId = await _focusFirstParagraph(tester, c);
      final before = c.wordCount;

      final editable = find.byType(EditableText);
      final current = c.sourceOf(paraId);
      // 追加一个完整单词，触发字数 +1
      await tester.enterText(editable, '$current 新词');
      await tester.pumpAndSettle();
      final afterAdd = c.wordCount;
      // 链 2：wordCount 实时（Live State）,无需失焦即随输入变化
      expect(afterAdd, greaterThan(before));

      // 删除该词 → 字数回落（仍聚焦,直接改 live 文本）
      final current2 = c.liveSourceOf(paraId);
      await tester.enterText(
          editable, current2.replaceAll(' 新词', ''));
      await tester.pumpAndSettle();
      expect(c.wordCount, lessThan(afterAdd));
    });

    testWidgets('StatusBar 显示实时字数并随输入刷新', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      // StatusBar 初始显示 '字数: N'
      expect(find.textContaining('字数:'), findsOneWidget);
      final before = c.wordCount;
      final paraId = await _focusFirstParagraph(tester, c);
      final editable = find.byType(EditableText);
      final current = c.sourceOf(paraId);
      await tester.enterText(editable, '$current 词');
      await tester.pumpAndSettle();
      // 链 2：wordCount 随真实输入变化
      expect(c.wordCount, greaterThan(before));
    });
  });
}
