/// Phase 3.4 E2E — 文件树真实打开链路（P0 核心链路）。
///
/// 验证 3.4.2 文件树侧栏的真实数据来源：
///   在磁盘创建 .md → 点击 AppBar 文件树按钮 → FileTreePanel 经
///   DocumentRepository 列出文档（标题取自正文首个 # H1）→ 列表含创建的文档
///
/// 边界说明：点击列表项会触发 _openDoc → context.go(...) 导航，
/// 本 harness 使用裸 MaterialApp（未注册 go_router），故仅验证
/// 「面板渲染 + 真实列出磁盘文档」这一半链路；完整「点击→切文档」导航
/// 依赖路由注册，留待后续补全（见 AGENTS.md E2E 边界清单）。
library;

import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/presentation/panels/file_tree_panel.dart';
import 'helpers/test_fixture_file.dart';

void main() {
  group('3.4.2 文件树真实打开链路', () {
    testWidgets('创建.md文件 → 文件树经仓储列出文档', (tester) async {
      // ---- 准备：在磁盘创建 2 个测试 .md 文件（标题取自 # H1）----
      final path1 = await createTestDoc(
        title: 'Alpha Doc',
        content: '# Alpha Doc\n\nContent A.',
      );
      final path2 = await createTestDoc(
        title: 'Beta Doc',
        content: '# Beta Doc\n\nContent B.',
      );
      addTearDown(() async {
        try { await io.File(path1).delete(); } catch (_) {}
        try { await io.File(path2).delete(); } catch (_) {}
      });

      // ---- 打开编辑器（带 filePath，文件树可用）----
      await pumpEditorFromFile(tester, filePath: path1);
      await tester.pumpAndSettle();

      // ---- 点击 AppBar 文件树按钮（Icons.folder_open / tooltip '文件树'）----
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      // ---- FileTreePanel 经 DocumentRepository 列出文档 ----
      final panel = find.byType(FileTreePanel);
      expect(panel, findsOneWidget);
      // 面板标题
      expect(find.descendant(of: panel, matching: find.text('文件')),
          findsOneWidget);
      // 我们创建的 2 个文档标题（取自正文 # H1）应出现在面板列表中。
      // 用 descendant 限定到面板内，避免与 AppBar 标题 / H1 块同名文本冲突。
      expect(
          find.descendant(of: panel, matching: find.text('Alpha Doc')),
          findsOneWidget);
      expect(
          find.descendant(of: panel, matching: find.text('Beta Doc')),
          findsOneWidget);
    });
  });
}
