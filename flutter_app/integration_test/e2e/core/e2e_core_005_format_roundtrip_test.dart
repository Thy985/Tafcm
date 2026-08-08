/// E2E-CORE-005：格式 Round-trip（Phase 3.6.1）。
///
/// 验证工具栏格式按钮（Bold、Heading）的响应与撤销。
///
/// 验证点：
/// 1. 聚焦段落块后工具栏格式按钮可点击
/// 2. 格式操作后输入内容正确显示
/// 3. Undo 后格式操作被撤销
///
/// 对应 E2E_TEST_PLAN §3.1 CORE-005。
library;

import 'package:flutter_test/flutter_test.dart';

import '../helpers/e2e_app.dart';
import '../helpers/e2e_editor.dart';
import '../helpers/e2e_assertions.dart';

void main() {
  group('E2E-CORE-005: Format Round-trip', () {
    testWidgets('Bold 按钮可点击 → 编辑内容显示 → Undo 撤销', (tester) async {
      await pumpE2EApp(tester, seedSelector: 0);

      // 聚焦段落块
      await tapBlockByText(tester, 'Hello, Block Editor!');

      // 点击 Bold 按钮（tooltip: '加粗'）
      await tapToolbarButton(tester, '加粗');

      // 编辑内容（Bold 标记后输入）
      await enterTextInFocusedBlock(tester, '**加粗内容**');

      // 验证内容可见（TextField 中为 '**加粗内容**'，用包含匹配）
      expectTextContaining(tester, '加粗内容');

      // P0 修复后：toolbar action 和 enterText 各产生 1 个 Transaction，
      // 需要 2 次 Undo 完全撤销（先撤销文本输入，再撤销格式操作）。
      await tapUndo(tester); // 撤销 enterText
      await tapUndo(tester); // 撤销 Bold
      // 撤销后应恢复原始内容
      expectTextVisible(tester, 'Hello, Block Editor!');
    });

    testWidgets('Heading 按钮可点击 → 编辑标题内容 → Undo 撤销', (tester) async {
      await pumpE2EApp(tester, seedSelector: 0);

      // 聚焦段落块
      await tapBlockByText(tester, 'Hello, Block Editor!');

      // 点击 H1 按钮（tooltip: '一级标题'）
      await tapToolbarButton(tester, '一级标题');

      // 编辑标题内容
      await enterTextInFocusedBlock(tester, '# 一级标题内容');

      // 验证标题内容可见（TextField 中为 '# 一级标题内容'，用包含匹配）
      expectTextContaining(tester, '一级标题内容');

      // P0 修复后：H1 插入 "# " 和 enterText 各产生 1 个 Transaction，
      // 需要 2 次 Undo 完全撤销。
      await tapUndo(tester); // 撤销 enterText
      await tapUndo(tester); // 撤销 H1 插入
      expectTextVisible(tester, 'Hello, Block Editor!');
    });
  });
}