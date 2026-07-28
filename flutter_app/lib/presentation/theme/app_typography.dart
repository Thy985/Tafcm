/// 排版 token（Phase 3.4.5 / ADR-0017 Design System Alignment）。
///
/// 与 [AppColors] 共同构成 Design System 的单一真相源，权威值取自
/// `design-system/tokens.json` 的 `typography` 段。
///
/// 三套字族分工（对齐 redesign 原型）：
/// - [serif]：文档正文 / 标题 / 公式 / 数字
/// - [sans] ：UI chrome / 标签 / 按钮 / 导航
/// - [mono] ：行内代码 / 公式源码 / 状态栏等
///
/// 使用约定：
/// - 文档正文与标题一律走 [serif]（见 `heading_block.dart` / `paragraph_block.dart`）。
/// - 代码相关走 [mono]（见 `code_block.dart` / `table_block.dart`）。
/// - UI 标签走 [sans]（见 `textTheme` 的 label* 角色）。
import 'package:flutter/material.dart';

class AppTypography {
  AppTypography._();

  /// 衬线字族：文档正文、标题、公式、数字。
  static const String serif =
      'Iowan Old Style, Palatino Linotype, Source Han Serif SC, Songti SC, Georgia, serif';

  /// 无衬线字族：UI chrome、标签、按钮、导航。
  static const String sans =
      '-apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, PingFang SC, Hiragino Sans GB, Microsoft YaHei, sans-serif';

  /// 等宽字族：行内代码、公式源码、状态栏。
  static const String mono =
      'SF Mono, JetBrains Mono, Fira Code, Consolas, monospace';

  /// 公式样式（文档 / 块级公式）：serif + italic。
  ///
  /// 颜色不由本方法固化（TextSpan 无法在构造时取运行时 theme），调用方经
  /// [EditorTokens] 注入 [color]。[ADR-0017]：公式样式不写死在 FormulaBlock，
  /// 由本方法统一提供（fontSize 对齐 tokens.json `typography.scale.formulaDisplay`）。
  static TextStyle formula({Color? color}) => TextStyle(
        fontFamily: serif,
        fontStyle: FontStyle.italic,
        fontSize: 19,
        height: 1.4,
        color: color,
      );

  /// 按亮度构建全局 [TextTheme]（serif 正文 + sans 标签）。
  ///
  /// 字号梯度取自 tokens.json `typography.scale`：
  /// readerH1 28 / h1 26 / h2 19-20 / sectionHeader 18 / readerBody 16 / editorBody 15。
  static TextTheme textTheme(Brightness brightness) {
    final textColor = brightness == Brightness.dark
        ? const Color(0xFFE8EAED)
        : const Color(0xFF1A1D23);
    return TextTheme(
      displayLarge: TextStyle(
          fontFamily: serif, fontSize: 28, fontWeight: FontWeight.w700, height: 1.25, color: textColor),
      displayMedium: TextStyle(
          fontFamily: serif, fontSize: 26, fontWeight: FontWeight.w700, height: 1.25, color: textColor),
      headlineLarge: TextStyle(
          fontFamily: serif, fontSize: 26, fontWeight: FontWeight.w700, height: 1.25, color: textColor),
      headlineMedium: TextStyle(
          fontFamily: serif, fontSize: 20, fontWeight: FontWeight.w600, height: 1.3, color: textColor),
      headlineSmall: TextStyle(
          fontFamily: serif, fontSize: 18, fontWeight: FontWeight.w600, height: 1.3, color: textColor),
      titleLarge: TextStyle(
          fontFamily: serif, fontSize: 18, fontWeight: FontWeight.w600, height: 1.3, color: textColor),
      titleMedium: TextStyle(
          fontFamily: sans, fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
      titleSmall: TextStyle(
          fontFamily: sans, fontSize: 13, fontWeight: FontWeight.w500, color: textColor),
      bodyLarge: TextStyle(
          fontFamily: serif, fontSize: 16, height: 1.9, color: textColor),
      bodyMedium: TextStyle(
          fontFamily: serif, fontSize: 15, height: 1.85, color: textColor),
      labelLarge: TextStyle(
          fontFamily: sans, fontSize: 13, fontWeight: FontWeight.w500, color: textColor),
      labelMedium: TextStyle(
          fontFamily: sans, fontSize: 12, color: textColor),
      labelSmall: TextStyle(
          fontFamily: sans, fontSize: 11, color: textColor),
    );
  }
}
