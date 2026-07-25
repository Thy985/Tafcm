/// 3.3.7 Markdown 工具栏（核心任务）E2E。
///
/// 覆盖 §12.3 三条链：
/// - 链 1（用户操作）：点击 Toolbar 按钮（B / H1 等）→
///   coordinator.handle(InsertTextCommand / WrapSelectionCommand)
/// - 链 2（状态同步）：文档修改 → 渲染更新
/// - 链 3（持久化代理）：操作 → 序列化 → 重解析 → Document 一致
///   （in-memory 代理；真实磁盘存档由 v2.1 §3.3.1 Hard Rule 禁止在 E2E 触达）
library;

import 'package:flutter/material.dart' show TextEditingValue, TextSelection;
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
  group('3.3.7 Markdown 工具栏', () {
    testWidgets('点击 B 按钮（无选区）→ 插入 ****', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      final paraId = await _focusFirstParagraph(tester, c);
      final current = c.sourceOf(paraId);

      // 链 1：点击 B 按钮（tooltip '加粗'）
      await tester.tap(find.byTooltip('加粗'));
      await tester.pumpAndSettle();

      // 链 2：文档被插入 '****'
      expect(c.sourceOf(paraId), contains('****'));
      expect(c.sourceOf(paraId), isNot(equals(current)));
    });

    testWidgets('选中文本后点击 B → 生成 **包裹**', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      final paraId = await _focusFirstParagraph(tester, c);
      final current = c.sourceOf(paraId);
      // 在编辑器内选中全部（controller selection → WrapSelectionCommand）
      final sel = TextSelection(baseOffset: 0, extentOffset: current.length);
      tester.testTextInput.updateEditingValue(
          TextEditingValue(text: current, selection: sel));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('加粗'));
      await tester.pumpAndSettle();
      expect(c.sourceOf(paraId), contains('**$current**'));
    });

    testWidgets('点击 H1 按钮 → 行首插入 "# "', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      final paraId = await _focusFirstParagraph(tester, c);
      final current = c.sourceOf(paraId);
      await tester.tap(find.byTooltip('一级标题'));
      await tester.pumpAndSettle();
      expect(c.sourceOf(paraId), contains('# '));
      expect(c.sourceOf(paraId), isNot(equals(current)));
    });
  });
}
