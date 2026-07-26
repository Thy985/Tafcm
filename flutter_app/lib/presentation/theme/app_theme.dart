import 'package:flutter/material.dart';

import '../themes/editor_tokens.dart';

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
  static const Color primaryColor = Color(0xFF165DFF);
  static const Color primaryHover = Color(0xFF0E42CC);
  static const Color successColor = Color(0xFF00B42A);
  static const Color warningColor = Color(0xFFFF7D00);
  static const Color errorColor = Color(0xFFF53F3F);

  static const Color textPrimary = Color(0xFF1D2129);
  static const Color textSecondary = Color(0xFF4E5969);
  static const Color textTertiary = Color(0xFF86909C);

  static const Color background = Color(0xFFFFFFFF);
  static const Color backgroundSecondary = Color(0xFFF2F3F5);
  static const Color border = Color(0xFFE5E6EB);

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
            borderRadius: BorderRadius.circular(8),
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
      extensions: const <ThemeExtension<dynamic>>[EditorTokens.light],
    );
  }

  /// 夜间主题（注入 [EditorTokens.dark]）。
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4080FF),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF1A1A1A),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4080FF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
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
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
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
