import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';
import 'package:formula_fix/presentation/theme/app_typography.dart';
import 'package:formula_fix/presentation/themes/editor_tokens.dart';
import 'package:formula_fix/presentation/widgets/formula_renderer.dart';

/// T1-3 FormulaRenderer 降级链路测试（Phase 3.5.1 / TEST_GAP_PLAN Tier 1）。
///
/// 降级链（widget 测试无 WebView，SVG 服务必然未就绪）：
/// - 块级：MathJax SVG（不可用）→ flutter_math_fork → serif italic 源码
/// - 行内：flutter_math_fork → serif italic `$...$` 源码
/// 颜色断言按三主题各自的 [EditorTokens.textPrimary]。
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

  testWidgets('块级非法 LaTeX → 二次降级 serif italic 源码（AppTypography.formula）',
      (tester) async {
    await tester.pumpWidget(host(
      FormulaRenderer(
        element: const FormulaElement(latex: badLatex, displayMode: true),
      ),
    ));
    await tester.pumpAndSettle();

    // onErrorFallback → Text(widget.element.latex)，样式 AppTypography.formula
    final fallback = find.text(badLatex);
    expect(fallback, findsOneWidget,
        reason: '非法 LaTeX 应回退为源码文本');
    final text = tester.widget<Text>(fallback);
    expect(text.style?.fontFamily, AppTypography.serif,
        reason: '降级样式须来自 AppTypography.formula（serif）');
    expect(text.style?.fontStyle, FontStyle.italic,
        reason: '降级样式须为 italic（ui-spec §7）');
    expect(text.style?.color, EditorTokens.light.textPrimary,
        reason: '降级色须经 EditorTokens 取色（ADR-0017）');
  });

  testWidgets('行内非法 LaTeX → 降级 serif italic \$源码\$', (tester) async {
    await tester.pumpWidget(host(
      FormulaRenderer(
        element: const FormulaElement(latex: badLatex),
      ),
    ));
    await tester.pumpAndSettle();

    final fallback = find.text('\$$badLatex\$');
    expect(fallback, findsOneWidget,
        reason: '行内非法 LaTeX 应回退为 \$...\$ 源码');
    final text = tester.widget<Text>(fallback);
    expect(text.style?.fontFamily, AppTypography.serif);
    expect(text.style?.fontStyle, FontStyle.italic);
    expect(text.style?.color, EditorTokens.light.textPrimary);
  });

  testWidgets('三主题下块级降级文本颜色 = 各自 EditorTokens.textPrimary',
      (tester) async {
    final cases = <(ThemeData, EditorTokens, String)>[
      (AppTheme.lightTheme, EditorTokens.light, 'light'),
      (AppTheme.darkTheme, EditorTokens.dark, 'dark'),
      (AppTheme.sepiaTheme, EditorTokens.sepia, 'sepia'),
    ];
    for (final (theme, tokens, name) in cases) {
      await tester.pumpWidget(host(
        FormulaRenderer(
          element: const FormulaElement(latex: badLatex, displayMode: true),
        ),
        theme: theme,
      ));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text(badLatex));
      expect(text.style?.color, tokens.textPrimary,
          reason: '$name 主题降级色应为该主题 textPrimary');
    }
  });
}
