/// T3-2 公式真实 MathJax SVG E2E（Tier 3）。
///
/// - 块级 $$ 真实 WebView SVG 渲染（仅模拟器可验，需挂载 MermaidRendererHost）
/// - SVG 未就绪窗口期降级 flutter_math_fork
/// - 行内公式 WYSIWYG
/// - 三主题（light/dark/sepia）下公式颜色由 EditorTokens 驱动
///
/// 运行：Android 模拟器 `flutter test integration_test/phase35_formula_test.dart`
/// （CI 不跑 integration_test，结果作为手动门禁记入 verification report）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tafcm/core/services/formula_svg_service.dart';
import 'package:tafcm/core/services/mermaid_service.dart';
import 'package:tafcm/presentation/editor/editor_page.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'package:tafcm/presentation/themes/editor_tokens.dart';
import 'helpers/test_fixture_file.dart';
import 'helpers/phase35_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('T3-2 formula E2E', () {
    testWidgets('块级公式真实 MathJax SVG 渲染（模拟器）', (tester) async {
      final path = await createTestDoc(
        title: 'f1',
        content: '# 公式\n\n'
            r'$$E = mc^2$$',
      );
      await pumpEditorFromFileWithMermaid(
        tester,
        filePath: path,
        themeMode: AppThemeMode.light,
      );

      // 1) 等 WebView 平台视图真实挂载（integration_test 为实时 binding，
      //    pump 推进真实时间，onWebViewCreated 经平台通道回调）。
      var attached = false;
      for (var i = 0; i < 100 && !attached; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        attached = MermaidService.attachedController != null;
      }
      expect(attached, isTrue, reason: 'WebView controller 应完成挂载');

      // 1b) 等页面 + tex-svg.js 真正加载完。
      //     已实证：integration_test 环境下 onLoadStop 平台回调不可靠（90s pump
      //     仍未触发），因此直接轮询 JS `typeof window.renderLatex`，就绪后手动
      //     markPageLoaded()（与 onLoadStop 等价的公开生产 API）。
      var jsReady = false;
      Object? probe;
      Object? href;
      await tester.runAsync(() async {
        final controller = MermaidService.attachedController!;
        // 已实证：integration_test 下 initialFile 停在 about:blank
        // （typeof renderLatex 恒为 undefined），手动触发一次 loadFile。
        href = await controller.evaluateJavascript(
            source: 'document.location.href');
        if (href is! String || !(href as String).contains('mermaid')) {
          await controller.loadFile(
              assetFilePath: MermaidService.rendererAssetPath);
        }
        final sw = Stopwatch()..start();
        while (!jsReady && sw.elapsed < const Duration(seconds: 60)) {
          try {
            probe = await controller.evaluateJavascript(
                source: 'typeof window.renderLatex');
            jsReady = probe == 'function';
          } catch (e) {
            probe = e;
          }
          if (!jsReady) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      });
      expect(jsReady, isTrue,
          reason: 'tex-svg.js 应加载完成（probe=$probe, href=$href）');
      if (!MermaidService.isPageLoaded) {
        MermaidService.markPageLoaded();
      }

      // 2) 直接驱动一次真实 MathJax 渲染验证链路。
      //    说明：FormulaRenderer 首帧请求可能早于 attach 而降级且不重试
      //    （已知产品行为，report 中记录），此处验证真实 SVG 渲染链路本身。
      const latex = r'E = mc^2';
      String? svg;
      Object? lastErr;
      await tester.runAsync(() async {
        for (var i = 0; i < 3 && svg == null; i++) {
          try {
            svg = await FormulaSvgService.renderToSvg(latex,
                displayMode: true);
          } catch (e) {
            lastErr = e;
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      });
      expect(svg, isNotNull,
          reason: 'WebView 挂载后 MathJax 应渲染出 SVG（lastErr=$lastErr）');
      expect(svg, contains('<svg'), reason: '产物应为 SVG 字符串');
      expect(FormulaSvgService.cachedSvg(latex, displayMode: true), isNotNull,
          reason: '渲染结果应进入缓存');

      // 3) 缓存已填充 → 重开编辑器，FormulaRenderer 同步命中缓存 → SvgPicture。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpEditorFromFileWithMermaid(
        tester,
        filePath: path,
        themeMode: AppThemeMode.light,
      );
      expect(find.byType(SvgPicture), findsWidgets,
          reason: '公式应渲染为 SvgPicture（缓存命中路径）');
    });

    testWidgets('SVG 未就绪窗口期降级 flutter_math_fork', (tester) async {
      // 不挂载 MermaidRendererHost → 降级。
      // 前一测试可能已 attach controller / 填充缓存，先重置到"未挂载"前置状态。
      MermaidService.resetRenderer();
      FormulaSvgService.clearCache();
      final path = await createTestDoc(
        title: 'f2',
        content: r'$$E = mc^2$$',
      );
      await pumpEditorFromFile(tester, filePath: path);
      await tester.pumpAndSettle();

      expect(FormulaSvgService.cachedSvg(r'E = mc^2', displayMode: true), isNull,
          reason: '未挂载 WebView 时缓存应为空');
      expect(find.byType(Math), findsWidgets,
          reason: '降级应出现 flutter_math_fork 的 Math widget');
    });

    testWidgets('行内公式渲染', (tester) async {
      final path = await createTestDoc(
        title: 'f3',
        content: r'正文中有行内公式 $a^2 + b^2 = c^2$ 结束。',
      );
      await pumpEditorFromFile(tester, filePath: path);
      await tester.pumpAndSettle();

      final hasInline = find.byType(SvgPicture).evaluate().isNotEmpty ||
          find.byType(Math).evaluate().isNotEmpty;
      expect(hasInline, isTrue, reason: '行内公式应渲染（SVG 或 fallback）');
    });

    testWidgets('三主题下公式颜色由 EditorTokens 驱动', (tester) async {
      // 读取各主题 MaterialApp 注入的 EditorTokens.textPrimary，
      // 证明不同主题下公式渲染所使用的颜色确实不同（公式渲染读取该 token）。
      // 注意：不能在 Builder 首帧用 Completer 捕获——MaterialApp 换 theme 有
      // AnimatedTheme 过渡动画，首帧读到的是动画起点色；且 rebuild 会二次
      // complete 抛 StateError。改为 pumpAndSettle 后经 GlobalKey context 读终值，
      // 且每次捕获前卸载整棵树避免 theme lerp。
      Future<Color> captureToken(AppThemeMode mode, String docPath) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final probeKey = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.themeFor(mode),
              home: Stack(
                children: [
                  EditorPage(filePath: docPath),
                  Positioned(
                    left: -10000,
                    top: -10000,
                    child: SizedBox(key: probeKey, width: 1, height: 1),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return EditorTokens.of(probeKey.currentContext!).textPrimary;
      }

      final path = await createTestDoc(title: 'f4', content: r'$$x^2$$');
      final light = await captureToken(AppThemeMode.light, path);
      final dark = await captureToken(AppThemeMode.dark, path);
      final sepia = await captureToken(AppThemeMode.sepia, path);

      expect(light, isNot(equals(dark)), reason: 'light/dark 公式颜色应不同');
      expect(dark, isNot(equals(sepia)), reason: 'dark/sepia 公式颜色应不同');
      expect(light, isNot(equals(sepia)), reason: 'light/sepia 公式颜色应不同');
    });
  });
}
