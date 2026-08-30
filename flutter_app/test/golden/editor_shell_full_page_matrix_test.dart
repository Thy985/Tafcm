/// P1-4 EditorShell 整页 golden 矩阵变体（核心页矩阵策略）。
///
/// 在 [editor_shell_full_page_light_test] 的 800×1200 light 基线之外，补齐：
/// - dark @ 800（暗色整页，P0-1 暗色阴影令牌接入后必测）
/// - light @ 834 / dark @ 834（平板宽度破版守护）
/// - light @ 800 @ textScale 1.3（系统字体放大破版守护）
///
/// 注意：本文件与 light 基线共用同一编辑器内容构造，确保跨尺寸/主题差异仅来自
/// 视口与主题，而非内容。PNG 命名见各用例。
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/editor_scope.dart';
import 'package:tafcm/presentation/editor/editor_shell.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'golden_helpers.dart';

/// 与 light 基线一致的编辑器内容（标题 / 行内公式 / 代码块 / 块级公式）。
EditorCoordinator _buildCoordinator() {
  final editor = InMemoryDocumentEditor(title: 'Golden Editor');
  editor
    ..insertBlock(0, HeadingElement(level: 1, children: [TextElement('Golden Editor Page')]))
    ..insertBlock(
      1,
      ParagraphElement(children: [
        TextElement('A paragraph with '),
        FormulaElement(latex: r'E = mc^2', displayMode: false),
        TextElement(' inline formula.'),
      ]),
    )
    ..insertBlock(
      2,
      CodeElement(
        code: 'print("hello world");',
        language: 'dart',
      ),
    )
    ..insertBlock(
      3,
      ParagraphElement(children: [
        FormulaElement(latex: r'a^2 + b^2 = c^2', displayMode: true),
      ]),
    );
  return EditorCoordinator(
    editor: editor,
    history: EditorHistory(maxHistorySize: 200),
  );
}

Widget _shell(EditorCoordinator coordinator) => EditorScope(
      coordinator: coordinator,
      child: AnimatedBuilder(
        animation: coordinator,
        builder: (context, _) => EditorShell(coordinator: coordinator),
      ),
    );

void main() {
  setUpAll(() async {
    await setUpGoldenFonts();
  });

  testWidgets('editor shell full page dark @800', (tester) async {
    await pumpFullScreenGolden(
      tester,
      _shell(_buildCoordinator()),
      theme: AppTheme.darkTheme,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/editor_shell_full_page_dark.png'),
    );
  });

  testWidgets('editor shell full page light @834（平板宽度）', (tester) async {
    await pumpFullScreenGolden(
      tester,
      _shell(_buildCoordinator()),
      theme: AppTheme.lightTheme,
      size: const Size(834, 1200),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/editor_shell_full_page_light_834.png'),
    );
  });

  testWidgets('editor shell full page dark @834（平板宽度）', (tester) async {
    await pumpFullScreenGolden(
      tester,
      _shell(_buildCoordinator()),
      theme: AppTheme.darkTheme,
      size: const Size(834, 1200),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/editor_shell_full_page_dark_834.png'),
    );
  });

  testWidgets('editor shell full page light @800 @textScale 1.3', (tester) async {
    await pumpFullScreenGolden(
      tester,
      _shell(_buildCoordinator()),
      theme: AppTheme.lightTheme,
      textScaleFactor: 1.3,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/editor_shell_full_page_light_textscale_1_3.png'),
    );
  });
}
