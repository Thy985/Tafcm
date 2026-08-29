/// T2-1 核心 golden：块级公式（display mode）渲染（sepia 护眼主题）。
///
/// 防什么：护眼（sepia）主题下块级公式渲染回归——公式颜色经
/// [EditorTokens.textPrimary] 随主题切换。sepia 主题（米黄纸感）下背景 / 文字 /
/// 公式三色关系一旦错配即 diff。与 light / dark 基线三极成对，守护主题色彩
/// 单一真相源。
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'golden_helpers.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenFonts();
  });

  testWidgets('formula block sepia：护眼主题块级公式渲染', (tester) async {
    final editor = InMemoryDocumentEditor(title: 'golden-formula-block-sepia');
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

    await pumpEditorGolden(tester, coordinator, theme: AppTheme.sepiaTheme);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/formula_block_sepia.png'),
    );
  });
}
