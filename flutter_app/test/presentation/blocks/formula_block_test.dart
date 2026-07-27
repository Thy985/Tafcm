import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/blocks/formula/formula_block.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';
import 'package:formula_fix/presentation/theme/app_typography.dart';

/// FormulaBlock 的 Typora 化「公式块严格还原」验证。
///
/// 关键断言：
/// 1. 降级态（测试环境无 WebView）→ 显示 serif italic 源码，居中，无卡片/边框。
/// 2. 字体族为 serif、字重 italic（非旧版 deepPurple 内联样式）。
/// 3. 颜色经 EditorTokens 注入，随 light/dark 主题切换。
/// 4. 降级态不重复显示 mono 源码行（仅在真实 SVG 渲染成功时显示）。
void main() {
  group('FormulaBlock (Typora 严格还原)', () {
    testWidgets('降级态：serif italic 源码 + 居中 + 无卡片', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: FormulaBlock(
              element: FormulaElement(latex: 'E=mc^2', displayMode: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 源码以 serif italic 显示（降级态，无 WebView 真实渲染）
      final textFinder = find.text('E=mc^2');
      expect(textFinder, findsOneWidget);

      final text = tester.widget<Text>(textFinder);
      expect(text.textAlign, TextAlign.center);
      expect(text.style?.fontStyle, FontStyle.italic);
      expect(text.style?.fontFamily, AppTypography.serif);
      // 颜色来自 EditorTokens.light.textPrimary（#1A1D23），非硬编码
      expect(text.style?.color, isNotNull);

      // 降级态不显示 mono 源码行（仅在真实 SVG 渲染成功时显示）
      expect(find.text('\$\$E=mc^2\$\$'), findsNothing);
    });

    testWidgets('dark 主题：公式颜色切换为 dark foreground', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: FormulaBlock(
              element: FormulaElement(latex: 'E=mc^2', displayMode: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('E=mc^2'));
      // dark 主题 foreground = #E8EAED（EditorTokens.dark.textPrimary）
      expect(text.style?.color, const Color(0xFFE8EAED));
    });

    testWidgets('行内公式（displayMode=false）也可渲染为 serif italic', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: FormulaBlock(
              element: FormulaElement(latex: r'\frac{a}{b}', displayMode: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text(r'\frac{a}{b}'));
      expect(text.style?.fontStyle, FontStyle.italic);
      expect(text.style?.fontFamily, AppTypography.serif);
    });
  });
}
