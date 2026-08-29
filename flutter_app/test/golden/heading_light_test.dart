/// T2-1 核心 golden：标题排版（heading 1/2/3 梯度，light 主题）。
///
/// 防什么：标题排版回归——[HeadingBlock] 字号梯度（h1 26 / h2 19-20 / h3 ...）、
/// 字族 serif（[AppTypography.serif] = NotoSerifSC）、字间距 / 段距一旦变化
/// 即 diff。[HeadingElement] 的 level→字号映射是 Design System 单一真相源的
/// 直接体现，回归代价高。
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

  testWidgets('heading light：标题排版梯度', (tester) async {
    final editor = InMemoryDocumentEditor(title: 'golden-heading');
    editor
      ..insertBlock(0, HeadingElement(level: 1, text: 'Chapter One'))
      ..insertBlock(1, HeadingElement(level: 2, text: 'Section A'))
      ..insertBlock(2, HeadingElement(level: 3, text: 'Subsection'))
      ..insertBlock(
        3,
        ParagraphElement(children: [
          TextElement('Body text under the headings.'),
        ]),
      );
    final coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );

    await pumpEditorGolden(tester, coordinator);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/heading_light.png'),
    );
  });
}
