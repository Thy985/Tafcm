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

<<<<<<< HEAD
  // ── 布局令牌（P1-2）：权威值取自 design-system/tokens.json `spacing` 节 ──
  //
  // 这些值此前在 tokens.json 有定义、在 Dart 侧却无名（散落为魔法数或尚无
  // 消费方），本节把它们收敛为命名常量，作为设计系统与代码的对齐锚点。
  // 部分令牌对应的界面（阅读模式、FAB、底部 sheet）尚未实现，暂无消费方是
  // 预期状态；新建这些界面时必须消费本节令牌，不得再写魔法数。

  /// 阅读模式左右留白 —— tokens.json `spacing.readerHorizontal`。
  static const double readerHorizontal = 28;

  /// 卡片之间的纵向间距 —— tokens.json `spacing.cardGap`。
  static const double cardGap = 12;

  /// 区块之间的纵向间距 —— tokens.json `spacing.sectionGap`。
  static const double sectionGap = 24;

  /// 悬浮按钮距屏幕底部的偏移 —— tokens.json `spacing.fabBottomOffset`。
  static const double fabBottomOffset = 88;

  /// 顶部栏高度 —— tokens.json `spacing.topBarHeight`。
  ///
  /// 注意：**不等于** Material 的 `kToolbarHeight`(56)，本产品用更紧凑的 48。
  static const double topBarHeight = 48;

  /// 底部 sheet 最大高度占屏幕的比例 —— tokens.json
  /// `spacing.bottomSheetMaxHeight`（原值 `88vh`，Flutter 侧表达为比例）。
  static const double bottomSheetMaxHeightFactor = 0.88;

  /// 输入框圆角 —— tokens.json `radius.input`。
  static const double inputRadius = 8;

=======
>>>>>>> f60831d (补 0010-SKIPPED 编号纪律占位，新增 ADR-0021 Repository Integrity Strategy v1.4)
  static const double heading1 = 28;
  static const double heading2 = 24;
  static const double heading3 = 20;
  static const double heading4 = 18;
  static const double body = 16;
  static const double code = 14;
  static const double small = 13;
<<<<<<< HEAD

  /// ⚠️ 命名历史遗留：本值 11 实为 tokens.json `typography.scale.meta`，
  /// **不是** `caption`(10)。真正的 caption 令牌见 [AppTypography.caption]。
  /// 收敛为单一来源属 P1-3 后续项（会改像素，需同步 golden 基线）。
  static const double caption = 11;

  static const double formulaInline = 16;
  /// ⚠️ 命名历史遗留：本值 20 实为 tokens.json `typography.scale.h2Reader`，
  /// **不是** `AppTypography.formulaDisplay`(19)。块级公式主渲染路径（Math.tex）
  /// 用此值，fallback 路径（[AppTypography.formula]）用 19，二者并存为既有不一致。
  /// 收敛为单一来源属 P1-3 后续项（会改像素，需同步 golden 基线）。
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
=======
  static const double caption = 11;

  static const double formulaInline = 16;
  static const double formulaDisplay = 20;
}

class AppShadows {
  AppShadows._();

  static List<BoxShadow> card({bool isDark = false}) => [
    BoxShadow(
      color: (isDark ? Colors.black : Colors.black).withValues(alpha: 0.05),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ];
>>>>>>> f60831d (补 0010-SKIPPED 编号纪律占位，新增 ADR-0021 Repository Integrity Strategy v1.4)
}