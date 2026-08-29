/// Phase 3.4 Slice 3 / ADR-0015：EditorTokens ThemeExtension 运行时验证。
///
/// 覆盖 q-0 三大 P0 风险中的 **风险1（ThemeExtension 注入遗漏）**：
/// - 三套主题（light / dark / sepia）必须都注入非空 [EditorTokens]，
///   否则 [EditorTokens.of] 在该主题下 `!` 空断言崩溃。
/// - [EditorTokens.of] 必须返回当前 [ThemeData] 注入的实例；切换主题后取到新色。
/// - [EditorTokens.copyWith] / [EditorTokens.lerp] 契约（ThemeExtension 硬约束）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'package:tafcm/presentation/themes/editor_tokens.dart';

void main() {
  group('风险1 守门：三主题 EditorTokens 注入完整性', () {
    test('lightTheme 注入非空且为 EditorTokens.light', () {
      final ext = AppTheme.lightTheme.extension<EditorTokens>();
      expect(ext, isNotNull);
      expect(ext, same(EditorTokens.light));
    });

    test('darkTheme 注入非空且为 EditorTokens.dark', () {
      final ext = AppTheme.darkTheme.extension<EditorTokens>();
      expect(ext, isNotNull);
      expect(ext, same(EditorTokens.dark));
    });

    test('sepiaTheme 注入非空且为 EditorTokens.sepia', () {
      final ext = AppTheme.sepiaTheme.extension<EditorTokens>();
      expect(ext, isNotNull);
      expect(ext, same(EditorTokens.sepia));
    });

    test('themeFor 覆盖全部 AppThemeMode，且每套主题均注入 EditorTokens', () {
      // 若未来新增枚举值但漏配主题 / 漏注入 extension，此断言即失败。
      for (final mode in AppThemeMode.values) {
        final theme = AppTheme.themeFor(mode);
        expect(
          theme.extension<EditorTokens>(),
          isNotNull,
          reason: '$mode 主题必须注入 EditorTokens，否则 of(context) 空断言崩溃',
        );
      }
    });
  });

  group('EditorTokens.of(context) 运行时解析', () {
    testWidgets('of(context) 返回当前 ThemeData 注入的实例（dark）', (tester) async {
      late EditorTokens captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              captured = EditorTokens.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(captured, same(EditorTokens.dark));
      expect(captured.textPrimary, EditorTokens.dark.textPrimary);
    });

    testWidgets('切换 ThemeData 后 of(context) 反映新颜色（light → dark）', (tester) async {
      final modeNotifier = ValueNotifier<AppThemeMode>(AppThemeMode.light);
      addTearDown(modeNotifier.dispose);

      Color? seen;
      await tester.pumpWidget(
        ValueListenableBuilder<AppThemeMode>(
          valueListenable: modeNotifier,
          builder: (context, mode, _) => MaterialApp(
            theme: AppTheme.themeFor(mode),
            home: Builder(
              builder: (context) {
                seen = EditorTokens.of(context).codeBackground;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(seen, EditorTokens.light.codeBackground);

      modeNotifier.value = AppThemeMode.dark;
      // MaterialApp 用 AnimatedTheme 对 ThemeExtension 做 lerp（~200ms），
      // 单次 pump 只会拿到中间插值色，需 settle 到动画结束再断言终值。
      await tester.pumpAndSettle();
      expect(seen, EditorTokens.dark.codeBackground);
      expect(seen, isNot(EditorTokens.light.codeBackground));
    });
  });

  group('ThemeExtension 契约：copyWith / lerp', () {
    test('copyWith 只覆盖指定字段，其余保持不变', () {
      const base = EditorTokens.light;
      final changed = base.copyWith(textPrimary: const Color(0xFF123456));
      expect(changed.textPrimary, const Color(0xFF123456));
      expect(changed.codeBackground, base.codeBackground);
      expect(changed.tableBorderColor, base.tableBorderColor);
    });

    test('lerp t=0 取自身色，t=1 取 other 色', () {
      const a = EditorTokens.light;
      const b = EditorTokens.dark;
      final at0 = a.lerp(b, 0.0);
      final at1 = a.lerp(b, 1.0);
      expect(at0.textPrimary, a.textPrimary);
      expect(at1.textPrimary, b.textPrimary);
    });

    test('lerp 传入非 EditorTokens 时返回自身', () {
      const a = EditorTokens.light;
      final result = a.lerp(null, 0.5);
      expect(result, same(a));
    });
  });
}
