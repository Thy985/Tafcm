/// SVG 布局死循环诊断（B-2 方向）：真实路径 `parseSvgString → SvgPdfWidget
/// → pw.MultiPage → pdf.save()`，用 timeout 判定卡死点。
///
/// 背景（真机卡 28% 调查）：大语料导出卡在 Phase 4 `pdf.addPage`（第一片
/// 30 块 3.5min 永久阻塞），小文档 10 块 132ms 完成。真实路径不走
/// `pw.SvgImage`（已在 formula_render_plan.dart 绕开），走自研转换器：
/// `svg_parser.parseSvgString` → AST → `SvgPdfWidget` → pdf 底层
/// PdfGraphics API。候选死点：svg_parser 解析 / SvgPdfWidget 绘制 /
/// dart_pdf `canvas.drawShape`（path data 解析）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tafcm/core/renderers/svg_parser.dart';
import 'package:tafcm/core/renderers/svg_to_pdf.dart';

/// Case B 基线：简单 SVG（小 viewBox + 单个 rect）。
const simpleSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="50" height="20" viewBox="0 0 50 20">'
    '<rect x="0" y="0" width="10" height="10" fill="black"/>'
    '</svg>';

/// Case C 探测：MathJax 风格复杂 SVG（大 viewBox + 多层 g transform +
/// 长 path data + use 引用）。MathJax 输出特征：viewBox 宽度可达上千，
/// 多层 `<g transform="translate(...)">`，glyph 用 `<use>` 引用 `<defs>`
/// 中的 `<path>`。
const mathjaxStyleSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="1262" height="100" viewBox="0 0 1262 100">
  <defs>
    <path id="g1" d="M10 10 L20 20 L30 10 C40 30 50 5 60 20 S80 10 90 25 Q110 40 120 20 T150 30 A10 10 0 0 1 170 25 Z"/>
    <path id="g2" d="M5 5 h10 v10 h-10 Z M30 30 h20 v20 h-20 Z"/>
  </defs>
  <g transform="translate(0, 10)">
    <g transform="translate(100, 0)">
      <rect x="0" y="0" width="12" height="8" fill="currentColor"/>
      <use href="#g1"/>
      <use href="#g2"/>
    </g>
    <g transform="translate(300, 0) scale(0.8)">
      <path d="M0 0 L50 50 L100 0 C150 60 200 10 250 40 S350 20 400 60 Z"/>
      <use href="#g1" transform="translate(10, 10)"/>
    </g>
    <g transform="translate(600, 5)">
      <use href="#g2" transform="scale(1.2)"/>
      <path d="M20 20 C40 0 80 40 100 20 C120 0 160 40 180 20 C200 0 240 40 260 20 C280 0 320 40 340 20 Z"/>
    </g>
    <g transform="translate(900, 0)">
      <use href="#g1" transform="rotate(15)"/>
      <use href="#g2" transform="translate(50, 0) scale(0.5)"/>
    </g>
  </g>
</svg>
''';

/// 真实路径渲染：parseSvgString → SvgPdfWidget → MultiPage → save。
/// 埋点：svg_create / svg_parse_done / addPage_done / save_done——
/// 若卡死，最后一条日志即卡点（logcat grep svg_diag）。
Future<Uint8List> renderRealPath(String svg) async {
  debugPrint('svg_diag svg_create');
  final root = parseSvgString(svg);
  debugPrint('svg_diag svg_parse_done');
  final pdf = pw.Document();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 60, 40, 60),
      build: (_) => [
        SvgPdfWidget(root: root, fontSize: 13),
      ],
    ),
  );
  debugPrint('svg_diag addPage_done');
  final bytes = await pdf.save();
  debugPrint('svg_diag save_done');
  return bytes;
}

/// 模拟真实分片路径：一个 slice 内多个文本块 + 多个公式 SVG widget，
/// 8 阶段埋点（assemble_start / block_start / formula_start / svg_create /
/// svg_layout_start / svg_layout_done / addPage_done / slice_done）。
/// 若卡死，最后一条 svg_diag 日志即卡点（logcat grep svg_diag）。
Future<Uint8List> renderSlice({
  required int textBlockCount,
  List<String>? svgs,
}) async {
  debugPrint('svg_diag assemble_start');
  final widgets = <pw.Widget>[];
  for (var i = 0; i < textBlockCount; i++) {
    debugPrint('svg_diag block_start $i');
    widgets.add(pw.Text(
      'Block $i 内容 abc',
      style: pw.TextStyle(font: pw.Font.helvetica(), fontSize: 13),
    ));
  }
  if (svgs != null) {
    for (var i = 0; i < svgs.length; i++) {
      debugPrint('svg_diag formula_start $i');
      final root = parseSvgString(svgs[i]);
      debugPrint('svg_diag svg_create $i');
      widgets.add(SvgPdfWidget(root: root, fontSize: 13));
    }
  }
  final pdf = pw.Document();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 60, 40, 60),
      build: (_) => widgets,
    ),
  );
  debugPrint('svg_diag svg_layout_done');
  debugPrint('svg_diag addPage_done');
  final bytes = await pdf.save();
  debugPrint('svg_diag slice_done');
  return bytes;
}

void main() {
  group('SVG 布局死循环诊断（真实路径 parseSvgString → SvgPdfWidget）', () {
    test('Case B：简单 SVG 真实路径渲染（基线，应正常完成）', () async {
      final bytes = await renderRealPath(simpleSvg);
      expect(bytes.isNotEmpty, true, reason: '简单 SVG 应正常渲染');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Case C：MathJax 风格复杂 SVG 真实路径渲染（死循环探测）', () async {
      final bytes = await renderRealPath(mathjaxStyleSvg);
      expect(bytes.isNotEmpty, true,
          reason: '复杂 SVG 应正常渲染；若超时 = 自研 SVG 转换器或 '
              'dart_pdf drawShape 存在死循环（真机卡 28% 候选）');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Case A：30 个纯文本块（排除分片/addPage 本身）', () async {
      final bytes = await renderSlice(textBlockCount: 30);
      expect(bytes.isNotEmpty, true, reason: '30 个纯文本块应正常布局');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Case D：30 块 + 1 个公式 SVG（判断"只要有 SVG 就卡"）', () async {
      final bytes = await renderSlice(
        textBlockCount: 30,
        svgs: [mathjaxStyleSvg],
      );
      expect(bytes.isNotEmpty, true, reason: '30 块 + 1 公式应正常布局');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Case E：30 块 + 多个相同 SVG（判断重复布局/缓存问题）', () async {
      final bytes = await renderSlice(
        textBlockCount: 30,
        svgs: List.filled(10, mathjaxStyleSvg),
      );
      expect(bytes.isNotEmpty, true, reason: '30 块 + 10 个相同 SVG 应正常布局');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Case F：30 块 + 多个不同 SVG（判断特定 SVG 数据问题）', () async {
      // 三个变体 SVG：不同 viewBox / 层数 / path 密度。
      final v2 = mathjaxStyleSvg.replaceAll('viewBox="0 0 1262 100"',
          'viewBox="0 0 3000 300"');
      final v3 = mathjaxStyleSvg.replaceAll('width="1262"', 'width="2400"');
      final bytes = await renderSlice(
        textBlockCount: 30,
        svgs: [mathjaxStyleSvg, v2, v3],
      );
      expect(bytes.isNotEmpty, true, reason: '30 块 + 多个不同 SVG 应正常布局');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Case G：30 块 + 12 个真实公式 SVG（复现 Case E 密度，dart_pdf 多 SVG 布局探测）', () async {
      // 真机 Case E（30 块 + 12 公式）addPage 永久卡死（blocking primitive 锁定）。
      // 本测试：同密度用**真实公式 SVG fixture**（test_assets/svg_fixture/，
      // 真机 dump 的 118 个 MathJax SVG）在纯 Dart 路径布局——
      // 通过 = dart_pdf 多 SVG 布局本身不超线性，卡死是真机环境特有；
      // 超时 = dart_pdf 多 SVG 布局有可本地复现的超线性/死循环问题。
      final dir = Directory('test_assets/svg_fixture');
      final fixtures = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.svg'))
          .take(12)
          .map((f) => f.readAsStringSync())
          .toList();
      expect(fixtures.length, 12, reason: 'fixture 目录应有 >=12 个真实 SVG');
      final bytes = await renderSlice(
        textBlockCount: 30,
        svgs: fixtures,
      );
      expect(bytes.isNotEmpty, true,
          reason: '12 个真实公式 SVG 应正常布局；若超时 = dart_pdf 多 SVG '
              '布局存在可复现的超线性问题（非真机特有）');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
