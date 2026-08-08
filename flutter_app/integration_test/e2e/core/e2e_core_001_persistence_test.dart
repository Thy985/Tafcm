/// E2E-CORE-001：持久化 Round-trip（Phase 3.6.1）。
///
/// 验证文档编辑 → autosave → 关 App → 重开 → 内容一致。
///
/// 验证点：
/// 1. 编辑内容在 autosave 后已落盘
/// 2. 关 App 后磁盘文件内容保留
/// 3. 重开 App 后编辑内容正确渲染
///
/// 对应 E2E_TEST_PLAN §3.1 CORE-001。
library;

import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import '../helpers/e2e_app.dart';
import '../helpers/e2e_assertions.dart';
import '../helpers/e2e_editor.dart';

void main() {
  group('E2E-CORE-001: Persistence Roundtrip', () {
    testWidgets('编辑 → autosave → 关 App → 重开 → 内容一致', (tester) async {
      const content = '# 标题\n\n'
          '这是正文段落，用于持久化验证。\n\n'
          '```dart\nvoid main() {}\n```';
      final path = await createE2ETestDoc(title: 'persistence', content: content);

      // 打开文件
      await pumpE2EAppFromFile(tester, filePath: path);

      // 验证初始内容渲染
      expectTextVisible(tester, '这是正文段落，用于持久化验证。');
      expectTextInAnyWidget(tester, 'void main()');

      // 编辑正文段落
      await tapBlockByText(tester, '这是正文段落，用于持久化验证。');
      await enterTextInFocusedBlock(tester, '这是（已编辑）正文段落。');

      // 验证编辑后文本已显示在 TextField 中
      await tester.pumpAndSettle();
      expect(find.textContaining('已编辑'), findsWidgets,
          reason: '编辑文本应在 TextField 中可见');

      // 点击标题块使段落失焦 → 触发 _commitSource → 更新 committed source
      await tapBlockByText(tester, '标题');
      // 再点回段落使其重新聚焦（为下一轮编辑做准备）
      await tapBlockByText(tester, '这是（已编辑）正文段落。');

      // 等待 autosave 落盘（debounce 1.5s + 磁盘 I/O）
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // 验证文件已落盘
      final onDisk1 = await io.File(path).readAsString();
      expect(onDisk1, contains('已编辑'),
          reason: '编辑内容应已 autosave 落盘');

      // 模拟关 App
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // 重开同一文件
      await pumpE2EAppFromFile(tester, filePath: path);

      // 轮询等待异步加载完成
      var found = false;
      for (var i = 0; i < 12 && !found; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        found = find.textContaining('已编辑').evaluate().isNotEmpty;
      }
      expect(found, isTrue, reason: '重开后编辑内容应保留');

      // 验证其他内容也未丢失
      expectTextInAnyWidget(tester, 'void main()');
    });
  });
}