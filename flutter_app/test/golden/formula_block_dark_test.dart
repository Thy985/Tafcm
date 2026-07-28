/// T2-1 核心 golden：块级公式（display mode）渲染（dark 主题）。
///
/// 防什么：暗色主题下块级公式渲染回归——公式颜色经 [EditorTokens.textPrimary]
/// 随主题切换。暗色下背景 / 文字 / 公式三色关系一旦错配（如公式仍用亮色色值）
/// 即 diff。与 light 基线成对，守护主题色彩单一真相源。
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';
import 'golden_helpers.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenFonts();
  });

  testWidgets('formula block dark：暗色块级公式渲染', (tester) async {
    final editor = InMemoryDocumentEditor(title: 'golden-formula-block-dark');
    editor
      ..insertBlock(0, HeadingElement(level: 2, text: 'Mass-Energy Equivalence'))
      ..insertBlock(
        1,
        ParagraphElement(children: [
          FormulaElement(latex: r'E = mc^2', displayMode: true),
        ]),
      );
    final coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );

    await pumpEditorGolden(tester, coordinator, theme: AppTheme.darkTheme);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/formula_block_dark.png'),
    );
  });
}
