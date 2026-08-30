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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/services/formula_svg_service.dart';
import '../../../providers/formula_svg_provider.dart';
import '../../../core/constants/app_constants.dart' show AppSpacing;
import '../../../core/parser/formula_extractor.dart';
import '../../../data/models/document.dart';
import '../theme/app_typography.dart';
import '../themes/editor_tokens.dart';

/// 块级公式容器垂直留白。
/// 10 介于 [AppSpacing.sm](8) 与 [AppSpacing.md](12) 之间，无对应 token，
/// 故提取为命名常量；水平留白直接用 [AppSpacing.xs]（== 4）。
const double _formulaBlockVerticalPadding = 10.0;

/// 公式渲染终态结果（PR-1：terminal-state invariant）。
///
/// 任何渲染操作结束后，结果必须归入以下一种**非空白终态**；不允许
/// "null forever"（Bug5 空白窗口根因）。`build` 依据此结果选择展示
/// 路径：仅 [FormulaRenderSuccess] 显示 SVG，其余一律走 flutter_math_fork
/// 降级（[FormulaRenderer] 的 FormulaFallbackPolicy）。
sealed class FormulaRenderResult {
  const FormulaRenderResult();
}

/// SVG 渲染成功，且 [svg] 已通过有效性校验（非空、含实际渲染元素）。
class FormulaRenderSuccess extends FormulaRenderResult {
  const FormulaRenderSuccess(this.svg);

  final String svg;
}

/// 渲染超时（WebView/MathJax 未在 [_renderTimeout] 内返回）。
class FormulaRenderTimeout extends FormulaRenderResult {
  const FormulaRenderTimeout();
}

/// 返回了 SVG 字符串但内容非法 / 空白（仅 xmlns 头、无 path/text/g 等
/// 实际渲染元素）——`svg.isEmpty` 检查无法拦截的场景（Bug5 空白终态之一）。
class FormulaRenderInvalidSvg extends FormulaRenderResult {
  const FormulaRenderInvalidSvg();
}

/// WebView 通信错误（宿主未挂载 / 重置 / evaluateJavascript 失败等）。
class FormulaRenderWebViewError extends FormulaRenderResult {
  const FormulaRenderWebViewError();
}

/// 其它不可用情况（未分类异常 / 服务未就绪）。
class FormulaRenderUnavailable extends FormulaRenderResult {
  const FormulaRenderUnavailable();
}

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
  /// 渲染终态结果（PR-1）。初始 [FormulaRenderUnavailable]：build 走降级，
  /// **任何时刻都不会呈现空白**（terminal-state invariant）。
  FormulaRenderResult _result = const FormulaRenderUnavailable();

  /// 请求序列号：丢弃过期异步结果，避免快速连续改公式时的竞态覆盖（review #1）。
  int _loadToken = 0;

  /// P0-3：终态结果缓存（成功 + 失败都缓存）。
  ///
  /// 双态切换（rendered↔editing）时 [FormulaBlock] 整体移出/移回 widget 树，
  /// State 销毁重建会重新走 `initState → _load()`；若只靠 SVG 字符串缓存，
  /// 失败终态（timeout / invalidSvg）无法复用，切回时重新排队异步渲染
  /// （Bug5「再点变空白」的最大放大器）。此缓存按 (latex, displayMode) 保存
  /// 最终 [FormulaRenderResult]，重建时同步复用——成功即展示、失败即降级，
  /// 均不重新触发 WebView 渲染。
  static final Map<String, FormulaRenderResult> _resultCache = {};
  static const int _maxResultCacheEntries = 512;
  static String _resultCacheKey(String latex, bool displayMode) =>
      '${displayMode ? 'B' : 'I'}|$latex';

  static FormulaRenderResult? _resultCacheGet(String latex, bool displayMode) {
    final key = _resultCacheKey(latex, displayMode);
    final hit = _resultCache.remove(key);
    if (hit != null) {
      _resultCache[key] = hit; // LRU 触达
      return hit;
    }
    return null;
  }

  static void _resultCachePut(String latex, bool displayMode, FormulaRenderResult r) {
    final key = _resultCacheKey(latex, displayMode);
    _resultCache[key] = r;
    while (_resultCache.length > _maxResultCacheEntries) {
      final firstKey = _resultCache.keys.first;
      _resultCache.remove(firstKey);
    }
  }

  /// P0-5：fallback 决策 telemetry（最近 256 条）。
  ///
  /// 记录每次降级的原因分类（timeout / invalidSvg / webViewError /
  /// unavailable / cacheMiss）与 latex 长度、displayMode；不记 latex 原文
  /// （敏感内容最小化）。与 FormulaSvgService.telemetryEntries 互补：
  /// 服务层量化耗时瓶颈，本层量化 fallback 分布。
  static final Map<String, int> fallbackReasonCounts = {};
  static const int _maxFallbackReasons = 64;

  static void _recordFallback(String reason, int latexLength, bool displayMode) {
    fallbackReasonCounts[reason] = (fallbackReasonCounts[reason] ?? 0) + 1;
    if (fallbackReasonCounts.length > _maxFallbackReasons) {
      // 极端防御：只保留最多的 32 个原因分类（理论上不会触发）
      final sorted = fallbackReasonCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      fallbackReasonCounts
        ..clear()
        ..addEntries(sorted.take(32));
    }
    debugPrint(
      '[FormulaRenderer] fallback reason=$reason '
      '(len=$latexLength, display=$displayMode)',
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.displayMode) _load();
  }

  @override
  void didUpdateWidget(covariant FormulaRenderer oldWidget) {
    if (oldWidget.element.latex != widget.element.latex ||
        oldWidget.displayMode != widget.displayMode) {
      // 公式变化：立即回到不可用终态（build 走降级），重新异步加载。
      _result = const FormulaRenderUnavailable();
      if (widget.displayMode) _load();
    }
    super.didUpdateWidget(oldWidget);
  }

  void _load() {
    final token = ++_loadToken;
    final latex = widget.element.latex;
    final displayMode = widget.displayMode;
    // P0-3：优先复用终态缓存（成功展示 / 失败降级，不重新渲染）。
    final cachedResult = _resultCacheGet(latex, displayMode);
    if (cachedResult != null) {
      if (mounted) setState(() => _result = cachedResult);
      return;
    }
    // 同步命中 SVG 缓存直接展示，避免一帧的源码闪烁
    final cached = formulaSvgCached(latex, displayMode: displayMode);
    if (cached != null) {
      if (mounted) setState(() => _result = _validateResult(cached));
      return;
    }
    // 异步渲染；结果统一归入非空白终态：
    // - 成功 → _validateResult 校验 SVG 有效性（拦截空/畸形 SVG）
    // - 失败/超时 → _classifyError 分类（timeout / webViewError / unavailable）
    // token 校验：若期间 didUpdateWidget 触发了更新的 _load()（token 已自增），
    // 旧请求的回调会被丢弃，避免用旧公式 SVG 覆盖新公式内容（review #1）。
    // P0-5 前置：诊断埋点，记录每个公式的渲染结果分类，供 scheduler 优化
    // 收集数据（latex 长度 + 结果类型；不记原文，避免敏感内容外泄）。
    renderFormulaToSvg(latex, displayMode: displayMode)
        .then((svg) {
          if (mounted && token == _loadToken) {
            final result = _validateResult(svg);
            if (result is FormulaRenderInvalidSvg) {
              _recordFallback('invalidSvg', latex.length, displayMode);
            }
            _resultCachePut(latex, displayMode, result);
            setState(() => _result = result);
          }
        })
        .catchError((Object e) {
          // WebView 未就绪 / 渲染失败 / 超时：分类为明确失败终态，
          // build 据此走 flutter_math_fork 降级（绝不呈现空白）。
          if (mounted && token == _loadToken) {
            final result = _classifyError(e);
            _recordFallback(
              result.runtimeType.toString(),
              latex.length,
              displayMode,
            );
            _resultCachePut(latex, displayMode, result);
            setState(() => _result = result);
          }
        });
  }

  /// 校验 SVG 是否为可渲染终态：非空且含实际渲染元素（path/text/g 等）。
  ///
  /// 拦截"仅 xmlns 头的空 SVG"（`svg.isEmpty` 检查无法覆盖，Bug5 空白终态
  /// 之一）：MathJax 可能输出合法字符串但无任何可绘制内容。
  FormulaRenderResult _validateResult(String svg) {
    if (!_isValidSvg(svg)) return const FormulaRenderInvalidSvg();
    return FormulaRenderSuccess(svg);
  }

  /// 把异步渲染异常分类为明确的失败终态（FormulaFallbackPolicy 输入）。
  FormulaRenderResult _classifyError(Object error) {
    if (error is TimeoutException) return const FormulaRenderTimeout();
    if (error is FormulaSvgException) return const FormulaRenderWebViewError();
    return const FormulaRenderUnavailable();
  }

  /// SVG 有效性校验：非空 + 包含实际图形元素。
  static bool _isValidSvg(String svg) {
    if (svg.trim().isEmpty) return false;
    // MathJax SVG 至少包含 <path>（字形轮廓）或 <text>/<g>（组合内容）
    return svg.contains('<path') ||
        svg.contains('<text') ||
        svg.contains('<g ') ||
        svg.contains('<rect') ||
        svg.contains('<circle');
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
  ///
  /// **PR-1 FormulaFallbackPolicy**：仅 [FormulaRenderSuccess] 显示 SVG；
  /// 其余终态（timeout / invalidSvg / webViewError / unavailable）统一走
  /// `flutter_math_fork` 降级——**build 永不呈现空白**（terminal-state invariant）。
  Widget _buildBlock(BuildContext context, EditorTokens tokens) {
    final body = switch (_result) {
      FormulaRenderSuccess(:final svg) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SvgPicture.string(
            svg,
            color: tokens.textPrimary,
          ),
        ),
      _ => _flutterMathFallback(tokens),
    };

    return Container(
      width: double.infinity,
      // Typora：无卡片、无边框、无圆角（焦点圆角由 ParagraphBlock 统一绘制，避免重复；review #5）。
      padding: const EdgeInsets.symmetric(
        vertical: _formulaBlockVerticalPadding,
        horizontal: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: body),
          if (_result is FormulaRenderSuccess && widget.showSource) ...[
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
