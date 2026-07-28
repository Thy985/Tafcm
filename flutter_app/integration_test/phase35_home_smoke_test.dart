import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/main.dart' as app;
import 'package:integration_test/integration_test.dart';

/// Tier 4 真机首页冒烟测试（Phase 3.5 首页落地验证）。
///
/// 验证：启动经 BootstrapScreen 后进入 `/home`，首页含品牌字标、最近/更早区块、
/// 打开任意 .md 入口、底部 4 tab 导航。运行：`flutter test
/// integration_test/phase35_home_smoke_test.dart -d <device>`。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Phase 3.5 Home：首页渲染 + 三大区块 + 4 tab 导航', (tester) async {
    app.main();
    // 等待启动（StorageMigration + BootstrapScreen 路由决策 + 首帧）。
    await tester.pumpAndSettle(const Duration(seconds: 2));
    for (var i = 0; i < 4; i++) {
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    // 品牌字标
    expect(find.text('FormulaFix'), findsOneWidget,
        reason: '首页应包含 serif 品牌字标 FormulaFix');
    // 最近 / 更早 区块标签
    expect(find.text('最近'), findsWidgets, reason: '应包含「最近」区块');
    expect(find.text('更早'), findsWidgets, reason: '应包含「更早」区块');
    // 打开任意 .md 入口
    expect(find.text('打开任意 .md 文件'), findsOneWidget,
        reason: '应包含「打开任意 .md 文件」便携入口');
    // 底部 4 tab
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}
