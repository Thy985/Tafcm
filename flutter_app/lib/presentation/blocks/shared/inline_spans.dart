/// 行内元素 → TextSpan 构建（Paragraph / List / Task 等块共用）。
///
/// 从 paragraph_block.dart 提取（2026-08-29，P0-1 UI/UX 修复：列表 / 任务块复用
/// 同一套行内富文本渲染，避免复制私有实现）。
library;

import 'package:flutter/material.dart';

import '../../../core/utils/asset_image_resolver.dart';
import '../../../data/models/document.dart';
import '../../themes/editor_tokens.dart';
import '../../widgets/formula_renderer.dart';

/// 把 [InlineElement] 列表渲染为 [TextSpan]。
///
/// 支持 bold / italic / strikethrough / code / formula（WidgetSpan 真实渲染）/
/// link / image（本地文件或占位文本）。逻辑与段落块 render 态完全一致。
InlineSpan buildInlineSpans(
  List<InlineElement> children,
  TextStyle baseStyle,
  BuildContext context, {
  String? baseDir,
}) {
  return TextSpan(
    style: baseStyle,
    children: children
        .map((e) => _buildInlineSpan(e, baseStyle, context, baseDir))
        .toList(),
  );
}

InlineSpan _buildInlineSpan(
  InlineElement element,
  TextStyle baseStyle,
  BuildContext context,
  String? baseDir,
) {
  return switch (element) {
    TextElement(:final text) => TextSpan(text: text, style: baseStyle),
    BoldElement(:final children) => TextSpan(
        style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        children: children
            .map((e) => _buildInlineSpan(e, baseStyle, context, baseDir))
            .toList(),
      ),
    ItalicElement(:final children) => TextSpan(
        style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        children: children
            .map((e) => _buildInlineSpan(e, baseStyle, context, baseDir))
            .toList(),
      ),
    StrikethroughElement(:final children) => TextSpan(
        style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
        children: children
            .map((e) => _buildInlineSpan(e, baseStyle, context, baseDir))
            .toList(),
      ),
    InlineCodeElement(:final code) => TextSpan(
        text: code,
        style: baseStyle.copyWith(
          fontFamily: 'monospace',
          backgroundColor: Colors.grey.shade200,
        ),
      ),
    // 公式（行内 / 块级）Typora 化：纯 serif italic，无卡片（ui-spec.md §3.1/§7）。
    FormulaElement(:final latex, :final displayMode) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: FormulaRenderer(
          element: FormulaElement(latex: latex, displayMode: displayMode),
          displayMode: displayMode,
        ),
      ),
    LinkElement(:final text) => TextSpan(
        text: text,
        style: baseStyle.copyWith(
          color: EditorTokens.linkColor,
          decoration: TextDecoration.underline,
        ),
      ),
    ImageElement(:final alt, :final url) =>
      _buildImageInline(url, alt, baseStyle, context, baseDir),
  };
}

/// 渲染 [ImageElement] 为 [InlineSpan]。
///
/// 本地相对路径（[baseDir] 非空且文件存在）→ [WidgetSpan] + [Image.file]；
/// 否则回退占位文本（网络地址 / data uri / 缺基目录 / 文件缺失）。
InlineSpan _buildImageInline(
  String url,
  String alt,
  TextStyle baseStyle,
  BuildContext context,
  String? baseDir,
) {
  final placeholder = TextSpan(
    text: alt.isNotEmpty ? '[图片: $alt]' : '[图片]',
    style: baseStyle.copyWith(
      color: EditorTokens.of(context).textSecondary,
      fontStyle: FontStyle.italic,
    ),
  );
  // TC-ARCH-1：presentation 不直接 File()，经 core/utils 解析。
  final file = resolveLocalImageFile(baseDir, url);
  if (file == null) return placeholder;
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Image.file(
      file,
      height: 120,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Text(alt.isNotEmpty ? alt : '[图片]'),
    ),
  );
}
