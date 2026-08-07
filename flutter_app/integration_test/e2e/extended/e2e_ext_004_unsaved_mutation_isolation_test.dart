/// E2E-EXT-004：Unsaved Mutation Isolation（Phase 3.6.2）。
///
/// 验证未保存的修改不会污染持久化状态。
///
/// 场景：
/// 1. 打开文档 → 输入新内容 → 退出不保存 → 重开 → 原始内容保持
/// 2. 打开文档 → 修改 → 退出不保存 → 原始内容完整
///
/// 对应 E2E_TEST_PLAN §3.3.4 EXT-004。
library;

import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import '../helpers/e2e_app.dart';
import '../helpers/e2e_editor.dart';
import '../helpers/e2e_assertions.dart';

void main() {
  group('E2E-EXT-004: Unsaved Mutation Isolation', () {
    testWidgets('输入新内容后不保存退出 → 原始内容保持', (tester) async {
      const content = '原始内容，不会被修改污染。';
      final path = await createE2ETestDoc(title: 'isolation', content: content);

      // 打开文档
      await pumpE2EAppFromFile(tester, filePath: path);
      expectTextVisible(tester, '原始内容，不会被修改污染。');

      // 确认磁盘内容 = 原始内容
      final before = await io.File(path).readAsString();
      expect(before, contains('原始内容'),
          reason: '磁盘内容应为原始内容');
      expect(before, isNot(contains('未保存修改')),
          reason: '磁盘不应包含未保存的修改');

      // 编辑 — 输入新内容但不等待 autosave 触发
      await tapBlockByText(tester, '原始内容，不会被修改污染。');
      await enterTextInFocusedBlock(tester, '未保存修改');

      // 立即验证屏幕显示新内容
      expectTextVisible(tester, '未保存修改');

      // 验证磁盘文件尚未被修改（autosave debounce 1.5s，未等待）
      final afterEdit = await io.File(path).readAsString();
      expect(afterEdit, contains('原始内容'),
          reason: '未保存时磁盘应保持原始内容');
      expect(afterEdit, isNot(contains('未保存修改')),
          reason: '未保存修改不应写入磁盘');

      // 模拟关 App（不保存）
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // 重开同一文件
      await pumpE2EAppFromFile(tester, filePath: path);

      // 验证原始内容保持
      expectTextVisible(tester, '原始内容，不会被修改污染。');

      // 验证未保存内容不出现
      expectTextNotVisible(tester, '未保存修改');
    });

    testWidgets('修改后不保存 → 原始内容完整', (tester) async {
      const content = '这是原始段落内容。\n\n第二段内容。';
      final path = await createE2ETestDoc(title: 'modify', content: content);

      await pumpE2EAppFromFile(tester, filePath: path);
      expectTextVisible(tester, '这是原始段落内容。');

      // 修改内容
      await tapBlockByText(tester, '这是原始段落内容。');
      await enterTextInFocusedBlock(tester, '修改后的内容');

      // 不等待保存，直接关 App
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // 重开前验证文件内容
      final diskContent = await io.File(path).readAsString();
      expect(diskContent, contains('这是原始段落内容。'),
          reason: '磁盘文件应保持原始内容');
      expect(diskContent, isNot(contains('修改后的内容')),
          reason: '磁盘文件不应包含修改后的内容');

      // 重开
      await pumpE2EAppFromFile(tester, filePath: path);

      // 额外 pump 确保异步加载完成
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // 原始内容保持
      expectTextVisible(tester, '这是原始段落内容。');
      expectTextNotVisible(tester, '修改后的内容');
    });
  });
}