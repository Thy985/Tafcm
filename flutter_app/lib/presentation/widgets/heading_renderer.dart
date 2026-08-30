import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/document.dart';
import 'paragraph_renderer.dart';

class HeadingRenderer extends StatelessWidget {
  final int level;

  /// PR-3：标题内容已是 Inline AST，走 ParagraphRenderer 统一行内渲染
  /// （加粗/公式在预览中正常呈现）。
  final List<InlineElement> children;
  final bool isDark;

  const HeadingRenderer({
    super.key,
    required this.level,
    required this.children,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: _fontSize,
          fontWeight: FontWeight.bold,
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        child: ParagraphRenderer(children: children, isDark: isDark),
      ),
    );
  }

  double get _fontSize {
    return switch (level) {
      1 => AppSpacing.heading1,
      2 => AppSpacing.heading2,
      3 => AppSpacing.heading3,
      _ => AppSpacing.heading4,
    };
  }
}