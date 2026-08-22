import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';
import 'package:formula_fix/presentation/widgets/formula_renderer.dart';
import 'package:integration_test/integration_test.dart';

// stdout 回传是 integration_test 与 ffx adapter 之间的唯一证据通道
// （E8_PNG 块协议），非 UI 调试日志——print 为既定机制，非疏漏。
// ignore_for_file: avoid_print

/// E6 Physical Runtime（Phase 3.11 收口，评审冻结顺序第 4 步）：
/// 模拟器真实 Flutter runtime 渲染 FormulaRenderer → 结构断言（公式渲染
/// 成功，非 headless 单测）→ 截图导出 PNG（E8 视觉语义验证的 Observed 输入）。
///
/// RUN-015：每个公式单独 RepaintBoundary 截图；PNG 以 base64 分块经 stdout
/// 回传（`E8_PNG_BEGIN … E8_PNG_END` 块协议，行宽 ≤76 防止 compact reporter
/// 折行截断），latex 与截图一一对应。stdout 是唯一可靠通道——flutter test
/// 结束即卸载 app，应用私有目录文件 host 侧无法事后拉取（run-as unknown
/// package 实测）；该方案同样适用于未来真机（免 root/run-as）。
/// 证据强度：virtual_device_runtime（模拟器 device runtime；
/// 真机 physical_device_runtime Release Gate 仍登记）。
/// 运行：flutter test integration_test/cap_e6_physical_render_test.dart -d <device>

final GlobalKey _kEmc2 = GlobalKey();
final GlobalKey _kFrac = GlobalKey();

/// 截图单个 RepaintBoundary → PNG → base64 块回传（含 latex 元数据）。
Future<void> _capture(GlobalKey key, String fileName, String latex) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // pixelRatio 2.0 为实测最优（RUN-015）：动态提高分辨率反而让 OCR 模型
  // 幻觉增多（600px 目标宽下 E=mc² 被误读为长串符号）——pix2tex 内部
  // 会把超尺寸图缩回 max_dimensions，高倍采样再缩小丢失笔画锐度。
  final image = await boundary.toImage(pixelRatio: 2.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  // E8.1 断言：截图存在（bytes 非空）+ 有效 + 尺寸非零
  expect(bytes, isNotNull, reason: 'E8.1: 截图 PNG bytes 应非空');
  expect(bytes!.lengthInBytes, greaterThan(0), reason: 'E8.1: 截图 PNG 应非空');
  expect(image.width, greaterThan(0), reason: 'E8.1: 截图宽度应 > 0');
  expect(image.height, greaterThan(0), reason: 'E8.1: 截图高度应 > 0');

  final pngBytes = bytes.buffer.asUint8List();
  final b64 = base64Encode(pngBytes);

  // 块协议：每个字段一行（短行不触发 reporter 折行）；base64 按 76 字符分块。
  // host 端解析见 ffx harness adapters/formula.py 的 _parse_e6_captures。
  print('E8_PNG_BEGIN');
  print('name=$fileName');
  print('bytes=${pngBytes.length}');
  print('w=${image.width}');
  print('h=${image.height}');
  print('latex=$latex');
  print('b64_begin');
  for (var i = 0; i < b64.length; i += 76) {
    print(b64.substring(i, math.min(i + 76, b64.length)));
  }
  print('b64_end');
  print('E8_PNG_END');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('E6: FormulaRenderer 模拟器真实渲染 + 逐公式截图', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  key: _kEmc2,
                  child: FormulaRenderer(
                    element: const FormulaElement(latex: r'E = mc^2'),
                  ),
                ),
                const SizedBox(height: 16),
                RepaintBoundary(
                  key: _kFrac,
                  child: FormulaRenderer(
                    element: const FormulaElement(
                      latex: r'\frac{a}{b}',
                      displayMode: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 结构断言：公式渲染成功（physical runtime 真实绘制，非 headless 单测）
    // 注意：公式经 WebView/SVG/flutter_math_fork 渲染为图形——不用文本断言
    // （find.textContaining 不适用于图形公式），用渲染树完成绘制 + 尺寸非零。
    expect(find.byType(FormulaRenderer), findsNWidgets(2),
        reason: '两个公式元素都应渲染');
    for (final key in [_kEmc2, _kFrac]) {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      expect(boundary.debugNeedsPaint, false, reason: '渲染树应完成绘制');
      expect(boundary.size.width > 0 && boundary.size.height > 0, true,
          reason: '公式渲染应有非零尺寸（真实绘制出内容）');
    }

    // 截图：逐公式 RepaintBoundary → PNG base64 回传（Observed）+ latex 同步
    await _capture(_kEmc2, 'e6_formula_emc2.png', r'E = mc^2');
    await _capture(_kFrac, 'e6_formula_frac.png', r'\frac{a}{b}');
  });
}
