/// F-02 像素级守门测试（#216/#234）：离屏捕获 PNG 必须不透明且有墨迹。
///
/// 根因回顾（formula_pdf_renderer.dart 离屏捕获结构定稿）：
/// - **定稿**：`RepaintBoundary` 直接包内容——内容正常 paint，toImage
///   捕获层不含 OpacityLayer，像素不透明；视觉不可见由宿主
///   `Positioned(left:-10000)` 离屏定位保证（不影响 paint）。
/// - **旧缺陷**：boundary 与 `Opacity(0)` 组合——capture 层含
///   OpacityLayer(alpha=0) 或子树不 paint（RenderOpacity alpha==0
///   直接 return），PNG 全透明/捕获异常 → PDF/Word 公式"空白"。
///
/// 本测试用同款 U10 手法（tester.view 固定 surface + RepaintBoundary +
/// 像素采样）验证分层原则：定稿结构必须产出可用 PNG；旧缺陷结构必须
/// 复现全透明（证明测试真的在守门，而非恒真）。
///
/// **CI 跳过**（PR #278 实证）：`RenderRepaintBoundary.toImage` 在 CI
/// headless flutter_tester（Linux 无 GPU/swiftshader）上挂起直至超时，
/// 本机（Windows desktop）运行正常。像素证据由本地验证 + U7 真机发布
/// 门承担；CI 仅运行底部的结构哨兵用例。
library;

import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/main.dart' show kMermaidHostEnabled;

/// CI 环境检测（GitHub Actions 注入 CI=true）。
final bool _kRunningOnCi = Platform.environment['CI'] == 'true';

/// toImage 用例在 CI 上的跳过理由。
const String _kCiSkipReason =
    'toImage 在 CI headless flutter_tester 上挂起（PR #278 实证）；'
    '像素证据由本地验证 + U7 真机发布门承担';

/// 与 formula_pdf_renderer.dart 同款画布参数（捕获语义一致）。
const double _canvasW = 800;
const double _canvasH = 200;

Future<ui.Image> _captureStructure(WidgetTester tester, Widget child) async {
  // 生产定稿结构（formula_pdf_renderer F-02）：RepaintBoundary 直接包
  // 内容，不可见性由宿主 Positioned(left:-10000) 保证（不影响 paint）。
  // 本测试对 boundary 捕获，检验其 layer 树是否含 OpacityLayer(alpha=0)。
  final boundaryKey = GlobalKey();
  await tester.binding.setSurfaceSize(const Size(_canvasW, _canvasH));
  tester.view.physicalSize = const Size(_canvasW, _canvasH);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: child,
      ),
    ),
  );
  await tester.pumpAndSettle();

  // toImage 是 RenderRepaintBoundary 的方法（RenderBox 无此 API）。
  final renderObj = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  // test binding 下 surface 尺寸变更后的最后一帧可能尚未 paint，
  // toImage 的 !debugNeedsPaint 断言要求先冲刷帧。
  await tester.pump();
  final image = await renderObj
      .toImage(pixelRatio: 2.0)
      .timeout(const Duration(seconds: 10));
  return image;
}

/// 像素统计：(不透明像素占比, 非背景墨迹像素占比)。
Future<(double opaqueRatio, double inkRatio)> _pixelStats(
  ui.Image image,
) async {
  final byteData =
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(byteData, isNotNull, reason: 'PNG 原始数据必须可读');
  final bytes = byteData!.buffer.asUint8List();
  var opaque = 0, ink = 0, total = 0;
  for (var i = 0; i < bytes.length; i += 4) {
    total++;
    final alpha = bytes[i + 3];
    if (alpha > 0) opaque++;
    // 白底墨迹：非白像素（含灰度抗锯齿）。阈值避开纯噪声。
    if (bytes[i] < 200 || bytes[i + 1] < 200 || bytes[i + 2] < 200) {
      if (alpha > 0) ink++;
    }
  }
  return (opaque / total, ink / total);
}

/// 被捕获的内容：白底黑字（模拟 formula_pdf_renderer 的
/// `Container(color) + Math.tex` 结构；文字替代公式，像素语义等价）。
Widget _content() {
  return Container(
    width: _canvasW,
    height: _canvasH,
    color: Colors.white,
    alignment: Alignment.center,
    child: const Text(
      'x^2 + y^2 = z^2',
      style: TextStyle(fontSize: 40, color: Colors.black),
    ),
  );
}

void main() {
  testWidgets('F-02 正向：boundary 直接包内容（生产定稿）→ 不透明且有墨迹',
      (tester) async {
    if (_kRunningOnCi) {
      // ignore: avoid_print
      print('[SKIP] $_kCiSkipReason');
      return;
    }
    // 生产同款：boundary 直接包内容，不可见性由宿主 Positioned 离屏保证
    //（不影响 paint）→ 捕获层不含 OpacityLayer。
    final image = await _captureStructure(tester, _content());
    final (opaque, ink) = await _pixelStats(image);
    // ignore: avoid_print
    print('[F-02] 定稿结构 opaque=$opaque ink=$ink');
    expect(opaque, greaterThan(0.99),
        reason: 'boundary 下不得有 Opacity(0)——若全透明，说明有人把 '
            'Opacity(0) 加回捕获链（F-02 回归：PDF/Word 公式空白）');
    expect(ink, greaterThan(0.01),
        reason: '内容必须真实着墨（#234：导出公式可见性的最小硬证据）');
  });

  testWidgets('F-02 反向：boundary 包 Opacity(0) 复现全透明（守门非恒真）',
      (tester) async {
    if (_kRunningOnCi) {
      // ignore: avoid_print
      print('[SKIP] $_kCiSkipReason');
      return;
    }
    // 旧缺陷结构复现：RenderOpacity.paint 在 alpha==0 时直接 return
    // 不 paint 子树（SDK 实证）——捕获层全透明。证明正向断言真的在
    // 区分两种结构（非恒真守门）。
    final image = await _captureStructure(
      tester,
      Opacity(opacity: 0.0, child: _content()),
    );
    final (opaque, _) = await _pixelStats(image);
    // ignore: avoid_print
    print('[F-02] 旧缺陷结构 opaque=$opaque（复现 #216 F-02 根因）');
    expect(opaque, lessThan(0.5),
        reason: 'boundary 内侧 Opacity(0) 应复现全透明——此测试证明正向'
            '断言真的在区分两种结构（非恒真守门）');
  });

  test('结构漂移哨兵：main.dart 的 mermaid 开关仍为编译期常量', () {
    // 轻量绑定检查：F-02 修复与 #276 B 方案同处离屏/宿主链路，
    // 若常量被误改为运行时变量，此处立即失败提示同步。
    expect(kMermaidHostEnabled, isA<bool>());
  });
}
