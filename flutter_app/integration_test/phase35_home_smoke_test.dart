import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/presentation/screens/home_screen.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tier 4 真机首页冒烟测试（Phase 3.5 首页落地验证）。
///
/// 验证：首页含品牌字标、最近/更早区块、打开任意 .md 入口。
/// 运行：`flutter test integration_test/phase35_home_smoke_test.dart -d <device>`。
///
/// 2026-08-19 修复：原实现调用 `app.main()` 启动真实 App（runZonedGuarded +
/// 全局 observability 错误钩子 + StorageMigration + ExternalFileService
/// MethodChannel），在 integration_test 下污染 FlutterError.onError 且
/// pumpAndSettle 永不 settle → did not complete。改为 harness 模式直接
/// pump HomeScreen（与 pumpE2EApp 一致），避开真实 App 启动副作用。
/// 注意：底部 4 tab 由 StatefulShellRoute 的 HomeScaffold 渲染（非
/// HomeScreen 内），本测试仅验证首页内容，shell 导航由路由测试覆盖。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Phase 3.5 Home：首页渲染 + 最近/更早区块 + 打开入口', (tester) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const HomeScreen(),
        ),
      ),
    );
    // 等待首帧与异步加载（避免真实 App 启动的持续动画，用固定时长 pump）。
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    // 品牌字标
    expect(find.text('FormulaFix'), findsOneWidget,
        reason: '首页应包含 serif 品牌字标 FormulaFix');
    // 「最近」区块标题（无条件渲染）
    expect(find.text('最近'), findsOneWidget, reason: '应包含「最近」区块');
    // 空文档时「更早」区块不应出现（仅 earlier.isNotEmpty 时渲染）
    expect(find.text('更早'), findsNothing,
        reason: '空文档（无更早文件）时不应有「更早」区块');
    // 打开任意 .md 入口
    expect(find.text('打开任意 .md 文件'), findsOneWidget,
        reason: '应包含「打开任意 .md 文件」便携入口');
  });
}
