/// T2-1 核心 golden：正文排版（dark 主题）。
///
/// 防什么：暗色主题下正文排版回归——背景 / 文字色（[EditorTokens]）/ serif 字族
/// 一旦错配即 diff。与 T2-0 试点 paragraph_light 成对，守护三段主题（light /
/// dark / sepia）中 dark 一极的确定性。
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

  testWidgets('paragraph dark：暗色正文排版', (tester) async {
    final editor = InMemoryDocumentEditor(title: 'golden-paragraph-dark');
    editor.insertBlock(
      0,
      ParagraphElement(children: [
        TextElement(
          'The quick brown fox jumps over the lazy dog. Flutter golden '
          'tests must be deterministic across platforms, so this baseline '
          'locks the paragraph typography (serif body, 15px, block spacing).',
        ),
      ]),
    );
    final coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );

    await pumpEditorGolden(tester, coordinator, theme: AppTheme.darkTheme);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/paragraph_dark.png'),
    );
  });
}
