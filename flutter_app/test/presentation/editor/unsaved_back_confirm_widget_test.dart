/// issue #333-A 未保存内容 BACK 确认 — widget 测试。
///
/// 覆盖：
///   1. 有未保存内容（isDirty=true）BACK → 「放弃未保存的更改？」确认对话框
///      出现，编辑器不直接退出。
///   2. 确认「放弃并退出」→ 路由回首页。
///   3. 「继续编辑」→ 留在编辑器，不退出。
///   4. 无未保存内容（isDirty=false）BACK → 直接回首页，无对话框（原行为不变）。
///
/// 直接用 [ExportGuardPopScope] 泵最小 GoRouter（/ ↔ /home），
/// [isDirtyGetter] 用可翻转的布尔变量注入，聚焦守卫自身的分支逻辑
/// （EditorPage 侧接线由 editor_page 的 isDirtyGetter 注入单测覆盖）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tafcm/presentation/editor/export_guard_pop_scope.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';

/// 测试用 `InAppWebViewPlatform` 桩（与 export_back_confirm_widget_test 同源）。
class _FakeInAppWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    return _NoopPlatformInAppWebViewWidget(params);
  }
}

class _NoopPlatformInAppWebViewWidget extends PlatformInAppWebViewWidget {
  _NoopPlatformInAppWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) {
    throw UnimplementedError(
        'NoopPlatformInAppWebViewWidget.controllerFromPlatform');
  }

  @override
  void dispose() {}
}

/// 泵 [ExportGuardPopScope]：dirty 由外部变量控制，child 是编辑桩。
/// 返回翻转 dirty 的闭包。
Future<void> _pumpGuard(
  WidgetTester tester,
  bool Function() isDirtyGetter,
) async {
  final router = GoRouter(
    initialLocation: '/editor',
    routes: [
      GoRoute(
        path: '/editor',
        builder: (context, state) => ExportGuardPopScope(
          isDirtyGetter: isDirtyGetter,
          child: const Scaffold(body: Center(child: Text('editor-stub'))),
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('home-stub'))),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 触发系统返回（复刻 Android BACK → Navigator.maybePop → PopScope 拦截）。
Future<void> _simulateSystemBack(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  await navigator.maybePop();
}

void main() {
  setUpAll(() {
    InAppWebViewPlatform.instance = _FakeInAppWebViewPlatform();
    SharedPreferences.setMockInitialValues({});
  });

  group('issue #333-A 未保存内容 BACK 确认', () {
    testWidgets('1. 有未保存内容 BACK → 确认对话框出现，编辑器不直接退出',
        (tester) async {
      var dirty = true;
      await _pumpGuard(tester, () => dirty);

      await _simulateSystemBack(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('放弃未保存的更改？'), findsOneWidget);
      expect(find.text('继续编辑'), findsOneWidget);
      expect(find.text('放弃并退出'), findsOneWidget);
      expect(find.text('editor-stub'), findsOneWidget);
      expect(find.text('home-stub'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('2. 确认「放弃并退出」→ 回首页', (tester) async {
      var dirty = true;
      await _pumpGuard(tester, () => dirty);

      await _simulateSystemBack(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('放弃并退出'));
      await tester.pumpAndSettle();

      expect(find.text('home-stub'), findsOneWidget);
      expect(find.text('editor-stub'), findsNothing);
      expect(find.text('放弃未保存的更改？'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('3. 「继续编辑」→ 留在编辑器，不退出', (tester) async {
      var dirty = true;
      await _pumpGuard(tester, () => dirty);

      await _simulateSystemBack(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('继续编辑'));
      // 对话框关闭动画收敛后编辑器仍在（无在途导出，可安全 settle）。
      await tester.pumpAndSettle();

      expect(find.text('放弃未保存的更改？'), findsNothing);
      expect(find.text('editor-stub'), findsOneWidget);
      expect(find.text('home-stub'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. 无未保存内容 BACK → 直接回首页，无对话框（原行为不变）',
        (tester) async {
      var dirty = false;
      await _pumpGuard(tester, () => dirty);

      await _simulateSystemBack(tester);
      await tester.pumpAndSettle();

      expect(find.text('home-stub'), findsOneWidget);
      expect(find.text('editor-stub'), findsNothing);
      expect(find.text('放弃未保存的更改？'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('5. dirty 为 null（未注入）→ 直接回首页（旧行为）', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: GoRouter(
              initialLocation: '/editor',
              routes: [
                GoRoute(
                  path: '/editor',
                  builder: (context, state) => const ExportGuardPopScope(
                    child: Scaffold(body: Center(child: Text('editor-stub'))),
                  ),
                ),
                GoRoute(
                  path: '/home',
                  builder: (context, state) =>
                      const Scaffold(body: Center(child: Text('home-stub'))),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _simulateSystemBack(tester);
      await tester.pumpAndSettle();

      expect(find.text('home-stub'), findsOneWidget);
      expect(find.text('放弃未保存的更改？'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
