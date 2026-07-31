/// PR-F / P2-1：令牌化按钮组件单测。
///
/// 在 [AppTheme.lightTheme] 下泵入（该主题注入 [EditorTokens.light]），
/// 验证 4 个组件正确渲染且交互回调触发。golden 不涉及（本文件仅断言
/// 组件行为与令牌消费，不比对像素）。
import 'package:flutter/material.dart';
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

    testWidgets('onChanged 为 null 时禁用且不回调', (tester) async {
      var called = false;
      await tester.pumpWidget(
        _harness(const AppToggle(value: true, onChanged: null)),
      );
      // 无 onChanged → GestureDetector.onTap 为 null，tap 不触发回调。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AppToggle)),
      );
      await gesture.up();
      await tester.pump();
      expect(called, isFalse);
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
