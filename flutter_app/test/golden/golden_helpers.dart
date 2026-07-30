/// Tier 2 (TEST_GAP_PLAN T2-0) golden 测试基础设施。
///
/// 目标：消除跨平台渲染差异（GOLDEN-CI-001 根因），让 golden 基线在
/// Windows 本地与 Linux CI 上像素一致。
///
/// 固定项：
/// - locale = en_US（避免平台 locale 影响排版/日期/数字格式）
/// - textScaleFactor = 1.0（固定缩放，杜绝系统字号设置干扰）
/// - 固定 viewport（MediaQuery 800×1200），golden 像素尺寸确定
/// - [loadAppFonts]：显式加载 pubspec 打包字体（NotoSerifSC / NotoSansSC），
///   禁止依赖系统 fallback 字体（跨平台字体差异的直接根源）
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:formula_fix/core/editing/block_types.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/editor_scope.dart';
import 'package:formula_fix/presentation/editor/editor_shell.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';

/// 在 [setUpAll] 中调用，显式加载打包字体。
Future<void> setUpGoldenFonts() async {
  await loadAppFonts();
}

/// 在固定环境下 pump 一个 widget 供 golden 比对。
///
/// 固定 locale / textScaleFactor / viewport，并用 [theme]（默认
/// [AppTheme.lightTheme]）注入 EditorTokens（MEMORY §3：公式/chrome 等 widget
/// 依赖 EditorTokens）。[theme] 可传 [AppTheme.darkTheme] / [AppTheme.sepiaTheme]
/// 以生成对应主题的 golden。
///
/// 外层包 [ProviderScope]：EditorShell 是 ConsumerStatefulWidget，必须位于
/// ProviderScope 之下；对纯 EditorViewport 测试无副作用。
///
/// [size] / [textScaleFactor] 为 P1-4 Golden 矩阵扩充入口：默认 800×1200 / 1.0
/// 保持向后兼容；传 [size] 可覆盖窄屏(375)/平板(834) 等尺寸，传 [textScaleFactor]
/// 可覆盖系统字体放大(1.3) 场景，用于拦截破版回归。
Future<void> pumpGoldenApp(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  Size size = const Size(800, 1200),
  double textScaleFactor = 1.0,
}) async {
  final effectiveTheme = theme ?? AppTheme.lightTheme;
  tester.platformDispatcher
    ..localeTestValue = const Locale('en', 'US')
    ..textScaleFactorTestValue = textScaleFactor;

  await tester.pumpWidget(
    ProviderScope(
      child: MediaQuery(
        data: MediaQueryData(size: size, textScaleFactor: textScaleFactor),
        child: MaterialApp(
          theme: effectiveTheme,
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 在固定环境下 pump 一个**整屏 widget**（自身已返回 Scaffold，如
/// [HomeScreen] / [EditorShell] / [FileManagerScreen]）供 golden 比对。
///
/// 与 [pumpGoldenApp] 的区别：不额外套一层 `Scaffold(body: child)`，而是直接
/// 以 [screen] 作为 `MaterialApp.home`，避免「整屏 Scaffold 内再嵌整屏 Scaffold」
/// 导致顶部多一处空 AppBar 留白（破坏 P0-4「内容顶到最顶」的视觉基线）。
///
/// [size] / [textScaleFactor] 同 [pumpGoldenApp]；[overrides] 用于注入测试用
/// Provider（如 [documentListProvider]）。外层 [ProviderScope] 提供 Riverpod 环境。
Future<void> pumpFullScreenGolden(
  WidgetTester tester,
  Widget screen, {
  ThemeData? theme,
  Size size = const Size(800, 1200),
  double textScaleFactor = 1.0,
  List<Override> overrides = const [],
}) async {
  final effectiveTheme = theme ?? AppTheme.lightTheme;
  tester.platformDispatcher
    ..localeTestValue = const Locale('en', 'US')
    ..textScaleFactorTestValue = textScaleFactor;

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MediaQuery(
        data: MediaQueryData(size: size, textScaleFactor: textScaleFactor),
        child: MaterialApp(theme: effectiveTheme, home: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 用固定环境渲染一个已填充的编辑器（经 [EditorViewport]，真实块渲染路径）。
///
/// 覆盖 [pumpGoldenApp] 的固定项，外加 [EditorScope] + [AnimatedBuilder] +
/// [EditorViewport]（配合 [coordinator]）。[theme] 控制亮/暗/护眼主题。
///
/// 等价 T2-0 试点 `paragraph_light_test` 的样板，抽公共用，避免 9 张 golden
/// 各自重复。每个块的视觉由 [coordinator] 内文档决定。
Future<void> pumpEditorGolden(
  WidgetTester tester,
  EditorCoordinator coordinator, {
  ThemeData? theme,
}) async {
  await pumpGoldenApp(
    tester,
    EditorScope(
      coordinator: coordinator,
      child: AnimatedBuilder(
        animation: coordinator,
        builder: (context, _) => EditorViewport(
          coordinator: coordinator,
          blockKeys: <BlockId, GlobalKey>{},
        ),
      ),
    ),
    theme: theme,
  );
}
