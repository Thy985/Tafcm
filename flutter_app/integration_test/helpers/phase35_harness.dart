/// Tier 3 E2E 专用 harness：挂载 [MermaidRendererHost]（离屏）后打开编辑器，
/// 使真实 MathJax WebView SVG 可用。
///
/// 不挂载时 [FormulaSvgService.renderToSvg] 会抛
/// "MermaidRendererHost is not mounted" → 公式降级 flutter_math_fork。
/// 对应 `main.dart` 的 `TafcmApp` 挂载方式（仅 T3-2 公式测试需要真实 SVG）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/presentation/editor/editor_page.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'package:tafcm/presentation/widgets/mermaid_host.dart';

/// 打开真实 .md 文件并挂载 [MermaidRendererHost]，使公式走真实 WebView SVG。
Future<EditorPage> pumpEditorFromFileWithMermaid(
  WidgetTester tester, {
  required String filePath,
  AppThemeMode themeMode = AppThemeMode.light,
}) async {
  final app = EditorPage(filePath: filePath);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.themeFor(themeMode),
        home: Stack(
          children: [
            app,
            const Positioned(
              left: -10000,
              top: -10000,
              child: MermaidRendererHost(),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}
