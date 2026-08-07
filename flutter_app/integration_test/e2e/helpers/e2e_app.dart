/// E2E 测试套件统一启动入口（Phase 3.6.1）。
///
/// 基于 [test_fixture.dart] 的 pumpEditorApp 模式，提供：
/// - [pumpE2EApp]：标准 E2E 启动（种子文档模式）
/// - [pumpE2EAppFromFile]：真实文件模式（持久化链路）
///
/// **Hard Rule**（继承自 TestFixture v2.1 §3.3.1）：
/// - 所有 E2E 用例必须通过本文件启动 app
/// - 禁止直接 `pumpWidget(ProviderScope(child: FormulaFixApp()))`（会走真实存储）
/// - 禁止依赖 `path_provider` / `SharedPreferences` 真实存储
library;

import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:formula_fix/presentation/editor/editor_page.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';

/// 标准 E2E 启动：打开种子文档（默认 demo1，含 3 块：heading + paragraph + code）。
///
/// [seedSelector] 选择种子文档（0 = demo1, 1 = demo2, 2 = demo3）。
/// [themeMode] 指定注入的主题（默认 light）。
///
/// 返回构造的 [EditorPage] widget 引用（便于高级断言）。
Future<EditorPage> pumpE2EApp(
  WidgetTester tester, {
  int seedSelector = 0,
  AppThemeMode themeMode = AppThemeMode.light,
}) async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final app = EditorPage(seedSelector: seedSelector);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.themeFor(themeMode),
        home: app,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

/// 从真实 .md 文件打开编辑器（持久化链路验证）。
///
/// [filePath] 必须指向已存在的 .md 文件。
/// [theme] 可注入特定主题（默认浅色）。
Future<EditorPage> pumpE2EAppFromFile(
  WidgetTester tester, {
  required String filePath,
  ThemeData? theme,
}) async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final app = EditorPage(filePath: filePath);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        home: app,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

/// 在应用文档目录创建测试 .md 文件，返回绝对路径。
///
/// 文件内容自动添加 YAML front matter。
Future<String> createE2ETestDoc({
  required String title,
  required String content,
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final docsPath = '${dir.path}${io.Platform.pathSeparator}documents';
  await io.Directory(docsPath).create(recursive: true);
  final name = 'e2e_test_${DateTime.now().millisecondsSinceEpoch}.md';
  final path = '$docsPath${io.Platform.pathSeparator}$name';
  final fullContent = '---\ntitle: $title\n---\n\n$content';
  await io.File(path).writeAsString(fullContent);
  return path;
}