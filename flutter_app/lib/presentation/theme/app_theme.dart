import 'package:flutter/material.dart';

import '../themes/editor_tokens.dart';
import 'app_typography.dart';

/// 应用主题模式（Phase 3.4 Slice 3 / ADR-0015）。
///
/// 三向：浅色 / 夜间 / 护眼(sepia)。持久化键见 [themeModeProvider]。
enum AppThemeMode {
  light,
  dark,
  sepia;

  /// 是否按「深色」渲染（legacy AppColors 路径据此取 dark 调色板）。
  bool get isDark => this == AppThemeMode.dark;
}

class AppTheme {
  // ===== Brand & semantic —— design-system/tokens.json (color.light) =====
  static const Color primaryColor = Color(0xFF1E3A5F);
  static const Color primaryHover = Color(0xFF16304F);
  static const Color successColor = Color(0xFF2D6A4F);
  static const Color warningColor = Color(0xFFE9C46A);
  static const Color errorColor = Color(0xFFC1121F);

  // ===== Text =====
  static const Color textPrimary = Color(0xFF1A1D23);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9AA0A6);

  // ===== Surface =====
  static const Color background = Color(0xFFFFFFFF); // card / AppBar
  static const Color backgroundSecondary = Color(0xFFFAFAF7); // warm paper
  static const Color border = Color(0xFFE5E4DF);

  /// 浅色主题（注入 [EditorTokens.light]）。
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: backgroundSecondary,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
      ),
      textTheme: AppTypography.textTheme(Brightness.light),
      primaryTextTheme: AppTypography.textTheme(Brightness.light),
      extensions: const <ThemeExtension<dynamic>>[EditorTokens.light],
    );
  }

  /// 夜间主题（注入 [EditorTokens.dark]）。
  static ThemeData get darkTheme {
    const seed = Color(0xFF5B8DB8); // tokens color.dark.brand.primary
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F1419),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1D23),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: const Color(0xFF0F1419),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textTheme: AppTypography.textTheme(Brightness.dark),
      primaryTextTheme: AppTypography.textTheme(Brightness.dark),
      extensions: const <ThemeExtension<dynamic>>[EditorTokens.dark],
    );
  }

  /// 护眼(sepia)主题（注入 [EditorTokens.sepia]）。
  static ThemeData get sepiaTheme {
    const sepiaSeed = Color(0xFF9C7A4D);
    const sepiaBg = Color(0xFFF8F0E0);
    const sepiaSurface = Color(0xFFFBF3E3);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: sepiaSeed,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: sepiaBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: sepiaSurface,
        foregroundColor: Color(0xFF403020),
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: sepiaSeed,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textTheme: AppTypography.textTheme(Brightness.light),
      primaryTextTheme: AppTypography.textTheme(Brightness.light),
      extensions: const <ThemeExtension<dynamic>>[EditorTokens.sepia],
    );
  }

  /// 按 [AppThemeMode] 返回对应 [ThemeData]。
  static ThemeData themeFor(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.light => lightTheme,
      AppThemeMode.dark => darkTheme,
      AppThemeMode.sepia => sepiaTheme,
    };
  }
}
