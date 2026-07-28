import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/constants/app_constants.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/blocks/formula/formula_block.dart';
import 'package:formula_fix/presentation/widgets/formula_renderer.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';
import 'package:formula_fix/presentation/theme/app_typography.dart';

/// FormulaRenderer / FormulaBlock 的 Typora 化「公式块严格还原」验证（Phase 3.5.1）。
///
/// 关键断言：
/// 1. 降级态（测试环境无 WebView）→ 经 `flutter_math_fork` 真实渲染（非源码文本），居中，无卡片/边框。
/// 2. 字体族为 serif、字重 italic（非旧版 deepPurple 内联样式）。
/// 3. 颜色经 [EditorTokens] 注入，随 light/dark 主题切换。
/// 4. 行内公式（displayMode=false）同样真实渲染为 serif italic，无卡片。
void main() {
  group('FormulaRenderer (Typora 严格还原 / 统一渲染)', () {
    testWidgets('降级态：flutter_math_fork 真实渲染 + 居中 + 无卡片', (tester) async {
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

      // 真实渲染（flutter_math_fork），不显示源码字面量
      expect(find.byType(FormulaRenderer), findsOneWidget);
      expect(find.byType(Math), findsWidgets);
      expect(find.text('E=mc^2'), findsNothing);
      // 降级态（无 SVG）不重复显示 mono 源码行
      expect(find.text('\$\$E=mc^2\$\$'), findsNothing);

      final math = tester.widget<Math>(find.byType(Math));
      expect(math.mathStyle, MathStyle.display);
      expect(math.textStyle?.fontStyle, FontStyle.italic);
      expect(math.textStyle?.fontFamily, AppTypography.serif);
      // 颜色来自 EditorTokens.light.textPrimary（#1A1D23），非硬编码
      expect(math.textStyle?.color, const Color(0xFF1A1D23));

      // 无卡片：不存在 formulaInlineBg 背景的装饰容器
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              ((w.decoration as BoxDecoration).color == AppColors.formulaInlineBg ||
                  (w.decoration as BoxDecoration).color == AppColors.darkFormulaInlineBg),
        ),
        findsNothing,
      );
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

      final math = tester.widget<Math>(find.byType(Math));
      // dark 主题 foreground = #E8EAED（EditorTokens.dark.textPrimary）
      expect(math.textStyle?.color, const Color(0xFFE8EAED));
    });

    testWidgets('行内公式（displayMode=false）经统一渲染为 serif italic', (tester) async {
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

      final math = tester.widget<Math>(find.byType(Math));
      expect(math.mathStyle, MathStyle.text);
      expect(math.textStyle?.fontStyle, FontStyle.italic);
      expect(math.textStyle?.fontFamily, AppTypography.serif);
      // 行内同样无卡片
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              ((w.decoration as BoxDecoration).color == AppColors.formulaInlineBg),
        ),
        findsNothing,
      );
    });
  });
}
