/// E2E-EXT-002：List Behavior Contract（Phase 3.6.2）。
///
/// Behavior Contract Test — 定义未来 List 编辑行为，当前标记 skip。
/// 当 ListBlock 就绪后，删除 skip 注释即可启用。
///
/// 契约定义：
/// 1. 输入 "- apple" → Enter → 产生两个列表项
/// 2. 空列表项按 Enter → 退出列表 → 变普通段落
///
/// 对应 E2E_TEST_PLAN §3.3.2 EXT-002。
library;

import 'package:flutter_test/flutter_test.dart';

import '../helpers/e2e_app.dart';
import '../helpers/e2e_editor.dart';

void main() {
  group('E2E-EXT-002: List Behavior Contract', () {
    testWidgets(
      '输入列表项 → Enter 延续列表',
      (tester) async {
        await pumpE2EApp(tester, seedSelector: 0);

        // 聚焦段落块
        await tapBlockByText(tester, 'Hello, Block Editor!');

        // 输入列表项
        await enterTextInFocusedBlock(tester, '- apple');

        // TODO(E2E): List 就绪后启用
        // 验证点 1：按 Enter 后产生两个列表项
        // 验证点 2：空列表项按 Enter → 退出列表变普通段落
      },
      skip: true, // ListBlock 未就绪，契约保留
    );

    testWidgets(
      '空列表项 Enter → 退出列表',
      (tester) async {
        // TODO(E2E): List 就绪后启用
        // 1. 输入 "- item1" → Enter → 两个列表项
        // 2. 空列表项按 Enter → 退出列表
        // 3. 验证块数变化
      },
      skip: true,
    );
  });
}