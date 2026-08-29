/// Phase 3.4 E2E — Chain 3 持久化强制（P0 核心链路）。
///
/// 验证 ADR-0003（存储单一来源）/ ADR-0013（自动保存 1.5s debounce）/ ADR-0016：
///   真实 .md 文件 → 编辑器打开 → 编辑段落 → 自动保存落盘
///   → 关闭 App → 重新打开同一文件 → 内容一致（编辑已持久化）
///
/// 这是从「Feature Presence」升级为「User Journey」的关键用例：
/// 不再只验证组件存在，而是真实驱动 输入→状态→保存→关闭→重开→恢复 全链路。
library;

import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/presentation/editor/editor_page.dart';
import 'helpers/test_fixture_file.dart';

void main() {
  group('Chain 3 持久化 — 编辑→自动保存→重启恢复', () {
    testWidgets('编辑 .md 段落 → 自动保存落盘 → 重启恢复一致', (tester) async {
      // ---- 准备：写测试 .md 到磁盘（与 FileRepository 同一 documents 目录）----
      // 注意：公式 $...$ 在渲染层产出 KaTeX 图片而非 Text，故此处只用
      // 标题 + 段落两类会被渲染为 Text 的块，断言更稳健。
      final path = await createTestDoc(
        title: '持久化测试',
        content: '# Hello\n\n这是一段用于编辑的测试段落。\n',
      );
      addTearDown(() async {
        try { await io.File(path).delete(); } catch (_) {}
      });

      // ---- 打开编辑器（带 filePath → currentPath 非空 → AutosaveService 激活）----
      final app = await pumpEditorFromFile(tester, filePath: path);
      expect(app, isA<EditorPage>());

      // ---- 渲染校验：标题已通过 文件→解析→渲染 链路加载 ----
      // 'Hello' 同时出现于 AppBar 标题与 H1 块，故用 findsWidgets
      expect(find.text('Hello'), findsWidgets);

      // ---- 进入编辑：点击段落块（body 唯一文本，避开 AppBar 标题）----
      final para = find.text('这是一段用于编辑的测试段落。');
      expect(para, findsOneWidget);
      await tester.tap(para);
      await tester.pumpAndSettle();

      // ---- 段落进入编辑态：出现 TextField ----
      final tf = find.byType(TextField);
      expect(tf, findsOneWidget);
      await tester.enterText(tf, '这是一段（已编辑）的测试段落。');
      // 触发 onSubmitted → commit（base_block_state：TextInputAction.done → 失焦 → commit）
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // ---- 等待 AutosaveService debounce（1.5s）+ 落盘 ----
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // ---- 磁盘写入校验：编辑内容已真正落盘 ----
      final onDisk = await io.File(path).readAsString();
      expect(onDisk, contains('已编辑'),
          reason: '自动保存应将编辑后的段落写回 .md 文件');

      // ---- 模拟关闭 App（pump 新 widget 触发 dispose 链）----
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // ---- 重新打开同一文件 ----
      final app2 = await pumpEditorFromFile(tester, filePath: path);
      expect(app2, isA<EditorPage>());

      // ---- 恢复校验：编辑后的内容仍被正确加载并渲染 ----
      expect(find.text('这是一段（已编辑）的测试段落。'), findsWidgets,
          reason: '重启后应从 .md 恢复编辑过的内容');
      final onDisk2 = await io.File(path).readAsString();
      expect(onDisk2, contains('已编辑'));
    });
  });
}
