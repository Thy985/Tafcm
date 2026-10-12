/// issue #358 遗留项：FormulaInsertDialog 语法错误反馈回归测试。
///
/// 对话框在 WYSIWYG 工具栏公式入口弹出（12 预设 + 实时预览）。守门点：
/// - 合法 LaTeX → 预览渲染（Math widget），无错误提示
/// - 非法 LaTeX（未闭合分组）→ 预览显示「公式语法错误」标签 + 错误色源码，
///   让用户在插入前即可定位语法错误（不再"插入后静默不渲染"）
/// - 取消（直接关闭）→ 返回 null 不插入（由调用方处理，此处守门对话框本身）
library;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/constants/app_constants.dart';
import 'package:tafcm/presentation/widgets/formula_insert_dialog.dart';

void main() {
  Widget host(Widget dialog) => MaterialApp(home: Scaffold(body: dialog));

  testWidgets('合法 LaTeX → 预览渲染 Math widget，无错误提示', (tester) async {
    await tester.pumpWidget(host(
      const FormulaInsertDialog(displayMode: true, isDark: false),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), r'\frac{a}{b}');
    await tester.pumpAndSettle();

    expect(find.text('预览'), findsOneWidget, reason: '输入后应显示实时预览');
    expect(find.byType(Math), findsOneWidget,
        reason: '合法 LaTeX 预览应真实渲染（flutter_math_fork）');
    expect(find.text('公式语法错误'), findsNothing,
        reason: '合法 LaTeX 不应出现错误提示');
  });

  testWidgets('非法 LaTeX → 预览显示「公式语法错误」标签 + 错误色源码',
      (tester) async {
    await tester.pumpWidget(host(
      const FormulaInsertDialog(displayMode: true, isDark: false),
    ));
    await tester.pumpAndSettle();

    // 未闭合分组：Math.tex 必然解析失败 → onErrorFallback。
    await tester.enterText(find.byType(TextField), r'\frac{1}{');
    await tester.pumpAndSettle();

    expect(find.text('公式语法错误'), findsOneWidget,
        reason: '非法 LaTeX 应显示可理解的语法错误提示（issue #358 遗留项）');

    // 错误态源码（mono 样式）与输入框 EditableText 内容区分定位。
    final src = find.byWidgetPredicate((w) =>
        w is Text &&
        w.data == r'\frac{1}{' &&
        w.style?.fontFamily == 'monospace');
    expect(src, findsOneWidget, reason: '错误态应保留源码便于定位');
    final text = tester.widget<Text>(src);
    expect(text.style?.color, AppColors.error,
        reason: '错误态源码应为错误色（AppColors.error）');
    // 注意：Math widget 是宿主（其 build 返回 fallback），仍在树中——
    // 这里不断言 Math 缺席，只断言错误提示可见（fallback 内容由标签+源码体现）。
  });

  testWidgets('输入框空内容 → 提交显示「请输入公式内容」', (tester) async {
    await tester.pumpWidget(host(
      const FormulaInsertDialog(displayMode: true, isDark: false),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('插入'));
    await tester.pumpAndSettle();

    expect(find.text('请输入公式内容'), findsOneWidget,
        reason: '空输入提交应提示（既有行为守门）');
  });
}
