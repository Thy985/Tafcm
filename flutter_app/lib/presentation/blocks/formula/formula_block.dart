/// FormulaBlock：块级公式（$$...$$）的编辑器委派入口（Phase 3.5.1）。
///
/// 真实渲染内核已统一收敛到 [FormulaRenderer]：优先 [FormulaSvgService] MathJax SVG，
/// 降级 `flutter_math_fork`；Typora 化（纯 serif italic、居中、无卡片，ui-spec §3.1/§7）。
///
/// 本 Widget 仅作为编辑器 [ParagraphBlock] 的委派入口；聚焦边框由 [ParagraphBlock] 外层
/// Container 绘制，故本 Widget 自身不持有 focus 状态。
library;

import 'package:flutter/material.dart';

import '../../../data/models/document.dart';
import '../../widgets/formula_renderer.dart';

/// 块级公式渲染 Widget（presentational）。
class FormulaBlock extends StatelessWidget {
  /// 当前块的公式 AST 数据（[FormulaElement]，应为 `displayMode=true`）。
  final FormulaElement element;

  const FormulaBlock({
    super.key,
    required this.element,
  });

  @override
  Widget build(BuildContext context) =>
      FormulaRenderer(element: element, displayMode: element.displayMode);
}
