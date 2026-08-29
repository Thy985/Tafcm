/// T2-1 核心 golden：EditorShell 整页布局（light 主题，800×1200）。
///
/// 防什么：编辑器整页布局回归——[EditorShell] 的 AppBar + 工具栏 + 编辑视口 +
/// 侧栏插槽的整体结构。这是一张「总览」基线，守护整页结构不被意外改动
/// （如 AppBar 元素增减、视口 padding 变化、主题注入错乱）。内容覆盖标题 /
/// 行内公式 / 代码块 / 块级公式，提供有代表性的整页渲染。
///
/// 尺寸 / 主题矩阵变体见 [editor_shell_full_page_matrix_test.dart]。
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

void main() {
  setUpAll(() async {
    await setUpGoldenFonts();
  });

  testWidgets('editor shell full page light：编辑器整页布局', (tester) async {
    final editor = InMemoryDocumentEditor(title: 'Golden Editor');
    editor
      ..insertBlock(0, HeadingElement(level: 1, text: 'Golden Editor Page'))
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
    final coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );

    await pumpFullScreenGolden(
      tester,
      EditorScope(
        coordinator: coordinator,
        child: AnimatedBuilder(
          animation: coordinator,
          builder: (context, _) => EditorShell(coordinator: coordinator),
        ),
      ),
      theme: AppTheme.lightTheme,
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/editor_shell_full_page_light.png'),
    );
  });
}
