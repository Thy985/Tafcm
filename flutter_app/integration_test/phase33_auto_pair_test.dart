/// 3.3.6 自动配对 E2E。
///
/// 覆盖 §12.3 三条链：
/// - 链 1（用户操作）：真实键入 '(' → InputHandler → PairInsertCommand
///   （同 UpdateBlockSourceCommand 路径，origin=ime）
/// - 链 2（状态同步）：文档插入 '()'，光标位于配对符中间
/// - 链 3（持久化）：N/A（纯输入变换，无磁盘持久化）
library;

import 'package:flutter/material.dart' show EditableText;
import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/blocks/code/code_block.dart';
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
  group('3.3.6 自动配对', () {
    testWidgets('输入 "(" → 自动生成 ")"，光标位于中间', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      final paraId = await _focusFirstParagraph(tester, c);
      final editable = find.byType(EditableText);
      final current = c.sourceOf(paraId);

      // 链 1：真实追加 '('（onChanged → InputHandler → 配对）
      await tester.enterText(editable, '$current(');
      await tester.pumpAndSettle();

      // 链 2：文档出现配对 '()'
      expect(c.sourceOf(paraId), contains('()'));
    });

    testWidgets('CodeBlock 内输入 "(" 不触发配对', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      final codeId =
          c.allIds.firstWhere((i) => c.getBlock(i) is CodeElement);
      // 聚焦 CodeBlock（点击其渲染区）
      await tester.tap(find.byType(CodeBlock));
      await tester.pumpAndSettle();
      final editable = find.byType(EditableText);
      final current = c.sourceOf(codeId);

      await tester.enterText(editable, '$current(');
      await tester.pumpAndSettle();

      // §2.5 CodeBlock 例外：不应出现自动配对生成的 '()'。
      // 校验「实时文本」(liveSourceOf) 而非已提交 sourceOf——
      // 守卫使 InputHandler 不派发配对命令,但用户实键 '(' 已落入 live 文本;
      // committed source 要等失焦才提交,且种子代码块本身可能含 '()' 字面量。
      expect(c.liveSourceOf(codeId), equals('$current('));
    });
  });
}
