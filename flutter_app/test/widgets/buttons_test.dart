/// PR-F / P2-1：令牌化按钮组件单测。
///
/// 在 [AppTheme.lightTheme] 下泵入（该主题注入 [EditorTokens.light]），
/// 验证 4 个组件正确渲染、交互回调触发、键盘可达性与语义标签。
/// golden 不涉及（本文件仅断言组件行为与令牌消费，不比对像素）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/presentation/theme/app_theme.dart';
import 'package:formula_fix/presentation/widgets/buttons.dart';

Widget _harness(Widget child) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('GhostButton', () {
    testWidgets('渲染图标并在 tap 时触发 onTap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _harness(GhostButton(icon: Icons.search, onTap: () => tapped++)),
      );
      expect(find.byIcon(Icons.search), findsOneWidget);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('onTap 为 null 时不抛错', (tester) async {
      await tester.pumpWidget(_harness(const GhostButton(icon: Icons.add)));
      expect(find.byIcon(Icons.add), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
    });

    testWidgets('注入 semanticLabel 后语义树含 label', (tester) async {
      final handle = tester.ensureSemantics();
      addTearDown(handle.dispose);
      await tester.pumpWidget(
        _harness(const GhostButton(icon: Icons.search, semanticLabel: '搜索')),
      );
      expect(tester.getSemantics(find.byType(GhostButton)).label, '搜索');
    });
  });

  group('AppToggle', () {
    testWidgets('tap 以取反值回调 onChanged', (tester) async {
      var value = false;
      await tester.pumpWidget(
        _harness(AppToggle(
          value: value,
          onChanged: (v) => value = v,
        )),
      );
      await tester.tap(find.byType(AppToggle));
      await tester.pumpAndSettle();
      expect(value, isTrue);
    });

    testWidgets('onChanged 为 null 时禁用且 tap 不翻转状态', (tester) async {
      final handle = tester.ensureSemantics();
      addTearDown(handle.dispose);
      await tester.pumpWidget(
        _harness(const AppToggle(value: true, onChanged: null)),
      );
      // 禁用态语义：toggled 反映当前 value（true）。
      expect(tester.getSemantics(find.byType(AppToggle)).toggled, isTrue);
      // tap 不触发回调（onTap 为 null），语义 toggled 保持不变。
      await tester.tap(find.byType(AppToggle));
      await tester.pump();
      expect(tester.getSemantics(find.byType(AppToggle)).toggled, isTrue);
    });

    testWidgets('键盘 Enter/Space 各触发 onChanged 恰好一次', (tester) async {
      var value = true;
      var calls = 0;
      await tester.pumpWidget(
        _harness(AppToggle(
          value: value,
          onChanged: (v) {
            value = v;
            calls++;
          },
        )),
      );
      // 首次 tap：聚焦 + 翻转为 false。
      await tester.tap(find.byType(AppToggle));
      await tester.pumpAndSettle();
      expect(value, isFalse);
      expect(calls, 1);
      // 键盘 Enter：再翻转为 true（恰好一次）。
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(value, isTrue);
      expect(calls, 2);
      // 键盘 Space：再翻转为 false（恰好一次，不重复触发）。
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(value, isFalse);
      expect(calls, 3);
    });

    testWidgets('注入 semanticLabel 后语义树含 label 与 toggled', (tester) async {
      final handle = tester.ensureSemantics();
      addTearDown(handle.dispose);
      await tester.pumpWidget(
        _harness(const AppToggle(
          value: false,
          onChanged: null,
          semanticLabel: '深色模式',
        )),
      );
      final data = tester.getSemantics(find.byType(AppToggle));
      expect(data.label, '深色模式');
      expect(data.toggled, isFalse);
    });
  });

  group('SearchPill', () {
    testWidgets('输入触发 onChanged 并携带完整文本', (tester) async {
      String? text;
      await tester.pumpWidget(
        _harness(SearchPill(onChanged: (t) => text = t)),
      );
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(text, 'hello');
    });

    testWidgets('渲染前缀搜索图标', (tester) async {
      await tester.pumpWidget(_harness(const SearchPill()));
      expect(find.byIcon(Icons.search), findsOneWidget);
    });
  });

  group('AppFab', () {
    testWidgets('tap 触发 onPressed', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        _harness(AppFab(
          icon: Icons.add,
          onPressed: () => pressed++,
        )),
      );
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      expect(pressed, 1);
    });
  });
}
