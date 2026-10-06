/// issue #323 导出中 BACK 确认 — widget 测试。
///
/// 覆盖：
///   1. 导出进行中 BACK（maybePop）→ 确认对话框出现（不直接退出）。
///   2. 「取消导出并退出」→ 协作式取消 + 返回首页 + 浮层消失 + 无异常。
///   3. 「继续导出」→ 留在编辑器，导出继续（状态保持 InProgress）。
///   4. 非导出态 BACK → 行为不变（直接回首页，无对话框）。
///   5. 兜底：ExportProgressOverlay 销毁（编辑器路由离开）→ 在途导出被取消
///      且状态归 Idle（杜绝「既不取消也不完成」孤儿）。
///
/// 用最小 GoRouter（/editor ↔ /home）驱动真实 EditorPage / ExportGuardPopScope，
/// 导出管线用注册到 MarkdownExporter 的假 PDF exporter 模拟（协作式取消）。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tafcm/core/observability/observability_service.dart';
import 'package:tafcm/domain/providers/export_progress_provider.dart';
import 'package:tafcm/domain/services/export_cancel_token.dart';
import 'package:tafcm/domain/services/export_service.dart';
import 'package:tafcm/presentation/editor/editor_page.dart';
import 'package:tafcm/presentation/editor/editor_shell.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'package:tafcm/presentation/widgets/export_progress_overlay.dart';

/// 挂起型假 PDF exporter：模拟协作式导出管线——持续上报进度，直到
/// 取消令牌置位后抛出 [ExportCancelledException]（真实管线的检查点行为）。
class _HangingPdfExporter implements PdfExporterInterface {
  @override
  Future<Uint8List> export(
    String markdown, {
    String? title,
    String? author,
    bool isDark = false,
    ExportProgressCallback? onProgress,
    ObservabilityService? observability,
    ExportCancelToken? cancelToken,
  }) async {
    onProgress?.call(const ExportProgress(
      stage: ExportStage.renderingBlocks,
      completed: 3,
      total: 9,
    ));
    // 模拟长耗时管线：逐 tick 推进，直到协作式取消命中。
    while (cancelToken == null || !cancelToken.isCancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      onProgress?.call(const ExportProgress(
        stage: ExportStage.renderingBlocks,
        completed: 4,
        total: 9,
      ));
    }
    throw const ExportCancelledException();
  }
}

/// 测试用 `InAppWebViewPlatform` 桩（与 file_tree_behavior_test 同源）：
/// 返回空 Widget，避免单元测试初始化平台 WebView。
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

Future<ProviderContainer> _pumpEditorApp(WidgetTester tester) async {
  final container = ProviderContainer();
  final router = GoRouter(
    initialLocation: '/editor',
    routes: [
      GoRoute(
        path: '/editor',
        builder: (context, state) => const EditorPage(seedSelector: 0),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('home-stub'))),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 触发系统返回（复刻 Android BACK → Navigator.maybePop → PopScope 拦截）。
Future<void> _simulateSystemBack(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  await navigator.maybePop();
}

/// 启动一次导出（经真实 AppBar 菜单 → handleExport → runWithGuard → 假管线）。
Future<void> _startExport(WidgetTester tester) async {
  await tester.tap(find.byTooltip('导出'));
  await tester.pumpAndSettle(); // 菜单打开（此时无导出在途，可 settle）
  await tester.tap(find.text('导出为 PDF'));
  // 导出开始后假管线持续排帧，不能 pumpAndSettle（永不收敛）。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() {
    InAppWebViewPlatform.instance = _FakeInAppWebViewPlatform();
    SharedPreferences.setMockInitialValues({});
  });

  // 导出相关用例经真实 AppBar 菜单触发 handleExport → 管线用假 exporter
  // 挂起（真实 PdfExporter 会瞬间完成，无法构造「导出进行中」场景）。
  late void Function() disposeFake;
  setUp(() {
    disposeFake = MarkdownExporter.register(pdf: _HangingPdfExporter());
  });
  tearDown(() => disposeFake());

  group('issue #323 导出中 BACK 确认', () {
    testWidgets('1. 导出进行中 BACK → 确认对话框出现，编辑器不直接退出',
        (tester) async {
      final container = await _pumpEditorApp(tester);
      await _startExport(tester);
      expect(find.textContaining('正在导出 PDF'), findsOneWidget);

      await _simulateSystemBack(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 对话框出现，编辑器仍在原位。
      expect(find.text('导出进行中'), findsOneWidget);
      expect(find.text('继续导出'), findsOneWidget);
      expect(find.text('取消导出并退出'), findsOneWidget);
      expect(find.byType(EditorShell), findsOneWidget);
      expect(find.text('home-stub'), findsNothing);
      expect(tester.takeException(), isNull);
      addTearDown(container.dispose);
      // 清理在途导出，避免 teardown 挂着假管线循环。
      container.read(exportProgressProvider.notifier).cancel();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('2. 确认「取消导出并退出」→ 取消导出 + 回首页 + 浮层消失',
        (tester) async {
      final container = await _pumpEditorApp(tester);
      await _startExport(tester);
      expect(find.textContaining('正在导出 PDF'), findsOneWidget);

      await _simulateSystemBack(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('取消导出并退出'));
      // 路由替换 + 假管线在下一个 tick 观察到取消 → 抛出 → runWithGuard 收敛。
      await tester.pump();
      await tester.pumpAndSettle();

      // 回到首页，编辑器与浮层均已消失。
      expect(find.text('home-stub'), findsOneWidget);
      expect(find.byType(EditorShell), findsNothing);
      expect(find.textContaining('正在导出'), findsNothing);
      // 状态机归 Idle（非 Failed），取消不报错。
      expect(container.read(exportProgressProvider), isA<ExportIdleState>());
      expect(tester.takeException(), isNull);
      addTearDown(container.dispose);
    });

    testWidgets('3. 「继续导出」→ 留在编辑器，导出继续', (tester) async {
      final container = await _pumpEditorApp(tester);
      await _startExport(tester);
      expect(find.textContaining('正在导出 PDF'), findsOneWidget);

      await _simulateSystemBack(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('继续导出'));
      // 对话框退出动画（~150ms）+ 动画完成后的卸载帧；导出仍在途，不能 settle。
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // 对话框关闭，编辑器仍在，导出未被取消（仍 InProgress + 浮层在）。
      expect(find.text('导出进行中'), findsNothing);
      expect(find.byType(EditorShell), findsOneWidget);
      expect(find.text('home-stub'), findsNothing);
      expect(container.read(exportProgressProvider),
          isA<ExportInProgressState>());
      expect(find.textContaining('正在导出 PDF'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 清理：取消在途导出，让假管线收敛，避免 teardown 挂起。
      container.read(exportProgressProvider.notifier).cancel();
      await tester.pumpAndSettle();
      expect(container.read(exportProgressProvider), isA<ExportIdleState>());
      addTearDown(container.dispose);
    });

    testWidgets('4. 非导出态 BACK → 行为不变（直接回首页，无对话框）',
        (tester) async {
      final container = await _pumpEditorApp(tester);
      expect(find.textContaining('正在导出'), findsNothing);

      await _simulateSystemBack(tester);
      await tester.pumpAndSettle();

      expect(find.text('home-stub'), findsOneWidget);
      expect(find.byType(EditorShell), findsNothing);
      expect(find.text('导出进行中'), findsNothing);
      expect(tester.takeException(), isNull);
      addTearDown(container.dispose);
    });
  });

  group('issue #323 浮层销毁兜底取消', () {
    testWidgets('5. ExportProgressOverlay 卸载 → 在途导出被取消并归 Idle',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      var showOverlay = true;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  // postFrame 启动导出（ref.listen 不在初始值触发的既有绕行模式）。
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ref.read(exportProgressProvider.notifier).start(ExportFormat.pdf);
                  });
                  return showOverlay
                      ? const ExportProgressOverlay(
                          key: ValueKey('overlay'),
                          child: Text('anchor'),
                        )
                      : const Text('no-overlay');
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump(); // 首帧挂载
      await tester.pump(); // postFrame → start()
      expect(container.read(exportProgressProvider), isA<ExportInProgressState>());
      expect(container.read(exportProgressProvider.notifier).activeCancelToken,
          isNotNull);

      // 卸载浮层（模拟编辑器路由离开）→ dispose 兜底取消。
      showOverlay = false;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: Text('no-overlay')),
          ),
        ),
      );
      // postFrame 兜底回调在当前帧末尾执行。
      await tester.pump();

      expect(container.read(exportProgressProvider), isA<ExportIdleState>());
      // 令牌已归还：无孤儿取消令牌。
      expect(container.read(exportProgressProvider.notifier).activeCancelToken,
          isNull);
    });
  });
}
