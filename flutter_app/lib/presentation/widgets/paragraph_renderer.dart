import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:path/path.dart' as p;
import '../../core/constants/app_constants.dart';
import '../../core/parser/formula_extractor.dart';
import '../../data/models/document.dart';

class ParagraphRenderer extends StatelessWidget {
  final List<InlineElement> children;
  final bool isDark;

  /// 文档存储基目录（ADR-0014）。非空时，相对资源路径（如 `assets/img_xxx.png`）
  /// 解析为绝对路径并以 [Image.file] 渲染；网络地址仍用 [Image.network]。
  /// 为 null 时本地图片回退为占位文本（老行为）。
  final String? baseDir;

  const ParagraphRenderer({
    super.key,
    required this.children,
    required this.isDark,
    this.baseDir,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;
    final spans = <InlineSpan>[];

    for (final child in children) {
      spans.addAll(_renderInline(child, textColor));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text.rich(
        TextSpan(children: spans),
        softWrap: true,
      ),
    );
  }

  /// 把单个 inline 元素渲染为 [InlineSpan]，内层递归以支持嵌套样式。
  List<InlineSpan> _renderInline(InlineElement child, Color textColor) {
    if (child is TextElement) {
      return [
        TextSpan(
          text: child.text,
          style: TextStyle(
            fontSize: AppSpacing.body,
            height: 1.6,
            color: textColor,
          ),
        ),
      ];
    } else if (child is FormulaElement) {
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _buildFormula(child.latex, child.displayMode),
        ),
      ];
    } else if (child is BoldElement) {
      return [
        TextSpan(
          children: child.children.expand((c) => _renderInline(c, textColor)).toList(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ];
    } else if (child is ItalicElement) {
      return [
        TextSpan(
          children: child.children.expand((c) => _renderInline(c, textColor)).toList(),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      ];
    } else if (child is StrikethroughElement) {
      return [
        TextSpan(
          children: child.children.expand((c) => _renderInline(c, textColor)).toList(),
          style: const TextStyle(decoration: TextDecoration.lineThrough),
        ),
      ];
    } else if (child is InlineCodeElement) {
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCodeBlockBg : AppColors.codeBlockBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              child.code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
        ),
      ];
    } else if (child is LinkElement) {
      return [
        TextSpan(
          text: child.text,
          style: const TextStyle(
            color: AppColors.primary,
            decoration: TextDecoration.underline,
            fontSize: AppSpacing.body,
            height: 1.6,
          ),
        ),
      ];
    } else if (child is ImageElement) {
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _buildImage(child.url, child.alt),
        ),
      ];
    }
    return [];
  }

  /// 渲染行内图片：网络地址用 [Image.network]；本地相对路径（[baseDir] 非空时）
  /// 解析为绝对路径用 [Image.file] 渲染（ADR-0014 资源副本）；其余回退为 alt 文本。
  Widget _buildImage(String url, String alt) {
    final placeholder = Text(
      alt.isNotEmpty ? alt : '[图片]',
      style: TextStyle(
        color: isDark ? Colors.grey[400] : Colors.grey[600],
        fontSize: AppSpacing.small,
      ),
    );
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        height: 120,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : placeholder,
      );
    }
    // 本地相对路径：assets/img_xxx.png → <baseDir>/assets/img_xxx.png
    if (baseDir != null && !url.startsWith('data:')) {
      final file = File(p.join(baseDir!, url));
      if (file.existsSync()) {
        return Image.file(
          file,
          height: 120,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => placeholder,
        );
      }
    }
    return placeholder;
  }

  Widget _buildFormula(String latex, bool displayMode) {
    final normalized = FormulaExtractor.normalizeLatex(latex);

    if (displayMode) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Math.tex(
          normalized,
          mathStyle: MathStyle.display,
          textStyle: const TextStyle(fontSize: AppSpacing.formulaDisplay),
          onErrorFallback: _fallback(latex),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkFormulaInlineBg : AppColors.formulaInlineBg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Math.tex(
        normalized,
        mathStyle: MathStyle.text,
        textStyle: const TextStyle(fontSize: AppSpacing.formulaInline),
        onErrorFallback: _fallback(latex),
      ),
    );
  }

  Widget Function(FlutterMathException) _fallback(String latex) {
    return (_) => Text(
      '\$$latex\$',
      style: const TextStyle(
        color: AppColors.error,
        fontFamily: 'monospace',
        fontSize: 12,
      ),
    );
  }
}
