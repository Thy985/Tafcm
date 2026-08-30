/// T2-1 核心 golden：块级公式（display mode）降级渲染（light 主题）。
///
/// 防什么：块级公式降级渲染回归——Phase 3.5 统一渲染内核 [FormulaRenderer]
/// 在 SVG（MathJax WebView）不可用时降级为 serif italic 源码。token（字号 /
/// 字族 / 颜色经 [EditorTokens]）或 [FormulaRenderer] 路径改动会改变块级公式
/// 视觉，基线即 diff。这是公式系统最关键的一张视觉锁。
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'golden_helpers.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenFonts();
  });

  testWidgets('formula block light：块级公式降级渲染', (tester) async {
    final editor = InMemoryDocumentEditor(title: 'golden-formula-block');
    editor
      ..insertBlock(0, HeadingElement(level: 2, children: [TextElement('Mass-Energy Equivalence')]))
      ..insertBlock(
        1,
        ParagraphElement(children: [
          FormulaElement(latex: r'E = mc^2', displayMode: true),
        ]),
      )
      ..insertBlock(
        2,
        ParagraphElement(children: [
          TextElement('The equation above relates energy to mass.'),
        ]),
      );
    final coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );

    await pumpEditorGolden(tester, coordinator);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/formula_block_light.png'),
    );
  });
}
