/// 3.4.3 主题切换 E2E（Phase 3.4 Slice 3 / ADR-0015）。
///
/// 覆盖 q-0 三大 P0 风险的**端到端完整链路**验证：
/// - 链路：主题偏好 → themeModeProvider → ThemeData → ThemeExtension(EditorTokens)
///   → Builder 内 EditorTokens.of(context) 取色。
/// - **风险1（注入遗漏）**：三套主题下 of(context) 均能取到 textPrimary（不崩溃）。
/// - **风险2（二值→三值 + 兼容迁移）**：
///   · 切换到夜间 → 关 App 重开 → 持久化恢复为 dark；
///   · 旧 `pref_dark_mode=true` 首次启动即迁移为 dark；
///   · light → dark → sepia → light 三值循环。
///
/// 说明：与其余 integration_test 用例一致，本文件在默认 widget-test binding 下运行
/// （`flutter test integration_test/...`），用 `SharedPreferences.setMockInitialValues`
/// 注入内存 mock，不触达真实存储（v2.1 §3.3.1 Hard Rule）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tafcm/presentation/theme/app_theme.dart';
import 'package:tafcm/presentation/themes/editor_tokens.dart';
import 'package:tafcm/providers/editor_providers.dart';

/// 最小主题宿主：镜像 main.dart 的接线（watch themeModeProvider → themeFor），
/// 并在 body 内经 [EditorTokens.of] 取色以验证完整链路 + 注入完整性。
class _ThemeHarness extends ConsumerWidget {
  const _ThemeHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      theme: AppTheme.themeFor(mode),
      home: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              key: const Key('theme_toggle'),
              icon: const Icon(Icons.brightness_6),
              onPressed: () => ref.read(themeModeProvider.notifier).cycle(),
            ),
          ],
        ),
        body: Builder(
          builder: (ctx) {
            // 若当前主题未注入 EditorTokens，这里 of() 空断言即崩溃（风险1）。
            final tokens = EditorTokens.of(ctx);
            return Text(
              'mode=${mode.name}',
              style: TextStyle(color: tokens.textPrimary),
            );
          },
        ),
      ),
    );
  }
}

void main() {
  group('3.4.3 主题切换 E2E（ADR-0015 完整链路）', () {
    testWidgets('切换到夜间 → 关 App 重开 → 主题持久化为 dark', (tester) async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});

      // 首次启动：默认 light
      await tester.pumpWidget(const ProviderScope(child: _ThemeHarness()));
      await tester.pumpAndSettle();
      expect(find.text('mode=light'), findsOneWidget);

      // 点击切换一次 → dark
      await tester.tap(find.byKey(const Key('theme_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('mode=dark'), findsOneWidget);

      // 链 3（持久化）：pref_theme_mode 已写入 'dark'
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pref_theme_mode'), 'dark');

      // 模拟「关 App 重开」：卸载旧树 → 全新 ProviderScope（新容器），mock 存储保留
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const ProviderScope(child: _ThemeHarness()));
      await tester.pumpAndSettle();

      // 重开后从持久化恢复为 dark
      expect(find.text('mode=dark'), findsOneWidget);
    });

    testWidgets('兼容迁移：旧 pref_dark_mode=true → 首次启动即 dark', (tester) async {
      SharedPreferences.setMockInitialValues(
        const <String, Object>{'pref_dark_mode': true},
      );
      await tester.pumpWidget(const ProviderScope(child: _ThemeHarness()));
      await tester.pumpAndSettle();
      expect(find.text('mode=dark'), findsOneWidget);
    });

    testWidgets('三主题循环：light → dark → sepia → light', (tester) async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      await tester.pumpWidget(const ProviderScope(child: _ThemeHarness()));
      await tester.pumpAndSettle();
      expect(find.text('mode=light'), findsOneWidget);

      Future<void> tapToggle() async {
        await tester.tap(find.byKey(const Key('theme_toggle')));
        await tester.pumpAndSettle();
      }

      await tapToggle();
      expect(find.text('mode=dark'), findsOneWidget);
      await tapToggle();
      expect(find.text('mode=sepia'), findsOneWidget);
      await tapToggle();
      expect(find.text('mode=light'), findsOneWidget);
    });
  });
}
