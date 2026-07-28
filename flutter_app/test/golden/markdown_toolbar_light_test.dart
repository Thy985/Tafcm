/// T2-1 核心 golden：Markdown 工具栏布局（light 主题）。
///
/// 防什么：Markdown 工具栏布局回归——[MarkdownToolbar] 的按钮排列、图标、分隔
/// 符、与编辑器协调器的联动入口一旦变化即 diff。工具栏是高频交互入口，视觉
/// 稳定性直接影响可用性。注意：golden 仅锁布局，不锁交互行为。
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/presentation/chrome/markdown_toolbar.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/editor_scope.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';
import 'golden_helpers.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenFonts();
  });

  testWidgets('markdown toolbar light：工具栏布局', (tester) async {
    final editor = InMemoryDocumentEditor(title: 'golden-toolbar');
    final coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );

    await pumpGoldenApp(
      tester,
      EditorScope(
        coordinator: coordinator,
        child: MarkdownToolbar(coordinator: coordinator),
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/markdown_toolbar_light.png'),
    );
  });
}
