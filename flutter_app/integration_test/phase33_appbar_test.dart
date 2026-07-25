/// 3.3.1 AppBar 标题 + 修改状态（•）E2E。
///
/// 覆盖 §12.3 三条链：
/// - 链 1（用户操作）：聚焦段落并真实输入 → InputHandler → UpdateBlockSourceCommand
/// - 链 2（状态同步）：isDirty 变化 → AnimatedBuilder 重建 → AppBar 显示 '•'
/// - 链 3（持久化）：本测试不覆盖（标题来自 InMemoryDocumentEditor.title，
///   真实磁盘存档由 v2.1 §3.3.1 Hard Rule 禁止在 E2E 触达；
///   「保存→状态消失」通过 coordinator.markSaved() 验证纯状态层）。
///
/// 真实用户路径：启动 App → 打开文档 → AppBar 显示标题 →
/// 修改内容 → 出现修改状态（•）→ 保存后状态消失。
library;

import 'package:flutter/material.dart' show EditableText;
import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/editor/editor_scope.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/chrome/editor_app_bar.dart';
import 'package:formula_fix/core/editing/block_types.dart';
import 'helpers/test_fixture.dart';

/// 从 widget 树取出真实 [EditorCoordinator]（UI 绑定的同一实例）。
EditorCoordinator _coordinator(WidgetTester tester) =>
    tester.widget<EditorScope>(find.byType(EditorScope)).coordinator;

/// 聚焦第一个段落块并返回其 [BlockId]（点击渲染态文本进入 editing 态）。
Future<BlockId> _focusFirstParagraph(
    WidgetTester tester, EditorCoordinator c) async {
  final id = c.allIds.firstWhere((i) => c.getBlock(i) is ParagraphElement);
  await tester.tap(find.text('Hello, Block Editor!'));
  await tester.pumpAndSettle();
  return id;
}

void main() {
  group('3.3.1 AppBar 标题 + 修改状态', () {
    testWidgets('启动后 AppBar 显示文档标题，初始无修改标记', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);

      // 链 2：coordinator.title 透传到 AppBar 标题
      expect(c.title, 'FormulaFix Demo');
      // 仅限定 AppBar 子树：正文首块（Heading）也渲染同名文本。
      expect(
        find.descendant(
          of: find.byType(EditorAppBar),
          matching: find.text('FormulaFix Demo'),
        ),
        findsOneWidget,
      );
      // 种子文档已 markSaved()，无 '•'
      expect(c.isDirty, isFalse);
      expect(find.text('•', findRichText: true), findsNothing);
    });

    testWidgets('修改内容 → AppBar 出现修改状态（•）', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      final paraId = await _focusFirstParagraph(tester, c);

      // 链 1：真实输入 'X'（经 InputHandler → UpdateBlockSourceCommand）
      final editable = find.byType(EditableText);
      final current = c.sourceOf(paraId);
      await tester.enterText(editable, '$current X');
      await tester.pumpAndSettle();

      // 链 2：isDirty → AnimatedBuilder 重建 → '•' 出现
      expect(c.isDirty, isTrue);
      expect(find.text('•', findRichText: true), findsOneWidget);
      // 仅限定 AppBar 子树：正文首块（Heading）也渲染同名文本。
      expect(
        find.descendant(
          of: find.byType(EditorAppBar),
          matching: find.text('FormulaFix Demo'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('保存后修改状态消失（markSaved）', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      final paraId = await _focusFirstParagraph(tester, c);
      final editable = find.byType(EditableText);
      final current = c.sourceOf(paraId);
      await tester.enterText(editable, '$current X');
      await tester.pumpAndSettle();
      expect(c.isDirty, isTrue);
      expect(find.text('•', findRichText: true), findsOneWidget);

      // 链 3（状态层代理）：保存清除 dirty → '•' 消失
      c.markSaved();
      await tester.pumpAndSettle();
      expect(c.isDirty, isFalse);
      expect(find.text('•', findRichText: true), findsNothing);
    });
  });
}
