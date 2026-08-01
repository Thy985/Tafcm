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

import '../../core/constants/app_constants.dart';

class AppTypography {
  AppTypography._();

  /// 衬线字族：文档正文、标题、公式、数字。
  ///
  /// Tier 2 (TEST_GAP_PLAN T2-0)：原值是逗号分隔的平台字体回退链，依赖平台
  /// 字体解析 → 跨平台（Windows vs Linux CI）渲染不一致，正是 GOLDEN-CI-001
  /// 的根因。改为打包注册的单一字族名 [NotoSerifSC]（pubspec `fonts:` 注册，
  /// 含 Latin + CJK 字形），保证本地与 CI 渲染一致。
  static const String serif = 'NotoSerifSC';

  /// 无衬线字族：UI chrome、标签、按钮、导航。
  static const String sans = 'NotoSansSC';

  /// 等宽字族：行内代码、公式源码、状态栏。
  ///
  /// Tier 2 (TEST_GAP_PLAN T2-1)：原值逗号分隔平台等宽回退链（同 serif/sans
  /// 旧症），改为打包注册的单一字族名 [CascadiaMono]（OFL，Cascadia Code 家族，
  /// `pubspec` `fonts:` 注册，`assets/fonts/CascadiaMono.ttf`）。与 serif/sans
  /// 一致，从根因消除「等宽字体跨平台不一致」导致的 golden 抖动。
  static const String mono = 'CascadiaMono';

<<<<<<< HEAD
  // ── 字号令牌（P1-3）：权威值取自 tokens.json `typography.scale` ──

  /// 说明文字字号 —— tokens.json `typography.scale.caption`。
  ///
  /// 注意与 [AppSpacing.caption](11) 区分：后者实为 `meta` 档的历史误名。
  static const double caption = 10;

  /// 底部 tab 标签字号 —— tokens.json `typography.scale.tabLabel`。
  static const double tabLabel = 11;

  /// 编辑模式块级公式字号 —— tokens.json `typography.scale.formulaDisplay`。
  static const double formulaDisplay = 19;

  /// 阅读模式块级公式字号 —— tokens.json
  /// `typography.scale.formulaDisplayReader`（阅读态比编辑态大一档）。
  static const double formulaDisplayReader = 21;

=======
>>>>>>> f60831d (补 0010-SKIPPED 编号纪律占位，新增 ADR-0021 Repository Integrity Strategy v1.4)
  /// 公式样式（文档 / 块级公式）：serif + italic。
  ///
  /// 颜色不由本方法固化（TextSpan 无法在构造时取运行时 theme），调用方经
  /// [EditorTokens] 注入 [color]。[ADR-0017]：公式样式不写死在 FormulaBlock，
  /// 由本方法统一提供（fontSize 对齐 tokens.json `typography.scale.formulaDisplay`）。
  static TextStyle formula({Color? color}) => TextStyle(
        fontFamily: serif,
        fontStyle: FontStyle.italic,
<<<<<<< HEAD
        fontSize: formulaDisplay,
=======
        fontSize: 19,
>>>>>>> f60831d (补 0010-SKIPPED 编号纪律占位，新增 ADR-0021 Repository Integrity Strategy v1.4)
        height: 1.4,
        color: color,
      );

  /// 按亮度构建全局 [TextTheme]（serif 正文 + sans 标签）。
  ///
  /// 字号梯度取自 tokens.json `typography.scale`：
  /// readerH1 28 / h1 26 / h2 19-20 / sectionHeader 18 / readerBody 16 / editorBody 15。
  static TextTheme textTheme(Brightness brightness) {
    final textColor = brightness == Brightness.dark
        ? AppColors.darkText
        : AppColors.lightText;
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
