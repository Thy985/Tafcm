/// SVG AST → PDF 矢量绘制。
///
/// 把 `svg_parser.dart` 生成的 AST 树用 `pdf` 包的底层 `PdfGraphics` API
/// 画出来。完全绕开 `pw.SvgImage`（已知在含未配对代理对的 SVG 上抛
/// "Unexpected extension byte"），且不依赖第三方 SVG 渲染器。
///
/// 用法：
/// ```dart
/// final root = parseSvgString(svgString);
/// final widget = SvgPdfWidget(
///   root: root,
///   textFont: pw.Font.courier(),  // 来自调用方
///   textColor: PdfColors.black,
///   fallbackFont: pw.Font.courier(),
/// );
/// ```
///
/// 设计原则：
/// 1. **永不抛错**。任何不支持的元素显示为 `[unsupported: ...]` 占位文本
///    （不阻塞整份 PDF 导出）
/// 2. **路径数据直通**。`canvas.drawShape(d)` 走 `pdf` 包内部的
///    `writeSvgPathDataToPath` 解析器，只解析 `d` 字符串本身，不解析
///    XML —— 完全绕开 `XmlDocument.parse` 路径上的 utf8 边界 bug
/// 3. **可选 transform 嵌套**。`<g transform="translate(x,y)">` 通过
///    `canvas.setTransform(matrix)` 嵌套 push/pop 实现
library;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vector_math/vector_math_64.dart' show Matrix4;

import 'svg_ast.dart';
import 'svg_pdf_palette.dart';

/// 入口：把 SVG 字符串直接转成 `pw.Widget`。
///
/// 失败时（解析异常、root 为空等）会创建一个 fallback widget，
/// 显示为 `[unsupported: <reason>]` 单行文字，绝不抛错。
///
/// 字体：默认在 paint 时懒创建 Helvetica/Courier，无需调用方预先构造。
/// 可通过 [textFont] / [fallbackFont] 注入（典型场景：复用已有 CJK
/// NotoSansSC 字体）。
class SvgPdfWidget extends pw.Widget {
  SvgPdfWidget({
    required this.root,
    this.textFont,
    this.textColor,
    this.fallbackFont,
    this.unsupportedColor,
    this.fontSize,
    this.debugCountPathOps = false,
  });

  /// 已解析的 AST。
  final SvgRoot root;

  /// 是否统计本次 paint 真实绘制的矢量/墨迹操作数。
  ///
  /// Issue #234：PDF 导出"公式可见"的最小硬证据 = 内容流真的画了矢量
  /// 操作（rect/line/circle/path），而非空流或纯 unsupported 占位。
  /// pdf 包产物是 Flate 压缩流，直接 grep op 码不可靠；改为在绘制层
  /// 计数器暴露真实绘制次数（只读诊断，不改输出）。默认关闭（防副作用）。
  final bool debugCountPathOps;
  int debugPathOpsDrawn = 0;

  /// 文本节点使用的字体（pw.Font 高层 API）。为 null 时 paint 时用
  /// `pw.Font.helvetica()`。
  final pw.Font? textFont;

  /// 文本节点默认颜色。
  final PdfColor? textColor;

  /// 兜底字体（用于 unsupported 占位 / 字族查找）。为 null 时用 courier。
  final pw.Font? fallbackFont;

  /// 未支持占位文本的颜色（默认红灰色 #B00020）。
  final PdfColor? unsupportedColor;

  /// 全局字号覆写。null 时用节点自带的 fontSize。
  final double? fontSize;

  @override
  void layout(pw.Context context, pw.BoxConstraints constraints,
      {bool parentUsesSize = false}) {
    final intrinsicW = root.intrinsicWidth;
    final intrinsicH = root.intrinsicHeight;

    // SVG viewBox 原始尺寸可能高达数千 pt（MathJax 默认输出 em 单位），
    // 必须按父约束等比缩放，否则会触发 MultiPage 的 TooManyPagesException。
    //
    // 关键：Mermaid 父容器（pw.Column）通常给出 maxWidth=页宽，maxHeight=∞。
    // 仅按 width 缩放会把高瘦 SVG 撑得更高（200×1262 → 555×3250），
    // 因此需要两段缩放 + 兜底硬上限（min(intrinsicH, pageHeight)）。
    double w = intrinsicW;
    double h = intrinsicH;
    if (constraints.maxWidth != double.infinity && w > constraints.maxWidth) {
      final scale = constraints.maxWidth / w;
      w = w * scale;
      h = h * scale;
    }
    if (constraints.maxHeight != double.infinity && h > constraints.maxHeight) {
      final scale = constraints.maxHeight / h;
      w = w * scale;
      h = h * scale;
    } else if (constraints.maxHeight == double.infinity) {
      // 父约束未给硬高度（pw.Column 内部 child 的典型情况），按宽度缩放
      // 后的高度仍可能远超单页。按 A4 单页可用高度 720pt 兜底，避免
      // 触顶 MultiPage 的 TooManyPagesException。
      const double pageAvailableH = 720.0;
      if (h > pageAvailableH && h > 0) {
        final scale = pageAvailableH / h;
        w = w * scale;
        h = h * scale;
      }
    }
    // 至少留出 1pt，避免 0-height widget
    if (w <= 0) w = 1;
    if (h <= 0) h = 1;

    box = PdfRect.fromPoints(PdfPoint.zero, PdfPoint(w, h));
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    if (debugCountPathOps) debugPathOpsDrawn = 0;
    final canvas = context.canvas;
    // pw.Font.helvetica()/courier() 工厂无参；不为调用方增加 document 依赖。
    final textFontWrapper = textFont ?? pw.Font.helvetica();
    final fallbackFontWrapper = fallbackFont ?? pw.Font.courier();
    // PdfGraphics.drawString 需要底层 PdfFont（不是 widgets.dart 的 Font 包装）。
    final textPdfFont = textFontWrapper.getFont(context);
    final fallbackPdfFont = fallbackFontWrapper.getFont(context);

    // 与 layout 保持一致：按 box / intrinsic 算缩放比，应用到画布 transform。
    final intrinsicW = root.intrinsicWidth;
    final intrinsicH = root.intrinsicHeight;
    final myBox = box;
    if (myBox == null) {
      // 还没 layout 过（理论不会发生），按 intrinsic 1:1 画
      _paintNode(
          canvas, root, textPdfFont, fallbackPdfFont, context);
      return;
    }
    final scaleX = intrinsicW > 0 ? myBox.width / intrinsicW : 1.0;
    final scaleY = intrinsicH > 0 ? myBox.height / intrinsicH : 1.0;

    if (scaleX != 1.0 || scaleY != 1.0) {
      canvas.saveContext();
      canvas.setTransform(Matrix4.identity()
        ..scaleByDouble(scaleX, scaleY, 1, 1));
      _paintNode(
          canvas, root, textPdfFont, fallbackPdfFont, context);
      canvas.restoreContext();
    } else {
      _paintNode(
          canvas, root, textPdfFont, fallbackPdfFont, context);
    }
  }

  void _paintNode(PdfGraphics canvas, SvgNode node, PdfFont textFont,
      PdfFont fallbackFont, pw.Context context) {
    if (node is SvgRoot) {
      for (final child in node.children) {
        _paintNode(canvas, child, textFont, fallbackFont, context);
      }
    } else if (node is SvgGroup) {
      canvas.saveContext();
      if (node.translateX != 0 || node.translateY != 0) {
        // SVG 用户坐标系下 translate；在 PDF 坐标系里是平移。
        canvas.setTransform(
            Matrix4.identity()..translateByDouble(node.translateX, node.translateY, 0, 1));
      }
      for (final child in node.children) {
        _paintNode(canvas, child, textFont, fallbackFont, context);
      }
      canvas.restoreContext();
    } else if (node is SvgScale) {
      // MathJax 根部 `scale(1,-1)`：glyph 的 y 向下为正，需翻转才正立
      // （#216 F-01 配套）。缺少此分支时变换被静默忽略 → 字形上下镜像。
      // 注意：PDF y 轴向上，SVG scale 是用户坐标系变换，直接按矩阵
      // 语义应用（与既有 layout 的 box 缩放同为坐标系级变换）。
      canvas.saveContext();
      canvas.setTransform(Matrix4.identity()
        ..scaleByDouble(node.scaleX, node.scaleY, 1, 1));
      _paintNode(canvas, node.child, textFont, fallbackFont, context);
      canvas.restoreContext();
    } else if (node is SvgRect) {
      _drawRect(canvas, node);
    } else if (node is SvgLine) {
      _drawLine(canvas, node);
    } else if (node is SvgCircle) {
      _drawCircle(canvas, node);
    } else if (node is SvgEllipse) {
      _drawEllipse(canvas, node);
    } else if (node is SvgPath) {
      _drawPath(canvas, node, fallbackFont);
    } else if (node is SvgText) {
      _drawText(canvas, node, textFont, fallbackFont);
    } else if (node is SvgUse) {
      _drawUnsupported(canvas, fallbackFont, '<use href="${node.href}">');
    } else if (node is SvgUnsupported) {
      _drawUnsupported(canvas, fallbackFont, '<${node.elementName}>');
    }
  }

  // === 形状绘制 ===============================================

  void _drawRect(PdfGraphics canvas, SvgRect r) {
    if (r.width <= 0 || r.height <= 0) return;
    final fill = parseSvgColor(r.fill, textColor);
    final stroke = parseSvgColor(r.stroke, textColor);
    if (fill == null && stroke == null) return;
    if (debugCountPathOps) debugPathOpsDrawn++;
    canvas.saveContext();
    if (fill != null) canvas.setFillColor(fill);
    if (stroke != null) canvas.setStrokeColor(stroke);
    canvas.setLineWidth(r.strokeWidth);
    canvas.drawRect(r.x, r.y, r.width, r.height);
    _finish(canvas, fill: fill, stroke: stroke);
    canvas.restoreContext();
  }

  void _drawLine(PdfGraphics canvas, SvgLine l) {
    final stroke = parseSvgColor(l.stroke, textColor) ?? textColor ?? PdfColors.black;
    if (debugCountPathOps) debugPathOpsDrawn++;
    canvas.saveContext();
    canvas.setStrokeColor(stroke);
    canvas.setLineWidth(l.strokeWidth);
    canvas.moveTo(l.x1, l.y1);
    canvas.lineTo(l.x2, l.y2);
    canvas.strokePath();
    canvas.restoreContext();
  }

  void _drawCircle(PdfGraphics canvas, SvgCircle c) {
    if (c.r <= 0) return;
    final fill = parseSvgColor(c.fill, textColor);
    final stroke = parseSvgColor(c.stroke, textColor);
    if (fill == null && stroke == null) return;
    if (debugCountPathOps) debugPathOpsDrawn++;
    canvas.saveContext();
    if (fill != null) canvas.setFillColor(fill);
    if (stroke != null) canvas.setStrokeColor(stroke);
    canvas.setLineWidth(c.strokeWidth);
    canvas.drawEllipse(c.cx, c.cy, c.r, c.r);
    _finish(canvas, fill: fill, stroke: stroke);
    canvas.restoreContext();
  }

  void _drawEllipse(PdfGraphics canvas, SvgEllipse e) {
    if (e.rx <= 0 || e.ry <= 0) return;
    final fill = parseSvgColor(e.fill, textColor);
    final stroke = parseSvgColor(e.stroke, textColor);
    if (fill == null && stroke == null) return;
    if (debugCountPathOps) debugPathOpsDrawn++;
    canvas.saveContext();
    if (fill != null) canvas.setFillColor(fill);
    if (stroke != null) canvas.setStrokeColor(stroke);
    canvas.setLineWidth(e.strokeWidth);
    canvas.drawEllipse(e.cx, e.cy, e.rx, e.ry);
    _finish(canvas, fill: fill, stroke: stroke);
    canvas.restoreContext();
  }

  void _drawPath(PdfGraphics canvas, SvgPath p, PdfFont fallbackFont) {
    if (p.d.isEmpty) return;
    var fill = parseSvgColor(p.fill, textColor);
    final stroke = parseSvgColor(p.stroke, textColor);
    if (fill == null && stroke == null) {
      // MathJax 字形 path 常无显式 fill/stroke（<defs> 内 path 只带 d，
      // 祖先 <g fill="currentColor"> 承载着色）。原实现在此路径直接
      // return → 真实 MathJax 字形被静默丢弃 → 导出公式"空白"（#216 同类、
      // #234 要守的门）。默认到文本色/黑，确保字形真实着墨。
      fill = textColor ?? PdfColors.black;
    }
    if (debugCountPathOps) debugPathOpsDrawn++;
    canvas.saveContext();
    if (fill != null) canvas.setFillColor(fill);
    if (stroke != null) canvas.setStrokeColor(stroke);
    canvas.setLineWidth(p.strokeWidth);
    try {
      canvas.drawShape(p.d);
    } catch (_) {
      canvas.restoreContext();
      _drawUnsupported(canvas, fallbackFont, '<path>');
      return;
    }
    _finish(canvas, fill: fill, stroke: stroke);
    canvas.restoreContext();
  }

  void _finish(PdfGraphics canvas, {PdfColor? fill, PdfColor? stroke}) {
    if (fill != null && stroke != null) {
      canvas.fillAndStrokePath();
    } else if (stroke != null) {
      canvas.strokePath();
    } else {
      canvas.fillPath();
    }
  }

  // === 文本绘制 ===============================================

  void _drawText(PdfGraphics canvas, SvgText t,
      PdfFont textFont, PdfFont fallbackFont) {
    if (t.children.isNotEmpty) {
      for (final s in t.children) {
        _drawTspan(canvas, t, s, textFont, fallbackFont);
      }
      return;
    }
    if (t.text.isEmpty) return;

    final font = resolveSvgFont(t.fontFamily, textFont, fallbackFont);
    final size = fontSize ?? (t.fontSize > 0 ? t.fontSize : 12.0);
    final color = parseSvgColor(t.fill, textColor) ?? textColor;

    canvas.saveContext();
    if (color != null) {
      canvas.setFillColor(color);
    }
    try {
      canvas.drawString(font, size, t.text, t.x, t.y);
    } catch (_) {
      canvas.restoreContext();
      _drawUnsupported(canvas, fallbackFont, t.text);
      return;
    }
    canvas.restoreContext();
  }

  void _drawTspan(PdfGraphics canvas, SvgText parent, SvgTspan s,
      PdfFont textFont, PdfFont fallbackFont) {
    if (s.text.isEmpty) return;
    final font = resolveSvgFont(s.fontFamily, textFont, fallbackFont);
    final size = fontSize ?? s.fontSize ?? parent.fontSize;
    final color = parseSvgColor(s.fill, textColor) ?? parseSvgColor(parent.fill, textColor) ?? textColor;
    final x = s.x ?? parent.x;
    final y = s.y ?? parent.y;

    canvas.saveContext();
    if (color != null) {
      canvas.setFillColor(color);
    }
    try {
      canvas.drawString(font, size, s.text, x, y);
    } catch (_) {
      canvas.restoreContext();
      _drawUnsupported(canvas, fallbackFont, s.text);
      return;
    }
    canvas.restoreContext();
  }

  // === 占位文本 ===============================================

  void _drawUnsupported(PdfGraphics canvas, PdfFont fallbackFont, String detail) {
    final color = unsupportedColor ?? const PdfColor.fromInt(0xFFB00020);
    final label = '[unsupported: $detail]';
    canvas.saveContext();
    canvas.setFillColor(color);
    try {
      canvas.drawString(fallbackFont, 8, label, 4, 10);
    } catch (_) {
      // swallow — 绝不让 unsupported 占位阻塞导出
    }
    canvas.restoreContext();
  }
}
