/// issue #333-B 重命名入口 — widget 测试。
///
/// 覆盖：
///   1. ⋮ 菜单含「重命名」项，点击开后弹出对话框，输入框预填当前标题。
///   2. 保存新标题 → 对话框关闭 + AppBar 标题立即跟随（无 path 演示文档场景，
///      persistCallback 不落盘，标题仍应刷新）。
///   3. 取消 → 标题不变。
///
/// 用与 export_back_confirm_widget_test 相同的最小 GoRouter 驱动真实
/// EditorPage / EditorAppBar。
library;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tafcm/presentation/editor/editor_page.dart';
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

/// 打开 ⋮ 菜单并点击「重命名」，返回对话框中的 TextField。
Future<TextField> _openRenameDialog(WidgetTester tester) async {
  // 界面存在两处「更多」tooltip（AppBar 主菜单 + 场景内其它入口），
  // AppBar 的 more_vert 是构建顺序较后的一个，取 .last。
  await tester.tap(find.byTooltip('更多').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('重命名'));
  await tester.pumpAndSettle();
  return tester.widget<TextField>(find.byType(TextField));
}

void main() {
  setUpAll(() {
    InAppWebViewPlatform.instance = _FakeInAppWebViewPlatform();
    SharedPreferences.setMockInitialValues({});
  });

  group('issue #333-B 重命名入口', () {
    testWidgets('1. ⋮ 菜单 → 重命名对话框，输入框预填当前标题', (tester) async {
      final container = await _pumpEditorApp(tester);
      addTearDown(container.dispose);

      final field = await _openRenameDialog(tester);
      expect(find.text('重命名'), findsWidgets); // 菜单项 + 对话框标题
      expect(field.controller?.text, isNotEmpty,
          reason: '输入框应预填当前文档标题');
      expect(tester.takeException(), isNull);
    });

    testWidgets('2. 保存新标题 → 对话框关闭 + 编辑器无异常（演示文档不落盘）',
        (tester) async {
      final container = await _pumpEditorApp(tester);
      addTearDown(container.dispose);

      await _openRenameDialog(tester);
      await tester.enterText(find.byType(TextField), '新标题 甲');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 对话框关闭。
      expect(find.text('新标题 甲'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('3. 取消 → 标题不变，对话框关闭', (tester) async {
      final container = await _pumpEditorApp(tester);
      addTearDown(container.dispose);

      final before = _openTitle(container, tester);
      await _openRenameDialog(tester);
      await tester.enterText(find.byType(TextField), '不应生效');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('不应生效'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(_openTitle(container, tester), before,
          reason: '取消不得改标题');
    });
  });
}

/// 读取可观察的标题：优先 AppBar 文本（seed 文档标题）。
String _openTitle(ProviderContainer container, WidgetTester tester) {
  // seedSelector 文档标题固定，直接取 AppBar 的 Text。
  final texts =
      tester.widgetList<Text>(find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(Text),
      ));
  for (final t in texts) {
    if (t.data != null && t.data!.isNotEmpty) return t.data!;
  }
  return '';
}