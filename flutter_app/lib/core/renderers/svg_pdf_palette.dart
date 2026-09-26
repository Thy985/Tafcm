/// SVG → PDF 绘制辅助（颜色 / 字体解析）。
///
/// 从 svg_to_pdf.dart 拆出的**纯函数**辅助（Issue #234 加 debugCountPathOps
/// 后主文件超 400 行，AGENTS.md §11.3 强制拆分）。只依赖 `pdf` 包类型：
/// - [parseSvgFill]: SVG 颜色字符串 → PdfColor（含 MathJax `currentColor`）
/// - [resolveSvgFont]: font-family → PdfFont 兜底映射
library;

import 'package:pdf/pdf.dart';

/// 解析 SVG 颜色字符串。MathJax 输出常用 `#rrggbb` / `#rgb` / `none` /
/// `currentColor`。`none` / `transparent` / 空返回 null（不绘制）。
///
/// [currentColor] 是 `currentColor` 关键字应映射到的颜色（调用方通常传
/// widget 的文本色）；它为 null 时 `currentColor` 也解析为 null。
PdfColor? parseSvgColor(String? raw, PdfColor? currentColor) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty || s == 'none' || s == 'transparent') return null;
  if (s == 'currentColor') return currentColor;
  if (s.startsWith('#')) {
    try {
      if (s.length == 7) {
        return PdfColor.fromInt(int.parse(s.substring(1), radix: 16) |
            0xFF000000);
      }
      if (s.length == 4) {
        final r = s[1];
        final g = s[2];
        final b = s[3];
        return PdfColor.fromInt(
          int.parse('$r$r$g$g$b$b', radix: 16) | 0xFF000000,
        );
      }
      if (s.length == 9) {
        return PdfColor.fromInt(int.parse(s.substring(1), radix: 16));
      }
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// 简单 font-family 查找 —— MathJax SVG 通常不输出 font-family。
PdfFont resolveSvgFont(String? family, PdfFont textFont, PdfFont fallbackFont) {
  if (family == null) return textFont;
  final lower = family.toLowerCase();
  if (lower.contains('mono') ||
      lower.contains('courier') ||
      lower.contains('serif') ||
      lower.contains('times') ||
      lower.contains('italic') ||
      lower.contains('oblique') ||
      lower.contains('bold')) {
    return fallbackFont;
  }
  return textFont;
}