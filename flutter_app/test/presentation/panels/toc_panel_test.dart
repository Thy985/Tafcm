/// 3.4.1 TOC 大纲面板单元测试。
///
/// 覆盖 Phase 3.4 Task Contract v1.2 §3.1 + §4.1：
/// - 标题遍历（coordinator.allIds → HeadingElement）
/// - 标题文本**复用 inline parser**（# **Hello** world → 显示 Hello world，不残留 **）
/// - 点击条目 → setFocus + onJump 回调
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/panels/toc_panel.dart';

/// 用 markdown 构造 [EditorCoordinator]（仅内存，不触达磁盘）。
EditorCoordinator _buildCoordinator(String markdown) {
  final editor = InMemoryDocumentEditor();
  final elements = MarkdownParser.parse(markdown);
  for (final e in elements) {
    editor.insertBlock(editor.blockCount, e);
  }
  return EditorCoordinator(editor: editor, history: EditorHistory());
}

BlockId _headingId(EditorCoordinator c, String contains) {
  return c.allIds.firstWhere(
    (id) {
      final e = c.getBlock(id);
      return e is HeadingElement && e.text.contains(contains);
    },
  );
}

/// 收集 TOC 面板内所有 RichText 的纯文本（inline 渲染产物）。
List<String> _tocPlainTexts(WidgetTester tester) {
  return tester
      .widgetList<RichText>(find.byType(RichText))
      .map((rt) => rt.text.toPlainText())
      .toList();
}

void main() {
  group('3.4.1 TOC 面板', () {
    testWidgets('列出所有标题，inline 解析去除 ** 标记', (tester) async {
      final c = _buildCoordinator('''
# **Hello** world
## Introduction
### Sub section
''');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TocPanel(coordinator: c)),
        ),
      );

      final plain = _tocPlainTexts(tester);
      // inline parser 生效：粗体标题显示为 Hello world（无 ** 残留）
      expect(plain, contains('Hello world'));
      expect(plain, isNot(contains('**Hello** world')));
      // 各级标题均列出
      expect(plain, contains('Introduction'));
      expect(plain, contains('Sub section'));
    });

    testWidgets('点击条目 → setFocus + onJump 回调', (tester) async {
      final c = _buildCoordinator('''
# **Hello** world
## Introduction
''');
      final captured = <BlockId>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TocPanel(coordinator: c, onJump: captured.add)),
        ),
      );

      final targetId = _headingId(c, 'Hello');
      expect(c.focusedId, isNot(targetId)); // 初始未聚焦该标题

      await tester.tap(find.byKey(Key('toc_$targetId')));
      await tester.pumpAndSettle();

      // 面板调用 setFocus
      expect(c.focusedId, targetId);
      // 跳转回调被触发且传回正确 id
      expect(captured, contains(targetId));
    });

    testWidgets('空文档显示占位', (tester) async {
      final c = _buildCoordinator('');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TocPanel(coordinator: c)),
        ),
      );
      expect(find.text('（暂无标题）'), findsOneWidget);
    });
  });
}
