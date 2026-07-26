/// TestFixture：integration_test 唯一入口。
///
/// 落地 Phase 3.3 PR #1.5 Task Contract v2.1 §3.3.1（审批 #4）。
///
/// **Hard Rule**（v2.1 §3.3.1）：
/// - 所有 E2E 用例必须通过 [TestFixture] 启动 app
/// - 禁止直接 `pumpWidget(ProviderScope(child: FormulaFixApp()))`（会走真实存储）
/// - 禁止依赖 `path_provider` / `SharedPreferences` 真实存储
///
/// **设计**：
/// Phase 3.0 production 路径中 [EditorPage] 直接在 `initState` 构造
/// [EditorCoordinator]（注入 [InMemoryDocumentEditor] + [EditorHistory]）,
/// 不依赖 Repository。因此 E2E 直接 `pumpWidget(EditorPage())` 即可跳过路由
/// `/files`（[FileManagerScreen] 依赖 `path_provider`）。
///
/// **Phase 3.4 Slice 3 / ADR-0015 变更**：
/// - `blocks/` 渲染改经 [EditorTokens.of]（ThemeExtension 运行时取色），
///   harness 必须提供**注入了 EditorTokens 的 ThemeData**（见 [AppTheme.themeFor]），
///   否则 `of(context)` 空断言崩溃（正是 q-0「风险1：注入遗漏」在测试面的体现）。
/// - [EditorPage.build] 读取 `themeModeProvider`，需要 [ProviderScope]；
///   用 `SharedPreferences.setMockInitialValues` 注入**内存 mock**，
///   不触达真实存储（满足 v2.1 §3.3.1 Hard Rule）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:formula_fix/presentation/editor/editor_page.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';

/// integration_test 唯一入口：构造 [EditorPage] 并 pump 到 [tester]。
///
/// [seedSelector] 选择种子文档（0 = demo1, 1 = demo2, 2 = demo3）。
/// [themeMode] 指定注入的主题（默认 light）；用于验证 blocks 在不同主题下渲染。
///
/// 返回构造的 [EditorPage] widget 引用（便于高级断言）。
Future<EditorPage> pumpEditorApp(
  WidgetTester tester, {
  int seedSelector = 0,
  AppThemeMode themeMode = AppThemeMode.light,
}) async {
  // 内存 mock，避免触达真实 SharedPreferences（Hard Rule §3.3.1）。
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final app = EditorPage(seedSelector: seedSelector);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        // ADR-0015：注入 EditorTokens，blocks 的 of(context) 才能取到主题色。
        theme: AppTheme.themeFor(themeMode),
        home: app,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}
