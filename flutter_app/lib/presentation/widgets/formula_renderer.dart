/// FormulaRenderer：公式统一渲染 Widget（Phase 3.5.1 Formula Rendering System）。
///
/// 收敛此前两条分叉路径：
/// - 编辑器块级公式（[FormulaBlock] → [FormulaSvgService] MathJax SVG）
/// - 预览行内/块级公式（[ParagraphRenderer]/[ListRenderer] → `flutter_math_fork`，行内还多一张卡片）
/// 统一为单一 Widget，供编辑器与预览共用。
///
/// 视觉规范（ui-spec.md §3.1/§7）：行内/块级均 **serif italic、无卡片背景**（Typora 化）。
/// 颜色经 [EditorTokens.of] 取色（[ADR-0017]），不硬编码。
///
/// 渲染内核策略（性能 / 保真权衡，经评审）：
/// - 块级 (`displayMode`)：优先 [FormulaSvgService] MathJax SVG（与 Mermaid 共享 WebView，
///   保真且可经 `currentColor` 着色随主题）；WebView 未挂载 / 渲染失败降级 `flutter_math_fork`。
/// - 行内：优先 `flutter_math_fork`（纯 Dart、轻量、不占 WebView 并发）；解析失败降级 serif 源码。
///
/// 块级公式支持可选 [number]（右对齐 serif italic，如 `(1)`）。自动顺序编号需文档模型支持，
/// 留作后续（见 ROADMAP 3.5.1 说明）。
///
/// **AST 决策（FormulaElement AST 评审结论）**：保持 [FormulaElement] 作为 inline 元素 +
/// `displayMode` 标志，不新增独立 BlockType（避免触动 BlockRenderer exhaustive switch 守门）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../providers/formula_svg_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/parser/formula_extractor.dart';
import '../../../data/models/document.dart';
import '../theme/app_typography.dart';
import '../themes/editor_tokens.dart';

/// 公式统一渲染 Widget（编辑器 + 预览共用）。
///
/// [element] 为公式 AST；[displayMode] 显式覆盖（构造默认取自 [element.displayMode]）。
class FormulaRenderer extends StatefulWidget {
  final FormulaElement element;

  /// 显式覆盖 [FormulaElement.displayMode]（保持与既有调用点兼容）。
  final bool displayMode;

  /// 块级公式编号（可选，右对齐 serif italic）。`null` 不显示编号。
  final int? number;

  /// 块级 SVG 渲染成功时是否额外显示 mono 源码行（与高保真 prototype 一致）。
  final bool showSource;

  FormulaRenderer({
    super.key,
    required this.element,
    bool? displayMode,
    this.number,
    this.showSource = true,
  }) : displayMode = displayMode ?? element.displayMode;

  @override
  State<FormulaRenderer> createState() => _FormulaRendererState();
}

class _FormulaRendererState extends State<FormulaRenderer> {
  String? _svg;

  @override
  void initState() {
    super.initState();
    if (widget.displayMode) _load();
  }

  @override
  void didUpdateWidget(covariant FormulaRenderer oldWidget) {
    if (oldWidget.element.latex != widget.element.latex ||
        oldWidget.displayMode != widget.displayMode) {
      _svg = null;
      if (widget.displayMode) _load();
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
    // 异步渲染；WebView 未挂载 / 渲染失败 → catchError 不抛，build 走 flutter_math_fork 降级
    renderFormulaToSvg(latex, displayMode: true)
        .then((svg) {
          if (mounted) setState(() => _svg = svg);
        })
        .catchError((_) {
          // WebView 未就绪 / 渲染失败：_svg 保持 null → 降级 flutter_math_fork
        });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = EditorTokens.of(context);
    final formula = widget.displayMode
        ? _buildBlock(context, tokens)
        : _buildInline(context, tokens);
    if (widget.number == null || !widget.displayMode) return formula;
    // 块级编号：公式主体 + 右对齐编号
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: formula),
        const SizedBox(width: 12),
        Text(
          '(${widget.number})',
          style: TextStyle(
            fontFamily: AppTypography.serif,
            fontStyle: FontStyle.italic,
            fontSize: 15,
            color: tokens.textSecondary,
          ),
        ),
      ],
    );
  }

  /// 行内公式：无卡片，优先 `flutter_math_fork`，失败降级 serif italic 源码。
  Widget _buildInline(BuildContext context, EditorTokens tokens) {
    final normalized = FormulaExtractor.normalizeLatex(widget.element.latex);
    return Math.tex(
      normalized,
      mathStyle: MathStyle.text,
      textStyle: TextStyle(
        fontFamily: AppTypography.serif,
        fontStyle: FontStyle.italic,
        fontSize: AppSpacing.formulaInline,
        color: tokens.textPrimary,
      ),
      onErrorFallback: (_) => Text(
        '\$${widget.element.latex}\$',
        style: TextStyle(
          fontFamily: AppTypography.serif,
          fontStyle: FontStyle.italic,
          fontSize: AppSpacing.formulaInline,
          color: tokens.textPrimary,
        ),
      ),
    );
  }

  /// 块级公式：Typora 化（居中、无卡片）。优先 SVG，降级 flutter_math_fork。
  Widget _buildBlock(BuildContext context, EditorTokens tokens) {
    final body = _svg != null
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SvgPicture.string(
              _svg!,
              color: tokens.textPrimary,
            ),
          )
        : _flutterMathFallback(tokens);

    return Container(
      width: double.infinity,
      // Typora：无卡片、无边框，仅垂直留白
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: body),
          if (_svg != null && widget.showSource) ...[
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

  /// 块级 SVG 未就绪 / 失败时的降级：用 `flutter_math_fork` 真实渲染（二次失败才回退 serif 源码）。
  Widget _flutterMathFallback(EditorTokens tokens) {
    final normalized = FormulaExtractor.normalizeLatex(widget.element.latex);
    return Math.tex(
      normalized,
      mathStyle: MathStyle.display,
      textStyle: TextStyle(
        fontFamily: AppTypography.serif,
        fontStyle: FontStyle.italic,
        fontSize: AppSpacing.formulaDisplay,
        color: tokens.textPrimary,
      ),
      onErrorFallback: (_) => Text(
        widget.element.latex,
        style: AppTypography.formula(color: tokens.textPrimary),
        textAlign: TextAlign.center,
      ),
    );
  }
}
