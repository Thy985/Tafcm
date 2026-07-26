/// EditorTokens：主题 token（Phase 3.4 Slice 3 / ADR-0015 ThemeExtension 迁移）。
///
/// 落地 ADR-0015：颜色 token 随主题变化，作为 [ThemeExtension] 实例字段，
/// 经 [EditorTokens.of] 在运行时按当前 [ThemeData] 注入的实例取值
/// （light / dark / sepia 三套，见 [AppTheme]）。
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

  /// 浅色主题实例。
  static const EditorTokens light = EditorTokens(
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF6B6B6B),
    borderFocused: Color(0xFF2196F3),
    borderDefault: Color(0xFFE0E0E0),
    codeBackground: Color(0xFFF5F5F5),
    codeLanguageChip: Color(0xFFE0E0E0),
    quoteBorderColor: Color(0xFFC0C0C0),
    tableBorderColor: Color(0xFFE0E0E0),
    tableHeaderBackground: Color(0xFFF5F5F5),
  );

  /// 夜间主题实例。
  static const EditorTokens dark = EditorTokens(
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0B0B0),
    borderFocused: Color(0xFF4080FF),
    borderDefault: Color(0xFF3A3A3A),
    codeBackground: Color(0xFF2A2A2A),
    codeLanguageChip: Color(0xFF3A3A3A),
    quoteBorderColor: Color(0xFF555555),
    tableBorderColor: Color(0xFF3A3A3A),
    tableHeaderBackground: Color(0xFF2A2A2A),
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
    );
  }

  // ============ 主题无关常量（保持 static const，ADR-0015 边界） ============

  /// 行内链接颜色（Phase 3.2 §3.7 LinkElement inline rendering）。
  ///
  /// 注：用于 ParagraphBlock 的 inline [TextSpan]，TextSpan 不支持运行时
  /// [Theme.of] 查找，需编译时常量。按 ADR-0015 留作已知边界
  /// （Issue `wontfix` + `phase-3.4-typography`），不随主题切换。
  static const Color linkColor = Color(0xFF2196F3);

  // ============ 间距 ============

  /// 块间距（块与块之间的垂直间距）。
  static const double blockSpacing = 8.0;

  /// 块内边距（水平）。
  static const double blockPaddingHorizontal = 12.0;

  /// 块内边距（垂直）。
  static const double blockPaddingVertical = 6.0;

  /// EditorViewport 整体内边距。
  static const double viewportPadding = 16.0;

  // ============ 字号 ============

  /// 段落字号。
  static const double paragraphFontSize = 16.0;

  /// 代码字号。
  static const double codeFontSize = 14.0;

  /// 表格单元格字号（与 code 字号一致但语义独立）。
  static const double tableCellFontSize = 14.0;

  /// 状态栏字号。
  static const double statusBarFontSize = 11.0;

  /// heading 字号映射（level 1-6）。
  static const List<double> headingFontSizes = [28, 24, 22, 20, 18, 16];

  // ============ 圆角 ============

  /// 块圆角。
  static const double blockRadius = 4.0;

  /// chip 圆角（language chip 等）。
  static const double chipRadius = 3.0;

  // ============ 状态栏 ============

  /// 状态栏高度。
  static const double statusBarHeight = 24.0;

  /// AppBar 高度（对齐 [kToolbarHeight]）。
  static const double appBarHeight = kToolbarHeight;
}
