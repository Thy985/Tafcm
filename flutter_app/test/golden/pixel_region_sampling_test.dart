/// U10 Pixel Region Sampling 试点（TEST-SYSTEM-UPGRADE-PLAN §4.3）。
///
/// 学 vgpu "pixel readback"实践：不满足于 golden 整图 diff（只能说
/// "长得不像"），对**关键区域**直接采样像素值做数值断言——
/// - L2 语义断言：公式区"非空白"（有墨迹）
/// - 主题背景色值命中 token 定义（dark/sepia 切换后背景真的变了）
///
/// 与 golden 的分工：golden 证明"视觉无非预期变化"；本测试证明
/// "该有内容的地方确实有内容、该变的颜色确实变了"——二者互补。
/// 本测试**不比对基线**，跨平台确定性可跑（固定字体 + 固定 viewport）。
///
/// 注意（AGENTS.md §11.3）：testWidgets 默认已创建 SemanticsHandle，
/// 不重复 ensureSemantics。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/editor/editor_scope.dart';
import 'package:tafcm/presentation/editor/editor_shell.dart' show EditorViewport;
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'package:tafcm/presentation/widgets/formula_renderer.dart';
import 'golden_helpers.dart';

/// 截取当前帧全图（RepaintBoundary 包裹的固定 viewport），返回 RGBA 字节
/// 与图像宽高。调用方负责 dispose 返回的 image？——此处已 dispose，
/// 仅返回 (bytes, width, height) 三元组。
Future<(Uint8List, int, int)> _captureFrame(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_frameKey),
  );
  late final ui.Image image;
  late final ByteData? byteData;
  await tester.runAsync(() async {
    image = await boundary.toImage(pixelRatio: 1.0);
    byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  });
  final width = image.width;
  final height = image.height;
  image.dispose();
  expect(byteData, isNotNull, reason: '帧像素读取失败');
  return (
    byteData!.buffer.asUint8List(),
    width,
    height,
  );
}

const _frameKey = Key('u10-frame');

/// 在固定环境 + 全屏 RepaintBoundary(key=_frameKey) 下渲染编辑器视口。
///
/// 复刻 pumpGoldenApp 的固定项（locale / textScaleFactor / viewport / 字体），
/// 但外层包 RepaintBoundary 以支持像素级读回（golden_helpers 无此能力，
/// U10 专用；若日后 golden 也要采样可上移到 helpers）。
Future<void> _pumpProbed(
  WidgetTester tester,
  EditorCoordinator coordinator, {
  ThemeData? theme,
  Size size = const Size(800, 1200),
  double textScaleFactor = 1.0,
}) async {
  final effectiveTheme = theme ?? AppTheme.lightTheme;
  tester.platformDispatcher
    ..localeTestValue = const Locale('en', 'US')
    // 与 golden_helpers 基线环境保持同一 API（混用 textScaler 会造成
    // 基线环境漂移）；deprecated 告警在 helpers 处统一豁免，此处对齐。
    // ignore: deprecated_member_use
    ..textScaleFactorTestValue = textScaleFactor;

  // workspace.dart 会对 blockKeys 做 putIfAbsent → 必须可变 map
  //（EditorShell 用字段持有；本 helper 每次调用新建即可）。
  final blockKeys = <BlockId, GlobalKey>{};

  // 固定物理 surface（默认 800×600 会裁掉 1200 高的布局）。
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    // RepaintBoundary 必须包住 MaterialApp：Scaffold 背景由 Material
    // 祖先绘制，若在边界外，截帧全透明（alpha=0），采样失真。
    RepaintBoundary(
      key: _frameKey,
      child: MaterialApp(
        theme: effectiveTheme,
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: EditorScope(
              coordinator: coordinator,
              child: AnimatedBuilder(
                animation: coordinator,
                builder: (context, _) => EditorViewport(
                  coordinator: coordinator,
                  blockKeys: blockKeys,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 统计 [region]（帧坐标）内与 [background] 不同的像素占比。
///
/// "墨迹"判定：任一通道差 > 8（抗锯齿容忍）。返回 [0.0, 1.0]。
Future<double> _inkRatio(
  WidgetTester tester,
  Rect region,
  Color background,
) async {
  final (data, width, height) = await _captureFrame(tester);
  final left = region.left.floor().clamp(0, width - 1);
  final top = region.top.floor().clamp(0, height - 1);
  final right = region.right.ceil().clamp(0, width);
  final bottom = region.bottom.ceil().clamp(0, height);

  // wide-gamut 安全取 0-255 通道值（Color.red 已 deprecated）。
  int ch(double v) => (v * 255.0).round().clamp(0, 255);
  final bgR = ch(background.r), bgG = ch(background.g), bgB = ch(background.b);
  var inkPixels = 0;
  var totalPixels = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final offset = (y * width + x) * 4;
      final r = data[offset], g = data[offset + 1], b = data[offset + 2];
      totalPixels++;
      if ((r - bgR).abs() > 8 ||
          (g - bgG).abs() > 8 ||
          (b - bgB).abs() > 8) {
        inkPixels++;
      }
    }
  }
  return totalPixels == 0 ? 0.0 : inkPixels / totalPixels;
}

void main() {
  setUpAll(() async {
    await setUpGoldenFonts();
  });

  group('U10-1 公式区非空白（数值断言先于视觉判断）', () {
    testWidgets('light 主题：公式块区域必须有墨迹（SVG 降级 serif italic）',
        (tester) async {
      final editor = InMemoryDocumentEditor(title: 'u10-pixel-probe');
      editor
        ..insertBlock(
            0,
            const HeadingElement(
                level: 2, children: [TextElement('Probe')]))
        ..insertBlock(
          1,
          const ParagraphElement(
              children: [FormulaElement(latex: r'E = mc^2', displayMode: true)]),
        );
      final coordinator = EditorCoordinator(
        editor: editor,
        history: EditorHistory(maxHistorySize: 50),
      );

      await _pumpProbed(tester, coordinator);

      // 用 finder 定位公式 widget 的真实 Rect（降级路径也会渲染
      // FormulaRenderer fallback 文本），替代硬编码探测带猜位置。
      final formulaRect = tester.getRect(find.byType(FormulaRenderer).first);
      final ratio =
          await _inkRatio(tester, formulaRect, AppTheme.backgroundSecondary);

      expect(ratio, greaterThan(0.01),
          reason: '公式区墨迹占比 $ratio 过低——公式渲染疑似空白（降级/丢失）');
      // 近乎全墨（>0.9，渲染炸成色块）同样异常。
      expect(ratio, lessThan(0.9),
          reason: '公式区墨迹占比 $ratio 异常偏高——疑似渲染溢出/色块');
    });

    testWidgets('对照实验：空白段落同区域墨迹占比应接近 0', (tester) async {
      final editor = InMemoryDocumentEditor(title: 'u10-empty-control');
      editor.insertBlock(
          0, const ParagraphElement(children: [TextElement('')]));
      final coordinator = EditorCoordinator(
        editor: editor,
        history: EditorHistory(maxHistorySize: 50),
      );

      await _pumpProbed(tester, coordinator);

      const probeRegion = Rect.fromLTWH(100, 160, 600, 120);
      final ratio =
          await _inkRatio(tester, probeRegion, AppTheme.backgroundSecondary);
      expect(ratio, lessThan(0.05),
          reason: '空白对照区墨迹占比 $ratio——采样器基线应接近 0');
    });
  });

  group('U10-2 主题背景 token 断言', () {
    // 三主题 Scaffold 背景色（app_theme.dart 实测，非猜值）：
    // light backgroundSecondary #FAFAF7 / dark #0F1419 / sepia #F8F0E0。
    testWidgets('三主题下背景像素值命中各自 token', (tester) async {
      final cases = <(ThemeData, Color, String)>[
        (AppTheme.lightTheme, const Color(0xFFFAFAF7), 'light'),
        (AppTheme.darkTheme, const Color(0xFF0F1419), 'dark'),
        (AppTheme.sepiaTheme, const Color(0xFFF8F0E0), 'sepia'),
      ];

      for (final (theme, expectedBg, label) in cases) {
        final editor = InMemoryDocumentEditor(title: 'u10-theme-$label');
        editor.insertBlock(
            0, const ParagraphElement(children: [TextElement('theme probe')]));
        final coordinator = EditorCoordinator(
          editor: editor,
          history: EditorHistory(maxHistorySize: 50),
        );

        await _pumpProbed(tester, coordinator, theme: theme);

        // 采右下角空白区（避开正文墨迹）验证背景色。
        const probeRegion = Rect.fromLTWH(700, 1100, 60, 40);
        final ratio = await _inkRatio(tester, probeRegion, expectedBg);
        expect(ratio, lessThan(0.05),
            reason: '$label 主题：角落区域与 token 背景色不符'
                '（非背景像素占 $ratio）——背景 token 或主题接线回归');
      }
    });
  });
}
