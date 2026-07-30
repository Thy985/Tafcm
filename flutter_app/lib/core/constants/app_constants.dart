import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ===== Brand & semantic —— design-system/tokens.json =====
  static const primary = Color(0xFF1E3A5F);
  static const success = Color(0xFF2D6A4F);

  static const lightBg = Color(0xFFFAFAF7);
  static const darkBg = Color(0xFF0F1419);
  static const darkSurface = Color(0xFF1A1D23);

  static const lightText = Color(0xFF1A1D23);
  static const darkText = Color(0xFFE8EAED);
  static const lightTextSecondary = Color(0xFF6B7280);
  static const darkTextSecondary = Color(0xFF9AA0A6);

  static const codeBlockBg = Color(0xFFF0EFEA);
  static const darkCodeBlockBg = Color(0xFF13171D);

  static const blockquoteBorder = primary;
  static const blockquoteBg = Color(0xFFF0EFEA);
  static const darkBlockquoteBg = Color(0xFF13171D);

  static const tableBorder = Color(0xFFE5E4DF);
  static const darkTableBorder = Color(0xFF2A2F38);
  static const tableHeaderBg = Color(0xFFF0EFEA);
  static const darkTableHeaderBg = Color(0xFF1A1D23);

  static const formulaInlineBg = Color(0xFFEBF0F5);
  static const darkFormulaInlineBg = Color(0xFF1E2A36);

  static const error = Color(0xFFC1121F);
  static const warning = Color(0xFFE9C46A);

  static const wordAccent = Color(0xFFE76F51);
}

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const double pageMargin = 16;
  static const double cardPadding = 16;
  static const double cardRadius = 12;
  static const double codeRadius = 8;

  static const double heading1 = 28;
  static const double heading2 = 24;
  static const double heading3 = 20;
  static const double heading4 = 18;
  static const double body = 16;
  static const double code = 14;
  static const double small = 13;
  static const double caption = 11;

  static const double formulaInline = 16;
  static const double formulaDisplay = 20;
}

/// 阴影令牌 —— design-system/tokens.json `shadow` 节（P0-1，UI_FIX_PLAN）。
///
/// light / dark 两套 sm/md/lg/xl 四档：亮色用低 alpha 的墨色投影
/// rgba(26,29,35,0.04~0.14)，暗色用高 alpha 纯黑投影 rgba(0,0,0,0.3~0.6)
/// （暗背景下低 alpha 阴影不可见，这是原 `card()` 明暗同值的缺陷）。
///
/// 消费方式：
/// - 已持有 isDark 标记：`(isDark ? AppShadows.dark : AppShadows.light).md`
/// - 只有 context：`AppShadows.of(context).md`
/// - 向上投影（底部栏）：`AppShadows.flipY(AppShadows.of(context).md)`
class AppShadows {
  AppShadows._();

  /// 亮色阴影基色 rgb(26,29,35) —— tokens.json `shadow.sm~xl`。
  static const Color _lightBase = Color(0xFF1A1D23);

  /// 暗色阴影基色纯黑 —— tokens.json `shadow.dark.sm~xl`。
  static const Color _darkBase = Color(0xFF000000);

  static final AppShadowSet light = AppShadowSet._(
    sm: _tier(_lightBase, 0.04, 1, 2),
    md: _tier(_lightBase, 0.06, 4, 12),
    lg: _tier(_lightBase, 0.10, 12, 40),
    xl: _tier(_lightBase, 0.14, 24, 60),
  );

  static final AppShadowSet dark = AppShadowSet._(
    sm: _tier(_darkBase, 0.3, 1, 2),
    md: _tier(_darkBase, 0.4, 4, 12),
    lg: _tier(_darkBase, 0.5, 12, 40),
    xl: _tier(_darkBase, 0.6, 24, 60),
  );

  /// 按当前主题亮度取对应套。
  static AppShadowSet of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// 反转投影垂直方向（底部栏等向上投影的场景）。
  static List<BoxShadow> flipY(List<BoxShadow> shadows) => shadows
      .map(
        (s) => BoxShadow(
          color: s.color,
          offset: Offset(s.offset.dx, -s.offset.dy),
          blurRadius: s.blurRadius,
          spreadRadius: s.spreadRadius,
        ),
      )
      .toList();

  static List<BoxShadow> _tier(
    Color base,
    double alpha,
    double y,
    double blur,
  ) => [
    BoxShadow(
      color: base.withValues(alpha: alpha),
      offset: Offset(0, y),
      blurRadius: blur,
    ),
  ];
}

/// 一套四档阴影（sm/md/lg/xl），经 [AppShadows.light] / [AppShadows.dark] 获取。
class AppShadowSet {
  const AppShadowSet._({
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
  });

  final List<BoxShadow> sm;
  final List<BoxShadow> md;
  final List<BoxShadow> lg;
  final List<BoxShadow> xl;
}