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

class AppShadows {
  AppShadows._();

  static List<BoxShadow> card({bool isDark = false}) => [
    BoxShadow(
      color: (isDark ? Colors.black : Colors.black).withValues(alpha: 0.05),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ];
}