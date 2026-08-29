/// P1-1 响应式：EditorShell 整页布局窄屏基线（light 主题，375×812）。
///
/// 防什么：窄屏（手机）下编辑器整页布局回归——AppBar + 工具栏 + 编辑视口 +
/// 状态栏在 375 宽度下不得溢出 / 破版。与 800×1200 基线互补，锁定响应式下限。
/// 文件树默认关闭（与历史基线一致），避免 Drawer 形态进入此基线。
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

  testWidgets('editor shell full page narrow：编辑器窄屏(375)整页布局',
      (tester) async {
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
      size: const Size(375, 812),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/editor_shell_full_page_narrow.png'),
    );
  });
}
