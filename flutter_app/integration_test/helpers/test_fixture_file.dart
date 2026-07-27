/// 增强版 TestFixture：支持真实文件路径（Chain 3 持久化链路）。
///
/// 在原始 `pumpEditorApp` 基础上新增 `pumpEditorFromFile`，
/// 用 `EditorPage(filePath:)` 打开磁盘上的真实 .md 文件。
library;

import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:formula_fix/presentation/editor/editor_page.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';
import 'package:formula_fix/providers/asset_provider.dart';

/// 原始的种子文档入口（无文件 I/O）。
Future<EditorPage> pumpEditorApp(
  WidgetTester tester, {
  int seedSelector = 0,
}) async {
  final app = EditorPage(seedSelector: seedSelector);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: app,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

/// 从真实 .md 文件打开编辑器（Chain 3 持久化链路入口）。
///
/// [theme] 可注入特定主题（默认浅色），用于验证主题块渲染链路。
///
/// [imagePicker] 可选：覆盖图片选择注入函数。传入则被当作 [MarkdownToolbar.pickImage]
/// 注入，用于 E2E 触发真实插入路径 `_handleInsertImage`（headless 环境下真实
/// [ImagePicker] 不可用、返回 null/抛异常导致静默跳过，无法验证插入）。典型用法：
/// 传入 `() async => 'assets/img_e2e.png'` 让图片项插入 `![](assets/img_e2e.png)`。
/// 不传则使用真实 provider（仅验证 UI，不插入）。
Future<EditorPage> pumpEditorFromFile(
  WidgetTester tester, {
  required String filePath,
  ThemeData? theme,
  Future<String?> Function()? imagePicker,
}) async {
  final app = EditorPage(filePath: filePath);
  final overrides = <Override>[
    if (imagePicker != null)
      imagePickAndImportProvider.overrideWithValue(imagePicker),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
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
Future<String> createTestDoc({
  required String title,
  required String content,
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final docsPath = '${dir.path}${io.Platform.pathSeparator}documents';
  await io.Directory(docsPath).create(recursive: true);
  final name = 'e2e_${DateTime.now().millisecondsSinceEpoch}.md';
  final path = '$docsPath${io.Platform.pathSeparator}$name';
  final fullContent = '---\ntitle: $title\n---\n\n$content';
  await io.File(path).writeAsString(fullContent);
  return path;
}
