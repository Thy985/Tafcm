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
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';

/// 在 [setUpAll] 中调用，显式加载打包字体。
Future<void> setUpGoldenFonts() async {
  await loadAppFonts();
}

/// 在固定环境下 pump 一个 widget 供 golden 比对。
///
/// 固定 locale / textScaleFactor / viewport，并用 [AppTheme.lightTheme]
/// 注入 EditorTokens（MEMORY §3：公式/chrome 等 widget 依赖 EditorTokens）。
Future<void> pumpGoldenApp(WidgetTester tester, Widget child) async {
  tester.platformDispatcher
    ..localeTestValue = const Locale('en', 'US')
    ..textScaleFactorTestValue = 1.0;

  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(800, 1200)),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
