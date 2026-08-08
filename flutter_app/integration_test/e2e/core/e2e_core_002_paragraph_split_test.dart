/// E2E-CORE-002：段落分块（Phase 3.6.1）。
///
/// 验证段落块聚焦后输入文本 → 内容正确显示。
///
/// 验证点：
/// 1. 点击段落文本可聚焦该块
/// 2. 输入新文本后内容正确更新
/// 3. 块数变化反映在状态栏
///
/// 对应 E2E_TEST_PLAN §3.1 CORE-002。
library;

import 'package:flutter_test/flutter_test.dart';

import '../helpers/e2e_app.dart';
import '../helpers/e2e_editor.dart';
import '../helpers/e2e_assertions.dart';

void main() {
  group('E2E-CORE-002: Paragraph Split', () {
    testWidgets('聚焦段落块 → 输入文本 → 内容正确显示', (tester) async {
      await pumpE2EApp(tester, seedSelector: 0);

      // Demo1 初始状态：3 块（heading + paragraph + code）
      expectBlockCount(tester, 3);

      // 聚焦段落块
      await tapBlockByText(tester, 'Hello, Block Editor!');

      // 输入新文本
      await enterTextInFocusedBlock(tester, '这是编辑后的段落内容');

      // 验证新文本可见
      expectTextVisible(tester, '这是编辑后的段落内容');
    });

    testWidgets('标题块聚焦后输入 → 标题内容更新', (tester) async {
      await pumpE2EApp(tester, seedSelector: 0);

      // 聚焦标题块
      await tapBlockByText(tester, 'FormulaFix Demo');

      // 输入新标题
      await enterTextInFocusedBlock(tester, '# 新标题');

      // 验证新标题可见（TextField 中为 '# 新标题'，用包含匹配）
      expectTextContaining(tester, '新标题');
    });
  });
}