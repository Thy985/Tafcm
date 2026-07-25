/// 3.3.8 自动续列表 / 引用 / 代码块 E2E。
///
/// 覆盖 §12.3 三条链：
/// - 链 1（用户操作）：输入 "- item" + 回车（\n）→ InputHandler →
///   InsertNewLineWithPrefixCommand
/// - 链 2（状态同步）：自动生成下一行前缀 "- "
/// - 链 3（持久化）：N/A（纯输入变换，无磁盘持久化）
///
/// 注：段落默认 TextInputAction.done，真实软键盘回车发送 "done" 而非 \n；
/// 本测试以 `testTextInput.updateEditingValue` 注入含 \n 的 value 来驱动
/// InputHandler 的续行检测（与 UI 使用同一 InputHandler 路径）。
library;

import 'package:flutter/material.dart' show TextEditingValue, TextSelection;
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
  group('3.3.8 自动续列表', () {
    testWidgets('输入 "- item" + 换行 → 自动生成 "- "', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      final paraId = await _focusFirstParagraph(tester, c);
      final current = c.sourceOf(paraId);

      // 链 1：注入 "- item\n"（\n 触发 AutoContinueRules）
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: '$current\n- item\n',
        selection: TextSelection.collapsed(offset: '$current\n- item\n'.length),
      ));
      await tester.pumpAndSettle();

      // 链 2：自动续行，末尾出现 "- "
      expect(c.sourceOf(paraId), contains('\n- item\n- '));
    });

    testWidgets('CodeBlock 内回车不续行', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      final codeId =
          c.allIds.firstWhere((i) => c.getBlock(i) is CodeElement);
      await tester.tap(find.byType(CodeBlock));
      await tester.pumpAndSettle();
      final current = c.sourceOf(codeId);

      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: '$current\n',
        selection: TextSelection.collapsed(offset: '$current\n'.length),
      ));
      await tester.pumpAndSettle();

      // CodeBlock：\n 是普通换行，不应追加列表前缀
      expect(c.sourceOf(codeId).contains('- '), isFalse);
    });
  });
}
