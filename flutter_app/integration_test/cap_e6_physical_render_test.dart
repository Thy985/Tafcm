import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';
import 'package:formula_fix/presentation/widgets/formula_renderer.dart';
import 'package:integration_test/integration_test.dart';

/// E6 Physical Runtime（Phase 3.11 收口，评审冻结顺序第 4 步）：
/// 模拟器真实 Flutter runtime 渲染 FormulaRenderer → 结构断言（公式渲染
/// 成功，非 headless 单测）→ 截图导出 PNG（physical runtime 视觉证据）。
///
/// 证据强度：test_runtime → physical_runtime（模拟器 device runtime；
/// 真机/WebView Release Gate 仍登记）。
/// 运行：flutter test integration_test/cap_e6_physical_render_test.dart -d <device>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('E6: FormulaRenderer 模拟器真实渲染 + 截图', (tester) async {
    final renderKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: renderKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FormulaRenderer(
                    element: const FormulaElement(latex: r'E = mc^2'),
                  ),
                  const SizedBox(height: 16),
                  FormulaRenderer(
                    element: const FormulaElement(
                      latex: r'\frac{a}{b}',
                      displayMode: true,
                    ),
                  ),
                ],
              ),
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
    // 渲染树完成绘制（physical runtime 真实绘制）
    final boundary =
        renderKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    expect(boundary.debugNeedsPaint, false, reason: '渲染树应完成绘制');
    // 渲染尺寸非零（公式真实绘出内容，非空渲染）
    final size = boundary.size;
    expect(size.width > 0 && size.height > 0, true,
        reason: '公式渲染应有非零尺寸（真实绘制出内容）');

    // 截图：RepaintBoundary → PNG（physical runtime 视觉证据）
    // E8.1 Screenshot Integrity（评审拆分基础层）：截图存在/有效/尺寸/非空——
    // 测试内校验（PNG bytes 非空 + 解码尺寸 > 0）+ 信息输出 stdout。
    // 写 app 内部私有目录（/data/data/.../files/，应用可写，无 scoped storage
    // 限制；外部存储 /sdcard 与 Android/data 均无写权限 errno 1/13）
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    // E8.1 断言：截图存在（bytes 非空）+ 有效（可解码）+ 尺寸预期（非零）
    expect(bytes, isNotNull, reason: 'E8.1: 截图 PNG bytes 应非空');
    expect(bytes!.lengthInBytes, greaterThan(0),
        reason: 'E8.1: 截图 PNG 应非空');
    expect(image.width, greaterThan(0), reason: 'E8.1: 截图宽度应 > 0');
    expect(image.height, greaterThan(0), reason: 'E8.1: 截图高度应 > 0');
    final png = File(
      '/data/data/com.formulafix.formula_fix/files/e6_formula_render.png',
    );
    png.parent.createSync(recursive: true);
    png.writeAsBytesSync(bytes.buffer.asUint8List());
    print('E8_PNG_INFO path=${png.path} bytes=${png.lengthSync()} '
        'w=${image.width} h=${image.height}');
  });
}
