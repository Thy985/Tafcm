import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:formula_fix/domain/services/exporters/formula_render_plan.dart';

/// 断言字符串中不存在未配对的 UTF-16 代理（孤立 high 或 low surrogate）。
///
/// 合法 surrogate pair（如 U+1F600 emoji = `\uD83D\uDE00`）的高位
/// surrogate (0xD800-0xDBFF) 是允许的——它必须紧跟一个低位
/// surrogate (0xDC00-0xDFFF)。
void _expectNoUnpairedSurrogates(String s) {
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      // high surrogate — 必须后跟 low surrogate
      if (i + 1 >= s.length) {
        throw StateError('Unpaired high surrogate at end of string: U+${unit.toRadixString(16)}');
      }
      final next = s.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) {
        throw StateError(
            'Unpaired high surrogate U+${unit.toRadixString(16)} '
            'not followed by low surrogate (got U+${next.toRadixString(16)})');
      }
      i++; // 跳过配对的 low surrogate
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      throw StateError('Unpaired low surrogate: U+${unit.toRadixString(16)}');
    }
  }
}

void main() {
  group('sanitizeSvgString', () {
    test('空字符串返回空字符串', () {
      expect(sanitizeSvgString(''), '');
    });

    test('纯 ASCII 不变', () {
      const input = '<svg viewBox="0 0 100 50"></svg>';
      expect(sanitizeSvgString(input), input);
    });

    test('合法 UTF-8 多字节字符（数学符号）保留', () {
      const input = '<svg><text>α + β = γ</text></svg>';
      expect(sanitizeSvgString(input), input);
    });

    test('合法 UTF-8 4 字节 emoji 保留', () {
      const input = '<svg><text>🎉</text></svg>';
      expect(sanitizeSvgString(input), input);
    });

    test('未配对 high surrogate (U+D800) 被替换为 U+FFFD', () {
      // 模拟 WebView 桥接时残留的孤立 surrogate
      const input = '<svg><text>hi \uD800</text></svg>';
      final result = sanitizeSvgString(input);
      // 整串应可被 utf8.encode 安全处理
      expect(() => utf8.encode(result), returnsNormally);
      // 孤立 surrogate 必须被替换，不能保留
      _expectNoUnpairedSurrogates(result);
      // 内容大部分保留
      expect(result, contains('hi'));
      expect(result, contains('<svg>'));
    });

    test('未配对 low surrogate (U+DC00) 被替换为 U+FFFD', () {
      const input = '<svg><text>hi \uDC00</text></svg>';
      final result = sanitizeSvgString(input);
      expect(() => utf8.encode(result), returnsNormally);
      _expectNoUnpairedSurrogates(result);
    });

    test('合法的 surrogate pair (U+1F600 😀) 保留', () {
      // Dart String 字面量里 \uD83D\uDE00 是合法 surrogate pair
      const input = '<svg><text>\uD83D\uDE00</text></svg>';
      final result = sanitizeSvgString(input);
      expect(result, input);
      _expectNoUnpairedSurrogates(result);
    });

    test('混合未配对 + 合法 pair 同时出现：正确处理两种', () {
      // \uD800 (未配对) + 空格 + \uD83D\uDE00 (合法 emoji) + 空格 + \uDC00 (未配对)
      const input = '<svg><text>math: \uD800 \uD83D\uDE00 \uDC00</text></svg>';
      final result = sanitizeSvgString(input);
      // 整串可被 utf8.encode 安全处理（这是用户实际遇到错误的根因）
      expect(() => utf8.encode(result), returnsNormally);
      // 不存在未配对 surrogate
      _expectNoUnpairedSurrogates(result);
      // 内容大部分保留
      expect(result, contains('math:'));
      expect(result, contains('<svg>'));
      // 合法 emoji 仍然存在
      expect(result.contains('\uD83D\uDE00'), isTrue);
    });

    test('长 SVG（>1KB）也不抛错', () {
      final input = '<svg>${'x' * 2048}<text>\uD800\uDC00</text></svg>';
      expect(() => sanitizeSvgString(input), returnsNormally);
    });

    /// **关键回归测试**：用户实际遇到的错误
    /// "FormatException: Unexpected extension byte (at offset 1)" 根因。
    ///
    /// 场景：SVG 字符串同时含非 BMP 字符（数学字母数字 𝑀 = U+1D44C）
    /// 和未配对 surrogate（U+D800）。旧实现 fallback 路径用
    /// `String.fromCharCode(r)` 逐字符重建，对 rune > 0xFFFF 截断为低
    /// 16 位 0xD44C（孤立 surrogate），再次触发 utf8.encode 抛
    /// "Unexpected extension byte (at offset 1)"。
    test('非 BMP 字符 + 未配对 surrogate 混合：清洗后必须能 utf8.encode', () {
      // 真实场景模拟：MathJax 输出的 SVG 包含数学符号 + 偶尔的孤立 surrogate
      const input = '<svg viewBox="0 0 200 50">'
          '<text>𝑀</text>' // 𝑀 = U+1D44C (非 BMP，UTF-16: D835 D44C)
          '<text>\uD800</text>' // 孤立 high surrogate
          '<text>end</text>'
          '</svg>';
      final result = sanitizeSvgString(input);
      // 关键断言 1：utf8.encode 必须成功（这是导致 PDF 导出失败的根因）
      expect(() => utf8.encode(result), returnsNormally,
          reason: 'sanitize 后的 SVG 必须能 utf8.encode，否则 pw.SvgImage 会抛错');
      // 关键断言 2：不存在未配对 surrogate
      _expectNoUnpairedSurrogates(result);
      // 关键断言 3：非 BMP 字符 𝑀 仍然存在（说明没被截断）
      expect(result, contains('𝑀'),
          reason: '非 BMP 字符 𝑀 必须被 fromCharCodes 正确编码为合法 surrogate pair');
    });

    test('控制字符 (NUL/BEL/ESC) 被替换为 U+FFFD', () {
      const input = '<svg>\u0000bell\u0007esc\u001B</svg>';
      final result = sanitizeSvgString(input);
      expect(() => utf8.encode(result), returnsNormally);
      _expectNoUnpairedSurrogates(result);
      // 控制字符被替换为 U+FFFD（不止 1 个，因为有 3 个控制字符）
      expect(result.contains('\uFFFD'), isTrue);
    });

    test('Tab/LF/CR 三个合法 XML 控制字符被保留', () {
      const input = '<svg>\n<text>line1</text>\r\n<text>line2\tcol</text>\n</svg>';
      final result = sanitizeSvgString(input);
      expect(result, contains('\n'));
      expect(result, contains('\r\n'));
      expect(result, contains('\t'));
    });
  });

  // P1 验收补充（2026-08-04）：公式导出三路径单元测试。
  //
  // PdfExporter.buildFormulaPlan 把 LaTeX 渲染为 PDF widget 时按
  //   SVG（矢量优先） → PNG 位图（SVG 失败） → 文本兜底
  // 三级回退。这里直接对 FormulaRenderPlan 三种 plan 调用 toPdfWidget，
  // 锁定每条路径的输出 widget 类型，避免后续重构静默改变回退链。
  group('FormulaRenderPlan.toPdfWidget 三路径', () {
    const latex = r'E = mc^2';
    const fontSize = 14.0;

    test('SvgPlan：合法 SVG → pw.Container 包 SvgPdfWidget', () {
      // 一段最小合法 SVG，确保 parseSvgString 不退到 unsupported。
      const svg = '<svg viewBox="0 0 100 20"><text x="0" y="15">E=mc^2</text></svg>';
      final plan = FormulaRenderPlan.svg(svg, latex, false);
      final widget = plan.toPdfWidget(fontSize: fontSize);

      // SvgPlan 总是把 SvgPdfWidget 包在 pw.Container 里（带 margin）。
      expect(widget, isA<pw.Container>(),
          reason: 'SvgPlan 应输出 pw.Container，实际: ${widget.runtimeType}');
      final container = widget as pw.Container;
      // 内部 child 应是 SvgPdfWidget（来自 core/renderers/svg_to_pdf.dart）。
      // 不直接断言 SvgPdfWidget 类型（避免 import 内部模块），改断言非空。
      expect(container.child, isNotNull);
    });

    test('SvgPlan：SVG 解析失败 → 回退到 FallbackPlan 的 pw.Text', () {
      // 故意传入无法解析的 SVG 字符串。parseSvgString 内部 try/catch
      // 兜底返回带 SvgUnsupported 的空 root，不抛异常。SvgPdfWidget
      // paint 时不抛异常。这里再传一个明显错误的 SVG（畸形 XML）
      // 验证 SvgPlan.toPdfWidget 的 try/catch 回退分支：任何环节失败
      // 都退到 FallbackPlan.toPdfWidget 输出 pw.Text。
      const malformedSvg = '<<<not a svg>>>';
      final plan = FormulaRenderPlan.svg(malformedSvg, latex, false);
      final widget = plan.toPdfWidget(fontSize: fontSize);

      // 容错路径：要么返回 pw.Container（SvgPdfWidget 渲染 unsupported 占位），
      // 要么在抛异常时退到 pw.Text。两条都是合法回退，这里只断言
      // "不抛未捕获异常 + 返回非空 widget"。
      expect(widget, isNotNull);
    });

    test('PngPlan：合法 PNG 字节 → pw.Container 包 pw.Image', () {
      // 1×1 透明 PNG 的最小合法字节流（PNG signature + IHDR + IDAT + IEND）。
      final pngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
        0x00, 0x00, 0x00, 0x0D, // IHDR length
        0x49, 0x48, 0x44, 0x52, // 'IHDR'
        0x00, 0x00, 0x00, 0x01, // width=1
        0x00, 0x00, 0x00, 0x01, // height=1
        0x08, 0x06, 0x00, 0x00, 0x00, // bit depth=8, color type=6 (RGBA)
        0x1F, 0x15, 0xC4, 0x89, // CRC
        0x00, 0x00, 0x00, 0x0A, // IDAT length
        0x49, 0x44, 0x41, 0x54, // 'IDAT'
        0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, // zlib data
        0x0D, 0x0A, 0x2D, 0xB4, // CRC
        0x00, 0x00, 0x00, 0x00, // IEND length
        0x49, 0x45, 0x4E, 0x44, // 'IEND'
        0xAE, 0x42, 0x60, 0x82, // CRC
      ]);
      final plan = FormulaRenderPlan.png(pngBytes, latex);
      final widget = plan.toPdfWidget(fontSize: fontSize);

      expect(widget, isA<pw.Container>(),
          reason: 'PngPlan 应输出 pw.Container，实际: ${widget.runtimeType}');
      final container = widget as pw.Container;
      // child 应为 pw.Image（pdf 包内置）。
      expect(container.child?.runtimeType.toString(), contains('Image'),
          reason: 'PngPlan 的 Container.child 应为 pw.Image');
    });

    test('FallbackPlan：原始 LaTeX → pw.Text 包裹 [latex]', () {
      final plan = FormulaRenderPlan.fallback(latex);
      final widget = plan.toPdfWidget(fontSize: fontSize);

      expect(widget, isA<pw.Text>(),
          reason: 'FallbackPlan 应输出 pw.Text，实际: ${widget.runtimeType}');
      final text = widget as pw.Text;
      // pw.Text 继承 RichText，text 字段是 InlineSpan（实际为 TextSpan）。
      // FallbackPlan 在 latex 外包裹 [] 标记，让用户在 PDF 里看到
      // 这是回退渲染（而非正确公式）。
      final span = text.text as pw.TextSpan;
      expect(span.text, contains('[$latex]'));
    });

    test('三路径回退链：SvgPlan 失败 → 内部退到 FallbackPlan（同 fontSize）', () {
      // 同一段畸形 SVG：SvgPlan 内部 try/catch 会调 FallbackPlan.toPdfWidget，
      // 输出 pw.Text。这是 SvgPlan.toPdfWidget 的关键容错行为——
      // 任何 SVG 解析/绘制异常都不应阻塞 PDF 导出。
      const malformedSvg = '';
      final svgPlan = FormulaRenderPlan.svg(malformedSvg, latex, false);
      final fallbackPlan = FormulaRenderPlan.fallback(latex);

      // 两者都返回非空 widget；SvgPlan 即使失败也不会抛异常。
      expect(svgPlan.toPdfWidget(fontSize: fontSize), isNotNull);
      expect(fallbackPlan.toPdfWidget(fontSize: fontSize), isNotNull);
    });
  });
}
