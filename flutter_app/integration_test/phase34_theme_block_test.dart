/// 3.4.3 主题块渲染（用户旅程级，区别于旧 Feature Presence 仅断言调试文本）。
///
/// 链路：设置主题模式 → 打开含代码块的 .md → 代码块容器背景色取自该主题
/// 注入的 [EditorTokens]（[CodeBlock.buildRenderContent] 用
/// `EditorTokens.of(context).codeBackground`）。验证「主题切换真实反映到块渲染」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/presentation/blocks/code/code_block.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';
import 'package:formula_fix/presentation/themes/editor_tokens.dart';

import 'helpers/test_fixture_file.dart';

void main() {
  group('3.4.3 主题块渲染', () {
    testWidgets('切换主题后代码块应用对应 EditorTokens（dark vs light）', (tester) async {
      // 含 fenced code block 的文档
      final path = await createTestDoc(
        title: '主题块',
        content: '# 标题\n\n这是一段普通段落。\n\n```dart\nvoid main() {}\n```\n',
      );

      // ---- 夜间主题：代码块背景应等于 EditorTokens.dark.codeBackground ----
      await pumpEditorFromFile(
        tester,
        filePath: path,
        theme: AppTheme.themeFor(AppThemeMode.dark),
      );
      final codeBlockDark = find.byType(CodeBlock);
      expect(codeBlockDark, findsOneWidget);
      final containerDark =
          find.descendant(of: codeBlockDark, matching: find.byType(Container)).first;
      final decoDark =
          tester.widget<Container>(containerDark).decoration as BoxDecoration;
      expect(decoDark.color, equals(EditorTokens.dark.codeBackground));

      // ---- 浅色主题：同一代码块背景应变为 EditorTokens.light.codeBackground ----
      await pumpEditorFromFile(
        tester,
        filePath: path,
        theme: AppTheme.themeFor(AppThemeMode.light),
      );
      final codeBlockLight = find.byType(CodeBlock);
      expect(codeBlockLight, findsOneWidget);
      final containerLight =
          find.descendant(of: codeBlockLight, matching: find.byType(Container)).first;
      final decoLight =
          tester.widget<Container>(containerLight).decoration as BoxDecoration;
      expect(decoLight.color, equals(EditorTokens.light.codeBackground));

      // 两套主题的背景色必须不同（证明主题确实驱动了块渲染，而非恒值）
      expect(EditorTokens.dark.codeBackground,
          isNot(equals(EditorTokens.light.codeBackground)));
    });
  });
}
