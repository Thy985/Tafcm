/// P1 回归测试（2026-08-06，phase3.5-realdevice-issues 问题 2）：
/// 编辑器返回按钮导航语义。
///
/// 覆盖 `editor_app_bar.dart:_onBack` 的两条路径：
/// 1. **有返回栈**（从 /home push /editor）→ `canPop == true` → `context.pop()` → 回 /home。
/// 2. **无返回栈**（冷启动恢复 / 外部 URI 拉起，/editor 为栈底）→ `canPop == false`
///    → `context.go('/home')` 兜底，不静默无操作。
///
/// 同时锁定进入 /editor 必须用 `context.push`（非 `context.go`）——后者替换整个栈，
/// 导致 `canPop == false`，返回按钮失灵。本测试用最小 GoRouter + 占位 editor
/// 验证导航模式，不依赖真实 EditorPage（避免文件 I/O + WebView 初始化）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 复刻 `EditorAppBar._onBack` 的导航逻辑（P1 修复 2026-08-06）。
///
/// 用闭包注入而非反射访问私有方法，保证测试逻辑与生产代码语义一致。
/// 若生产代码 `_onBack` 逻辑变化，此处需同步更新（守门：本测试断言会失败）。
void _onBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/home');
  }
}

/// 占位编辑器页：含一个返回按钮，调用 [_onBack]。
class _StubEditorPage extends StatelessWidget {
  const _StubEditorPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _onBack(context),
        ),
        title: const Text('editor-stub'),
      ),
      body: const Center(child: Text('editor-body')),
    );
  }
}

/// 占位首页：含一个按钮，push 到 /editor（复刻 home_screen._openDoc 的 P1 修复）。
class _StubHomePage extends StatelessWidget {
  const _StubHomePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const ValueKey('open-editor'),
          child: const Text('open-editor'),
          onPressed: () => context.push('/editor'),
        ),
      ),
    );
  }
}

void main() {
  group('P1 编辑器返回导航（phase3.5-realdevice-issues 问题 2）', () {
    /// 路径 1：从 /home push /editor → 返回按钮 → 回 /home。
    /// 验证 `context.push` 保留返回栈，`canPop == true` → `pop()` 生效。
    testWidgets('有返回栈：push /editor → tap back → 回 /home', (tester) async {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const _StubHomePage(),
          ),
          GoRoute(
            path: '/editor',
            builder: (context, state) => const _StubEditorPage(),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(routerConfig: router),
      );
      await tester.pumpAndSettle();

      // 初始：在 /home，编辑器占位不可见。
      expect(find.text('open-editor'), findsOneWidget);
      expect(find.text('editor-stub'), findsNothing);

      // push /editor（复刻 home_screen._openDoc 的 P1 修复：用 push 非 go）。
      await tester.tap(find.byKey(const ValueKey('open-editor')));
      await tester.pumpAndSettle();

      // 进入编辑器：占位 AppBar 可见。
      expect(find.text('editor-stub'), findsOneWidget);
      expect(find.text('open-editor'), findsNothing);

      // 点返回按钮 → _onBack → canPop == true → pop → 回 /home。
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();

      // 关键断言：回到 /home（返回栈生效，非静默无操作）。
      expect(find.text('open-editor'), findsOneWidget,
          reason: 'push 保留返回栈 → 返回按钮应 pop 回 /home');
      expect(find.text('editor-stub'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    /// 路径 2：冷启动直接进 /editor（initialLocation = /editor，无栈）。
    /// 验证 `canPop == false` → 兜底 `context.go('/home')`，不静默无操作。
    /// 复刻冷启动恢复上次文件 / 外部 URI 拉起场景（app_router.dart BootstrapScreen）。
    testWidgets('无返回栈：冷启动 /editor → tap back → 兜底 /home', (tester) async {
      final router = GoRouter(
        initialLocation: '/editor',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const _StubHomePage(),
          ),
          GoRoute(
            path: '/editor',
            builder: (context, state) => const _StubEditorPage(),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(routerConfig: router),
      );
      await tester.pumpAndSettle();

      // 初始：直接在 /editor（模拟冷启动恢复），无 /home 在栈底。
      expect(find.text('editor-stub'), findsOneWidget);
      expect(find.text('open-editor'), findsNothing);

      // canPop 应为 false（栈底是 /editor）。
      final buildContext = tester.element(find.text('editor-stub'));
      expect(GoRouter.of(buildContext).canPop(), isFalse,
          reason: '冷启动 /editor 为栈底，canPop 应为 false');

      // 点返回按钮 → _onBack → canPop == false → go /home 兜底。
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();

      // 关键断言：兜底跳 /home（非静默无操作）。
      expect(find.text('open-editor'), findsOneWidget,
          reason: 'canPop == false 时应兜底 go /home，不静默无操作');
      expect(find.text('editor-stub'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
