/// FormulaSyntaxErrorHint：公式语法错误提示（issue #358 遗留项）。
///
/// [flutter_math_fork] 解析失败（`Math.tex` 的 `onErrorFallback`）时替代静默
/// 源码，让用户能定位"公式为什么不渲染"（未闭合定界符 / 转义错误等）：
/// - 块级（[displayMode] = true）：错误色「公式语法错误」标签 + 错误色 mono
///   源码，居中显示；
/// - 行内：错误色 italic 源码 + Tooltip 说明（紧凑场景不放标签，避免破坏文本流）。
///
/// 错误色取 `Theme.of(context).colorScheme.error`（Material 语义色，随主题）。
library;

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../theme/app_typography.dart';

/// 语法错误提示文案（issue #358 遗留项：渲染失败不再静默）。
const String kFormulaSyntaxErrorLabel = '公式语法错误';

/// 公式语法错误提示 widget。
class FormulaSyntaxErrorHint extends StatelessWidget {
  const FormulaSyntaxErrorHint({
    super.key,
    required this.source,
    required this.displayMode,
  });

  /// 出错公式的源码（含 `$$` / `$` 定界符，便于定位）。
  final String source;

  /// true = 块级（标签 + 居中 mono 源码）；false = 行内（Tooltip + 错误色源码）。
  final bool displayMode;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    if (displayMode) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 14, color: errorColor),
              const SizedBox(width: 4),
              Text(
                kFormulaSyntaxErrorLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: errorColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            source,
            style: TextStyle(
              fontFamily: AppTypography.mono,
              fontSize: 12,
              height: 1.3,
              color: errorColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    // 行内：错误色 italic 源码 + Tooltip 说明。
    return Tooltip(
      message: kFormulaSyntaxErrorLabel,
      child: Text(
        source,
        style: TextStyle(
          fontFamily: AppTypography.serif,
          fontStyle: FontStyle.italic,
          fontSize: AppSpacing.formulaInline,
          color: errorColor,
        ),
      ),
    );
  }
}
