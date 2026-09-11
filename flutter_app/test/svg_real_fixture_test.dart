/// 真实 SVG fixture 复现验证（B-2 方向收尾）：遍历
/// `test_assets/svg_fixture/*.svg`（真机导出 dump 的 118 个真实公式 SVG），
/// 每个用**真实路径** `parseSvgString → SvgPdfWidget → pw.MultiPage →
/// pdf.save()` 渲染，30s timeout 判定卡死。
///
/// 目的：确认「卡 28%」死循环是否由特定真实公式 SVG 内容触发（单测环境）。
/// - 全部通过 = 真实 SVG 在纯 Dart 路径不卡（死循环依赖真机环境，如
///   inappwebview / 字体 / 内存，需真机侧继续二分）
/// - 某 test 超时 = 该文件即卡死 SVG fixture（文件名 = 缓存 key，
///   可对照 FormulaLc 日志定位公式内容）
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tafcm/core/renderers/svg_parser.dart';
import 'package:tafcm/core/renderers/svg_to_pdf.dart';

void main() {
  final dir = Directory('test_assets/svg_fixture');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.svg'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  group('真实 SVG fixture 复现（卡死探测，每个文件独立超时）', () {
    for (final f in files) {
      test('${f.uri.pathSegments.last}', () async {
        final svg = f.readAsStringSync();
        final root = parseSvgString(svg);
        final pdf = pw.Document();
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            build: (_) => [SvgPdfWidget(root: root, fontSize: 13)],
          ),
        );
        final bytes = await pdf.save();
        expect(bytes.isNotEmpty, true, reason: 'SVG 渲染应完成（bytes 非空）');
      }, timeout: const Timeout(Duration(seconds: 30)));
    }
  });
}
