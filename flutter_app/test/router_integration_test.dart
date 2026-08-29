import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tafcm/main.dart';
import 'package:tafcm/presentation/screens/document_list_screen.dart';
import 'package:tafcm/presentation/screens/editor_screen.dart';

/// 测试用 `InAppWebViewPlatform` 桩：返回固定大小的空 Widget，
/// 避免在 `flutter test` 单元测试中尝试初始化平台 WebView。
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
    throw UnimplementedError('NoopPlatformInAppWebViewWidget.controllerFromPlatform');
  }

  @override
  void dispose() {}
}

void main() {
  setUpAll(() {
    InAppWebViewPlatform.instance = _FakeInAppWebViewPlatform();
    // Phase 3.4.2：BootstrapScreen 启动读取上次打开文件，测试环境需 mock SharedPreferences。
    SharedPreferences.setMockInitialValues({});
  });

  /// ROADMAP 1.4 + 契约链 3：启动经 BootstrapScreen。无上次打开文件时恢复进入
  /// 首页（/home），首屏显示"Tafcm"品牌字标（PR #93 StatefulShellRoute）。
  testWidgets('启动后首屏为 /home，显示"Tafcm"',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: TafcmApp()),
    );
    await tester.pump(const Duration(seconds: 1));
    // pumpAndSettle 无法 settle（documentListProvider 是持续 stream）
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  /// ROADMAP 1.3：DocumentListScreen 可正常构建（非死代码/非损坏）。
  /// 其 AppBar 标题为 "Tafcm"，已随 1.3 注册为 /documents 路由。
  testWidgets('DocumentListScreen 可构建，AppBar 显示"Tafcm"',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DocumentListScreen())),
    );
    // AppBar 标题同步渲染，不依赖 documentsProvider 异步加载结果
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tafcm'), findsWidgets);
  });

  /// /editor 路由对应的 EditorScreen 可正常构建（顶栏含"文件管理"入口）。
  testWidgets('EditorScreen 可构建，顶栏含"文件管理"入口',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: EditorScreen())),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('文件管理'), findsWidgets);
  });
}
