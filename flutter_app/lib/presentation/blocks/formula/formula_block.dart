/// FormulaBlock：块级公式（$$...$$）的 Typora 化渲染。
///
/// 视觉规范（[ui-spec.md §3.1 / §7] + [formulafix-redesign.design] formula-sheet.html）：
/// - Typora 化：**纯 serif italic，无卡片背景 / 边框**。"公式块严格还原"以 ui-spec 工程权威裁定
///   为准，NOT `tokens.json.component.formulaBlock` 的渐变卡片（该卡片规格与 ui-spec 冲突，
///   已在 ROADMAP 3.4.5.4 / tokens.json 中修订对齐）。
/// - 居中显示（文档公式场景）。
/// - 真实渲染：优先经 [FormulaSvgService] 渲染 MathJax SVG（WebView 就绪时）；
///   WebView 未就绪 / 渲染失败则**降级为 serif italic 源码**（Typora 观感不丢失，不崩溃）。
/// - 真实渲染成功时，下方显示 mono 源码行（与高保真 prototype 一致）；降级态不重复显示。
///
/// **颜色守门（ADR-0017）**：不硬编码 `Color(0x..)`，全部经 [EditorTokens.of] 取色；
/// 公式字族 / 字重由 [AppTypography.formula] 提供（serif + italic）。
///
/// **AST 来源**：[FormulaElement]（inline 层，`displayMode=true` 标记块级）。块级公式在编辑器中
/// 表示为「仅含一个 `displayMode=true` FormulaElement 的 [ParagraphElement]」，由 [ParagraphBlock]
/// 在 render 态委派本 Widget 渲染——不新增 [BlockRenderer] case，保持 exhaustive switch 守门，
/// 符合 Phase 3.5 前不提前做 AST 手术的策略（真实 LaTeX 渲染内核留 Phase 3.5）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../providers/formula_svg_provider.dart';
import '../../../data/models/document.dart';
import '../../theme/app_typography.dart';
import '../../themes/editor_tokens.dart';

/// 块级公式渲染 Widget（presentational，Stateful 仅用于异步 SVG 加载）。
///
/// 不继承 [BaseBlockState]：双态编辑由委派方 [ParagraphBlock] 统一处理（edit 态回退到
/// 段落 TextField 显示 `$$...$$` 源码），本 Widget 只负责 render 态的 Typora 公式外观。
class FormulaBlock extends StatefulWidget {
  /// 当前块的公式 AST 数据（[FormulaElement]，应为 `displayMode=true`）。
  final FormulaElement element;

  /// 是否处于聚焦态（edit 态由外层容器绘制聚焦边框，本 Widget 仅透传用于潜在高亮）。
  final bool isFocused;

  const FormulaBlock({
    super.key,
    required this.element,
    this.isFocused = false,
  });

  @override
  State<FormulaBlock> createState() => _FormulaBlockState();
}

class _FormulaBlockState extends State<FormulaBlock> {
  String? _svg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FormulaBlock oldWidget) {
    if (oldWidget.element.latex != widget.element.latex) {
      _svg = null;
      _load();
    }
    super.didUpdateWidget(oldWidget);
  }

  void _load() {
    final latex = widget.element.latex;
    // 同步命中缓存直接展示，避免一帧的源码闪烁
    final cached = formulaSvgCached(latex, displayMode: true);
    if (cached != null) {
      setState(() => _svg = cached);
      return;
    }
    // 异步渲染；WebView 未就绪 / 失败则降级为 serif italic 源码（catchError 不抛）
    renderFormulaToSvg(latex, displayMode: true)
        .then((svg) {
          if (mounted) setState(() => _svg = svg);
        })
        .catchError((_) {
          // WebView 未就绪 / 渲染失败：_svg 保持 null → build 走 serif italic 源码降级
        });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = EditorTokens.of(context);
    return Container(
      width: double.infinity,
      // Typora：无卡片、无边框，仅垂直留白
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _buildFormulaBody(context, tokens)),
          if (_svg != null) ...[
            const SizedBox(height: 6),
            // 真实渲染成功时显示 mono 源码行（与高保真 prototype 一致）
            Center(
              child: Text(
                '\$\$${widget.element.latex}\$\$',
                style: TextStyle(
                  fontFamily: AppTypography.mono,
                  fontSize: 11,
                  height: 1.3,
                  color: tokens.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormulaBody(BuildContext context, EditorTokens tokens) {
    if (_svg != null) {
      // 真实 MathJax SVG：横向可滚动避免宽公式溢出；srcIn 把单色数学强制为 token 色
      // （兼容 dark 主题，MathJax tex-svg 用 currentColor）
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SvgPicture.string(
          _svg!,
          color: tokens.textPrimary,
        ),
      );
    }
    // 降级（WebView 未就绪 / 渲染失败）：serif italic 源码，Typora 观感不丢失
    return Text(
      widget.element.latex,
      style: AppTypography.formula(color: tokens.textPrimary),
      textAlign: TextAlign.center,
    );
  }
}
