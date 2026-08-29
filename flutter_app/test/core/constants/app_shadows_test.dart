/// P0-1 阴影令牌对齐守护（UI_FIX_PLAN PR-A）。
///
/// 防什么：`AppShadows` 与 `design-system/tokens.json` `shadow` 节脱钩——
/// 尤其是暗色档位被改回"明暗同值"导致暗色模式阴影再次不可见的回归。
/// 令牌值（alpha / offset / blur）以 tokens.json 为唯一权威，本测试逐档比对。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/constants/app_constants.dart';

void main() {
  group('AppShadows light —— tokens.json shadow.sm~xl', () {
    // "0 1px 2px rgba(26,29,35,0.04)" 等四档。
    const base = Color(0xFF1A1D23);

    final expected = <String, (List<BoxShadow>, double, double, double)>{
      'sm': (AppShadows.light.sm, 0.04, 1, 2),
      'md': (AppShadows.light.md, 0.06, 4, 12),
      'lg': (AppShadows.light.lg, 0.10, 12, 40),
      'xl': (AppShadows.light.xl, 0.14, 24, 60),
    };

    for (final entry in expected.entries) {
      test('light.${entry.key} 对齐令牌', () {
        final (shadows, alpha, y, blur) = entry.value;
        expect(shadows, hasLength(1));
        final s = shadows.single;
        expect(s.color.withValues(alpha: 1.0), base.withValues(alpha: 1.0));
        expect(s.color.a, closeTo(alpha, 0.005));
        expect(s.offset, Offset(0, y));
        expect(s.blurRadius, blur);
      });
    }
  });

  group('AppShadows dark —— tokens.json shadow.dark.sm~xl', () {
    // "0 1px 2px rgba(0,0,0,0.3)" 等四档，alpha 显著高于亮色。
    const base = Color(0xFF000000);

    final expected = <String, (List<BoxShadow>, double, double, double)>{
      'sm': (AppShadows.dark.sm, 0.3, 1, 2),
      'md': (AppShadows.dark.md, 0.4, 4, 12),
      'lg': (AppShadows.dark.lg, 0.5, 12, 40),
      'xl': (AppShadows.dark.xl, 0.6, 24, 60),
    };

    for (final entry in expected.entries) {
      test('dark.${entry.key} 对齐令牌', () {
        final (shadows, alpha, y, blur) = entry.value;
        expect(shadows, hasLength(1));
        final s = shadows.single;
        expect(s.color.withValues(alpha: 1.0), base.withValues(alpha: 1.0));
        expect(s.color.a, closeTo(alpha, 0.005));
        expect(s.offset, Offset(0, y));
        expect(s.blurRadius, blur);
      });
    }
  });

  test('暗色各档 alpha 必须高于亮色同档（暗色可见性回归守护）', () {
    expect(AppShadows.dark.sm.single.color.a,
        greaterThan(AppShadows.light.sm.single.color.a));
    expect(AppShadows.dark.md.single.color.a,
        greaterThan(AppShadows.light.md.single.color.a));
    expect(AppShadows.dark.lg.single.color.a,
        greaterThan(AppShadows.light.lg.single.color.a));
    expect(AppShadows.dark.xl.single.color.a,
        greaterThan(AppShadows.light.xl.single.color.a));
  });

  testWidgets('AppShadows.of(context) 按主题亮度取套', (tester) async {
    late AppShadowSet resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) {
            resolved = AppShadows.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(identical(resolved, AppShadows.dark), isTrue);
  });

  test('flipY 只反转垂直方向，其余参数不变', () {
    final flipped = AppShadows.flipY(AppShadows.light.md);
    final original = AppShadows.light.md.single;
    final f = flipped.single;
    expect(f.offset, Offset(original.offset.dx, -original.offset.dy));
    expect(f.color, original.color);
    expect(f.blurRadius, original.blurRadius);
    expect(f.spreadRadius, original.spreadRadius);
  });
}
