/// E2E-EXT-005：IME Composition（Phase 3.6.2，Patrol）。
///
/// 验证中文拼音输入法组合态输入，不产生错误 Transaction。
///
/// 验证点：
/// 1. 拼音输入后正确提交中文
/// 2. Undo 撤销全部中文文本
/// 3. 组合态期间不产生中间 Transaction
///
/// 对应 E2E_TEST_PLAN §3.3.5 EXT-005。
library;

import 'package:patrol/patrol.dart';
import 'package:flutter/material.dart';

void main() {
  patrolTest(
    '中文拼音输入 → 正确提交文本',
    ($) async {
      await $.pumpWidget(
        const MaterialApp(home: Text('IME 测试占位')),
      );
      await $.pumpAndSettle();

      // TODO(E2E): 待 Patrol 真机环境就绪后启用
      // 1. 通过 Patrol 真机键盘输入拼音 "ni"
      // 2. 选择候选词 "你"
      // 3. 继续输入 "hao"
      // 4. 选择候选词 "好"
      // 5. 验证编辑器显示 "你好"
      // 6. 撤销 → 验证文本全部消失
    },
    skip: true, // 需要真机 Gboard 输入法
  );

  patrolTest(
    'IME 组合态期间不产生中间 Transaction',
    ($) async {
      await $.pumpWidget(
        const MaterialApp(home: Text('IME 组合态测试占位')),
      );
      await $.pumpAndSettle();

      // TODO(E2E): 待 Patrol 真机环境就绪后启用
      // 1. 输入拼音 "ni"
      // 2. 验证组合态期间没有产生 Commit
      // 3. 选择候选词 "你"
      // 4. 验证最终只产生一个 Commit
    },
    skip: true, // 需要真机 Gboard 输入法
  );
}