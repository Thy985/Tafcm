/// T2-1 核心 golden：行内公式（inline mode）渲染（light 主题）。
///
/// 防什么：行内公式渲染回归——[FormulaRenderer] 行内优先 flutter_math_fork。
/// 行内公式的字号、基线对齐、与相邻文本的垂直对齐、颜色（经 [EditorTokens]）
/// 一旦变化即 diff。行内公式是正文高频元素，回归面大。
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';
import 'golden_helpers.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenFonts();
  });

  testWidgets('inline formula light：行内公式渲染', (tester) async {
    final editor = InMemoryDocumentEditor(title: 'golden-inline-formula');
    editor.insertBlock(
      0,
      ParagraphElement(children: [
        TextElement('Energy is '),
        FormulaElement(latex: r'E = mc^2', displayMode: false),
        TextElement(' in mass-energy equivalence, where '),
        FormulaElement(latex: r'c \approx 3 \times 10^8', displayMode: false),
        TextElement(' m/s.'),
      ]),
    );
    final coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );

    await pumpEditorGolden(tester, coordinator);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/inline_formula_light.png'),
    );
  });
}
