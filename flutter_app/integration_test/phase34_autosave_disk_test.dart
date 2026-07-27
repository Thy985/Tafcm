/// 3.4.4 自动保存真实落盘（用户旅程级，区别于旧 Feature Presence 仅断言不崩）。
///
/// 链路：打开 .md → 编辑段落块 → 脏标记触发 AutosaveService(防抖 1.5s, ADR-0013)
/// → [_saveDocument] 经 fileRepositoryProvider 写回磁盘原路径 → 读回文件字节断言。
/// 直接验证「编辑内容真正写入磁盘文件」，而非仅内存态。
library;

import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_fixture_file.dart';

void main() {
  group('3.4.4 自动保存真实落盘', () {
    testWidgets('编辑段落→自动保存(>1.5s)→磁盘文件包含新文本', (tester) async {
      final path = await createTestDoc(
        title: '自动保存',
        content: '# 标题\n\n这是一段用于编辑的测试段落。\n',
      );

      await pumpEditorFromFile(tester, filePath: path);

      // 聚焦并进入段落块编辑态（双击：渲染态 → 编辑态 TextField）
      final paragraph = find.text('这是一段用于编辑的测试段落。');
      expect(paragraph, findsWidgets);
      await tester.tap(paragraph);
      await tester.pumpAndSettle();
      await tester.tap(paragraph); // 进入编辑
      await tester.pumpAndSettle();

      // 全选并改写为新文本，触发脏标记
      await tester.enterText(
          find.byType(TextField), '已自动保存到磁盘的内容');
      // 触发 onSubmitted → commit（base_block_state：TextInputAction.done → 失焦 → commit）
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 等待自动保存防抖（1.5s）+ 余量。integration_test 跑在真机，Timer 为真实时钟。
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // ---- 真实落盘断言：直接读磁盘原文件 ----
      final disk = await io.File(path).readAsString();
      expect(disk, contains('已自动保存到磁盘的内容'));
      expect(disk, isNot(contains('这是一段用于编辑的测试段落。')));
    });
  });
}
