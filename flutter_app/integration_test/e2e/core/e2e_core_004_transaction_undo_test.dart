/// E2E-CORE-004：Transaction Undo/Redo（Phase 3.6.1）。
///
/// 验证编辑内容后 AppBar Undo/Redo 按钮的正确行为。
///
/// 验证点：
/// 1. 初始状态 Undo 禁用
/// 2. 编辑后 Undo 启用
/// 3. 点击 Undo 后内容恢复，Redo 启用
/// 4. 点击 Redo 后内容恢复编辑态
/// 5. Undo/Redo 按钮状态随操作正确切换
///
/// 对应 E2E_TEST_PLAN §3.1 CORE-004。
library;

import 'package:flutter_test/flutter_test.dart';

import '../helpers/e2e_app.dart';
import '../helpers/e2e_editor.dart';
import '../helpers/e2e_assertions.dart';

void main() {
  group('E2E-CORE-004: Transaction Undo/Redo', () {
    testWidgets('编辑 → Undo → 恢复 → Redo → 恢复', (tester) async {
      await pumpE2EApp(tester, seedSelector: 0);

      // 初始状态：Undo 禁用
      expectUndoDisabled(tester);
      expectRedoDisabled(tester);

      // 聚焦段落块并编辑
      await tapBlockByText(tester, 'Hello, Block Editor!');
      await enterTextInFocusedBlock(tester, 'Undo 测试文本');

      // 点击标题块使段落失焦 → 触发 commit → undo 栈有内容
      await tapBlockByText(tester, 'FormulaFix Demo');

      // 编辑后 Undo 启用
      expectUndoEnabled(tester);
      expectRedoDisabled(tester);
      // 标题块内容可见（渲染态）
      expectTextVisible(tester, 'FormulaFix Demo');

      // 点击 Undo → 恢复原始内容
      await tapUndo(tester);
      // 验证段落块已恢复原始内容
      expectTextVisible(tester, 'Hello, Block Editor!');
      expectTextNotVisible(tester, 'Undo 测试文本');
      expectUndoDisabled(tester);
      expectRedoEnabled(tester);

      // 点击 Redo → 恢复编辑内容
      await tapRedo(tester);
      expectTextVisible(tester, 'Undo 测试文本');
      expectTextNotVisible(tester, 'Hello, Block Editor!');
      expectUndoEnabled(tester);
      expectRedoDisabled(tester);
    });

    testWidgets('Undo 后编辑 → Redo 栈清空', (tester) async {
      await pumpE2EApp(tester, seedSelector: 0);

      // 第一次编辑并 commit
      await tapBlockByText(tester, 'Hello, Block Editor!');
      await enterTextInFocusedBlock(tester, '第一次编辑');
      await tapBlockByText(tester, 'FormulaFix Demo');  // 失焦 commit

      // Undo 回原始
      await tapUndo(tester);
      expectTextVisible(tester, 'Hello, Block Editor!');
      expectRedoEnabled(tester);

      // 第二次编辑（新编辑清空 Redo 栈）
      await tapBlockByText(tester, 'Hello, Block Editor!');
      await enterTextInFocusedBlock(tester, '第二次编辑');
      await tapBlockByText(tester, 'FormulaFix Demo');  // 失焦 commit
      expectRedoDisabled(tester);
      expectTextVisible(tester, '第二次编辑');
    });
  });
}