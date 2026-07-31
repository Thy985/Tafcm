/// EditorTokens：主题 token（Phase 3.4 Slice 3 / ADR-0015 ThemeExtension 迁移）。
///
/// 落地 ADR-0015：颜色 token 随主题变化，作为 [ThemeExtension] 实例字段，
/// 经 [EditorTokens.of] 在运行时按当前 [ThemeData] 注入的实例取值
/// （light / dark / sepia 三套，见 [AppTheme]）。
///
/// **app-wide 角色（ADR-0018 Decision 3）**：本类为 app-wide design token 载体，
/// 编辑器 / 首页 / 文件 / 阅读 / 我的 / CodeBlock / 块级公式均消费此 Token。
/// 实例字段禁止静态访问（TC-THEME）。若未来非编辑器屏出现专用 token，先在
/// `EditorTokens` 追加；仅当编辑器专属占比失衡时评估拆 `AppTokens`（记新 ADR）。
///
/// **两类 token**：
/// - 主题相关颜色：实例字段（textPrimary / codeBackground / …），必须经由
///   [EditorTokens.of] 取，禁止静态访问（架构守门 TC-THEME）。
/// - 主题无关常量：保持 `static const`（布局间距 / 字号 / 圆角 / 状态栏）。
/// - 行内 [TextSpan] 的 [linkColor]：TextSpan 无法运行时取 BuildContext，
///   按 ADR-0015 留作已知边界（Issue `wontfix` + `phase-3.4-typography`），
///   保持 `static const`。
library;

import 'package:flutter/material.dart';

/// 编辑器主题 token（Phase 3.4 Slice 3 / ADR-0015）。
///
/// 所有 UI 组件应优先使用 [EditorTokens.of] 而非硬编码值，便于主题切换。
class EditorTokens extends ThemeExtension<EditorTokens> {
  const EditorTokens({
    required this.textPrimary,
    required this.textSecondary,
    required this.borderFocused,
    required this.borderDefault,
    required this.codeBackground,
    required this.codeLanguageChip,
    required this.quoteBorderColor,
    required this.tableBorderColor,
    required this.tableHeaderBackground,
    required this.surfaceMuted,
    required this.brandPrimary,
    required this.brandPrimaryForeground,
  });

  // ============ 主题相关颜色（实例字段，经 of(context) 取值） ============

  /// 主文本颜色。
  final Color textPrimary;

  /// 次要文本颜色（标注、占位）。
  final Color textSecondary;

  /// 编辑态边框颜色（聚焦时）。
  final Color borderFocused;

  /// 渲染态边框颜色（默认）。
  final Color borderDefault;

  /// 代码块背景色。
  final Color codeBackground;

  /// 代码块 language chip 颜色。
  final Color codeLanguageChip;

  /// 引用块左侧竖线颜色。
  final Color quoteBorderColor;

  /// 表格边框颜色。
  final Color tableBorderColor;

  /// 表格表头背景色。
  final Color tableHeaderBackground;

  /// 静音表面色 → tokens color.*.surface.muted（light #F0EFEA / dark #242830 / sepia #EDE3D0）。
  ///
  /// 用于 searchPill 背景、toggle 关态轨道等"低对比容器"。**精确取 tokens 值，
  /// 不使用 `colorScheme.surfaceContainerHighest`**（M3 灰阶会偏离 #F0EFEA）。
  final Color surfaceMuted;

  /// 品牌主色 → tokens color.*.brand.primary（light #1E3A5F / dark #5B8DB8 / sepia #9C7A4D）。
  ///
  /// 用于 fab 背景、toggle 开态轨道。精确取 tokens 值，不使用 M3 重映射的
  /// `colorScheme.primary`。
  final Color brandPrimary;

  /// 品牌主色前景 → tokens color.*.brand.primaryForeground（light #FFFFFF / dark #0F1419 / sepia #FFFFFF）。
  ///
  /// 用于 fab 前景（图标）。精确取 tokens 值，不使用 `colorScheme.onPrimary`。
  final Color brandPrimaryForeground;

  /// 浅色主题实例（对齐 design-system/tokens.json color.light）。
  static const EditorTokens light = EditorTokens(
    textPrimary: Color(0xFF1A1D23),
    textSecondary: Color(0xFF6B7280),
    borderFocused: Color(0xFF1E3A5F),
    borderDefault: Color(0xFFE5E4DF),
    codeBackground: Color(0xFFF0EFEA),
    codeLanguageChip: Color(0xFFE5E4DF),
    quoteBorderColor: Color(0xFFD8D3C8),
    tableBorderColor: Color(0xFFE5E4DF),
    tableHeaderBackground: Color(0xFFF0EFEA),
    surfaceMuted: Color(0xFFF0EFEA),
    brandPrimary: Color(0xFF1E3A5F),
    brandPrimaryForeground: Color(0xFFFFFFFF),
  );

  /// 夜间主题实例（对齐 design-system/tokens.json color.dark）。
  static const EditorTokens dark = EditorTokens(
    textPrimary: Color(0xFFE8EAED),
    textSecondary: Color(0xFF9AA0A6),
    borderFocused: Color(0xFF5B8DB8),
    borderDefault: Color(0xFF2A2F38),
    codeBackground: Color(0xFF13171D),
    codeLanguageChip: Color(0xFF2A2F38),
    quoteBorderColor: Color(0xFF3A3F48),
    tableBorderColor: Color(0xFF2A2F38),
    tableHeaderBackground: Color(0xFF1A1D23),
    surfaceMuted: Color(0xFF242830),
    brandPrimary: Color(0xFF5B8DB8),
    brandPrimaryForeground: Color(0xFF0F1419),
  );

  /// 护眼(sepia)主题实例。
  static const EditorTokens sepia = EditorTokens(
    textPrimary: Color(0xFF403020),
    textSecondary: Color(0xFF7A6A55),
    borderFocused: Color(0xFF9C7A4D),
    borderDefault: Color(0xFFD8C9B0),
    codeBackground: Color(0xFFEDE3D0),
    codeLanguageChip: Color(0xFFD8C9B0),
    quoteBorderColor: Color(0xFFBBA583),
    tableBorderColor: Color(0xFFD8C9B0),
    tableHeaderBackground: Color(0xFFEDE3D0),
    surfaceMuted: Color(0xFFEDE3D0),
    brandPrimary: Color(0xFF9C7A4D),
    brandPrimaryForeground: Color(0xFFFFFFFF),
  );

  /// 运行时按当前 [ThemeData] 注入的实例取值。
  ///
  /// 要求当前 [ThemeData] 已通过 `extensions: [EditorTokens.xxx]` 注入
  /// （见 [AppTheme]），否则抛 [FlutterError] 并给出明确修复指引
  /// （而非泛化的 "Null check operator used on a null value"）。
  static EditorTokens of(BuildContext context) {
    final tokens = Theme.of(context).extension<EditorTokens>();
    assert(() {
      if (tokens == null) {
        throw FlutterError(
          'EditorTokens 未注入当前 ThemeData。\n'
          '请在 ThemeData(extensions: [EditorTokens.xxx]) 中注入（见 AppTheme）。',
        );
      }
      return true;
    }());
    return tokens!;
  }

  @override
  EditorTokens copyWith({
    Color? textPrimary,
    Color? textSecondary,
    Color? borderFocused,
    Color? borderDefault,
    Color? codeBackground,
    Color? codeLanguageChip,
    Color? quoteBorderColor,
    Color? tableBorderColor,
    Color? tableHeaderBackground,
    Color? surfaceMuted,
    Color? brandPrimary,
    Color? brandPrimaryForeground,
  }) {
    return EditorTokens(
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      borderFocused: borderFocused ?? this.borderFocused,
      borderDefault: borderDefault ?? this.borderDefault,
      codeBackground: codeBackground ?? this.codeBackground,
      codeLanguageChip: codeLanguageChip ?? this.codeLanguageChip,
      quoteBorderColor: quoteBorderColor ?? this.quoteBorderColor,
      tableBorderColor: tableBorderColor ?? this.tableBorderColor,
      tableHeaderBackground: tableHeaderBackground ?? this.tableHeaderBackground,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      brandPrimary: brandPrimary ?? this.brandPrimary,
      brandPrimaryForeground:
          brandPrimaryForeground ?? this.brandPrimaryForeground,
    );
  }

  @override
  EditorTokens lerp(ThemeExtension<EditorTokens>? other, double t) {
    if (other is! EditorTokens) return this;
    return EditorTokens(
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      borderFocused:
          Color.lerp(borderFocused, other.borderFocused, t) ?? borderFocused,
      borderDefault:
          Color.lerp(borderDefault, other.borderDefault, t) ?? borderDefault,
      codeBackground:
          Color.lerp(codeBackground, other.codeBackground, t) ?? codeBackground,
      codeLanguageChip: Color.lerp(codeLanguageChip, other.codeLanguageChip, t) ??
          codeLanguageChip,
      quoteBorderColor: Color.lerp(quoteBorderColor, other.quoteBorderColor, t) ??
          quoteBorderColor,
      tableBorderColor: Color.lerp(tableBorderColor, other.tableBorderColor, t) ??
          tableBorderColor,
      tableHeaderBackground:
          Color.lerp(tableHeaderBackground, other.tableHeaderBackground, t) ??
              tableHeaderBackground,
      surfaceMuted:
          Color.lerp(surfaceMuted, other.surfaceMuted, t) ?? surfaceMuted,
      brandPrimary:
          Color.lerp(brandPrimary, other.brandPrimary, t) ?? brandPrimary,
      brandPrimaryForeground:
          Color.lerp(brandPrimaryForeground, other.brandPrimaryForeground, t) ??
              brandPrimaryForeground,
    );
  }

  // ============ 主题无关常量（保持 static const，ADR-0015 边界） ============

  /// 行内链接颜色（Phase 3.2 §3.7 LinkElement inline rendering）。
  ///
  /// 注：用于 ParagraphBlock 的 inline [TextSpan]，TextSpan 不支持运行时
  /// [Theme.of] 查找，需编译时常量。按 ADR-0015 留作已知边界
  /// （Issue `wontfix` + `phase-3.4-typography`），不随主题切换。
  static const Color linkColor = Color(0xFF1E3A5F);

  // ============ 间距 ============

  /// 块间距（块与块之间的垂直间距）→ tokens.json spacing.paragraphGap (20px)。
  /// EditorViewport 对每块上下各垫 blockSpacing/2，相邻块合计间距 = blockSpacing。
  static const double blockSpacing = 20.0;

  /// 块内边距（水平）。
  static const double blockPaddingHorizontal = 12.0;

  /// 块内边距（垂直）。
  static const double blockPaddingVertical = 6.0;

  /// EditorViewport 整体内边距 → tokens.json spacing.pageHorizontal (24px)。
  static const double viewportPadding = 24.0;

  // ============ 字号 ============

  /// 段落字号 → tokens.json typography.scale.editorBody.size (15px)。
  static const double paragraphFontSize = 15.0;

  /// 代码字号。
  static const double codeFontSize = 14.0;

  /// 表格单元格字号（与 code 字号一致但语义独立）。
  static const double tableCellFontSize = 14.0;

  /// 状态栏字号。
  static const double statusBarFontSize = 11.0;

  /// heading 字号映射（level 1-6）→ tokens.json typography.scale（h1 26 / h2 19 / …）。
  static const List<double> headingFontSizes = [26, 19, 18, 16, 14, 13];

  // ============ 圆角 ============

  /// 块圆角 → tokens.json radius.sm (6px)。
  static const double blockRadius = 6.0;

  /// chip 圆角（language chip 等）→ tokens.json radius.sm (6px)。
  static const double chipRadius = 6.0;

  // ============ 状态栏 ============

  /// 状态栏高度 → tokens.json spacing.statusBarHeight (32px)。
  static const double statusBarHeight = 32.0;

  /// AppBar 高度（对齐 [kToolbarHeight]）。
  static const double appBarHeight = kToolbarHeight;
}
