/// T2-1 核心 golden：代码块渲染（light 主题）。
///
/// 防什么：代码块渲染回归——[CodeBlock] 语法高亮（flutter_highlight）+ 等宽
/// 字体（现已固定为 [CascadiaMono]，T2-1 补齐打包）+ 圆角 / 背景 / 行距。
/// 等宽字体一旦回退到平台字体（旧症）或高亮配色改动，基线即 diff。
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

  testWidgets('code block light：代码块渲染', (tester) async {
    final editor = InMemoryDocumentEditor(title: 'golden-code-block');
    editor
      ..insertBlock(0, HeadingElement(level: 2, text: 'Sample Code'))
      ..insertBlock(
        1,
        CodeElement(
          code: 'void main() {\n'
              '  final msg = "hello";\n'
              '  print(msg);\n'
              '}',
          language: 'dart',
        ),
      );
    final coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );

    await pumpEditorGolden(tester, coordinator);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/code_block_light.png'),
    );
  });
}
