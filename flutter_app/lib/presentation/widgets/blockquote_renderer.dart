import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/document.dart';
import 'paragraph_renderer.dart';

class BlockquoteRenderer extends StatelessWidget {
  /// PR-2：引用内容已是 Inline AST，直接渲染（加粗/公式正常呈现）。
  final List<InlineElement> children;
  final bool isDark;

  const BlockquoteRenderer({
    super.key,
    required this.children,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: const Border(
          left: BorderSide(color: AppColors.blockquoteBorder, width: 4),
        ),
        color: isDark ? AppColors.darkBlockquoteBg : AppColors.blockquoteBg,
      ),
      child: ParagraphRenderer(children: children, isDark: isDark),
    );
  }
}