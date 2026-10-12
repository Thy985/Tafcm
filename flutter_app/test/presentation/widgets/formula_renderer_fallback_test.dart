import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'package:tafcm/presentation/theme/app_typography.dart';
import 'package:tafcm/presentation/widgets/formula_renderer.dart';

/// T1-3 FormulaRenderer 降级链路测试（Phase 3.5.1 / TEST_GAP_PLAN Tier 1）。
///
/// 降级链（widget 测试无 WebView，SVG 服务必然未就绪）：
/// - 块级：MathJax SVG（不可用）→ flutter_math_fork → **语法错误提示**
/// - 行内：flutter_math_fork → **语法错误提示**
///
/// issue #358 遗留项：解析失败不再静默回退难辨的源码——块级显示「公式语法错误」
/// 标签 + 错误色 mono 源码，行内显示错误色 italic 源码 + Tooltip。错误色取
/// `Theme.of(context).colorScheme.error`（Material 语义色，随主题）。
void main() {
  /// 明确非法的 LaTeX（未闭合分组必然解析失败 → onErrorFallback）。
  const badLatex = r'\frac{1}{';

  Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('块级 SVG 未就绪 → 降级 flutter_math_fork（无 SvgPicture）',
      (tester) async {
    await tester.pumpWidget(host(
      FormulaRenderer(
        element: const FormulaElement(latex: 'E = mc^2', displayMode: true),
      ),
    ));
    await tester.pumpAndSettle();

    // WebView 未挂载：renderFormulaToSvg 抛错被吞，_svg 保持 null
    expect(find.byType(SvgPicture), findsNothing,
        reason: '测试环境无 WebView，不应出现 SVG 渲染结果');
    expect(find.byType(Math), findsOneWidget,
        reason: '应降级 flutter_math_fork 真实渲染');
  });

  testWidgets('块级非法 LaTeX → 「公式语法错误」标签 + 错误色 mono 源码',
      (tester) async {
    await tester.pumpWidget(host(
      FormulaRenderer(
        element: const FormulaElement(latex: badLatex, displayMode: true),
      ),
    ));
    await tester.pumpAndSettle();

    // issue #358 遗留项：可理解的错误提示而非静默源码。
    expect(find.text('公式语法错误'), findsOneWidget,
        reason: '非法 LaTeX 应显示可理解的语法错误提示，不再静默');

    final src = find.text(r'$$\frac{1}{$$');
    expect(src, findsOneWidget,
        reason: r'块级错误态应展示 $$...$$ 定界源码（含定界符便于定位）');
    final text = tester.widget<Text>(src);
    expect(text.style?.fontFamily, AppTypography.mono,
        reason: '错误态源码用 mono 字体（与正常 serif 渲染区分）');
    expect(text.style?.color, AppTheme.lightTheme.colorScheme.error,
        reason: '错误态颜色应为该主题 colorScheme.error（ADR-0017 语义取色）');
  });

  testWidgets('行内非法 LaTeX → 错误色 \$源码\$ + Tooltip 说明', (tester) async {
    await tester.pumpWidget(host(
      FormulaRenderer(
        element: const FormulaElement(latex: badLatex),
      ),
    ));
    await tester.pumpAndSettle();

    final fallback = find.text(r'$\frac{1}{$');
    expect(fallback, findsOneWidget,
        reason: '行内非法 LaTeX 应回退为 \$...\$ 源码');
    final text = tester.widget<Text>(fallback);
    expect(text.style?.fontFamily, AppTypography.serif);
    expect(text.style?.fontStyle, FontStyle.italic);
    expect(text.style?.color, AppTheme.lightTheme.colorScheme.error,
        reason: '行内错误态源码应为错误色（与正常 textPrimary 渲染区分）');

    // Tooltip 承载错误说明（行内紧凑场景不放标签）。
    expect(
      tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .contains('公式语法错误'),
      isTrue,
      reason: '行内错误态应以 Tooltip 说明错误原因',
    );
  });

  testWidgets('三主题下块级错误提示颜色 = 各自 colorScheme.error',
      (tester) async {
    final cases = <(ThemeData, String)>[
      (AppTheme.lightTheme, 'light'),
      (AppTheme.darkTheme, 'dark'),
      (AppTheme.sepiaTheme, 'sepia'),
    ];
    for (final (theme, name) in cases) {
      await tester.pumpWidget(host(
        FormulaRenderer(
          element: const FormulaElement(latex: badLatex, displayMode: true),
        ),
        theme: theme,
      ));
      await tester.pumpAndSettle();

      expect(find.text('公式语法错误'), findsOneWidget,
          reason: '$name 主题也应显示语法错误提示');
      final text = tester.widget<Text>(find.text(r'$$\frac{1}{$$'));
      expect(text.style?.color, theme.colorScheme.error,
          reason: '$name 主题错误色应为该主题 colorScheme.error');
    }
  });
}
