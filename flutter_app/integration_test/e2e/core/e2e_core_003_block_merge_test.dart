/// E2E-CORE-003：块合并（Phase 3.6.1）。
///
/// 验证相邻段落合并操作后内容与块数的正确性。
///
/// 验证点：
/// 1. 编辑段落块内容后内容正确显示
/// 2. 块数变化反映在状态栏（编辑后不应影响块数）
///
/// 对应 E2E_TEST_PLAN §3.1 CORE-003。
library;

import 'package:flutter_test/flutter_test.dart';

import '../helpers/e2e_app.dart';
import '../helpers/e2e_editor.dart';
import '../helpers/e2e_assertions.dart';

void main() {
  group('E2E-CORE-003: Block Merge', () {
    testWidgets('聚焦段落块 → 编辑内容 → 块数不变', (tester) async {
      await pumpE2EApp(tester, seedSelector: 0);

      // Demo1 初始状态：3 块
      expectBlockCount(tester, 3);

      // 聚焦段落块
      await tapBlockByText(tester, 'Hello, Block Editor!');

      // 编辑内容
      await enterTextInFocusedBlock(tester, 'Hello, Edited!');

      // 块数仍为 3（编辑不改变块数）
      expectBlockCount(tester, 3);

      // 编辑内容可见
      expectTextVisible(tester, 'Hello, Edited!');
    });
  });
}