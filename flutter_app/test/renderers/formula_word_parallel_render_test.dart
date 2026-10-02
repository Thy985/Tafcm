/// #250 回归守门：Word 导出公式 / Mermaid 渲染必须真并发。
///
/// 两层测试：
/// 1. [FormulaRenderHost]——队列前 4 个请求各自挂载独立、以请求 id 为
///    key 的离屏 capture（修复前只挂队首且无 key，State 复用导致第二个
///    请求起永不触发捕获，整条队列卡死）。
/// 2. [WordExporter] Mermaid 派发——一次性并发派发（修复前逐条 await，
///    把 MermaidService 内部 max-4 并发池退化为严格串行）。
///
/// 注：capture 的真实 toImage 光栅化在 headless 测试环境不完成（#250
/// 备注 needs-device-validation 同源），本文件只守门"挂载 / 派发"结构。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/services/formula_pdf_renderer.dart';
import 'package:tafcm/domain/services/exporters/word_exporter.dart';

/// 离屏 capture 的固定画布尺寸（与 formula_pdf_renderer.dart
/// _offscreenCanvasWidth/Height 一致），用于树内定位 capture widget。
Finder _offscreenCaptures() => find.byWidgetPredicate(
      (w) => w is SizedBox && w.width == 800 && w.height == 200,
      skipOffstage: false,
    );

/// 结束测试前清场：drain 队列 + 推进 fake clock 让已挂载 capture 的
/// 16ms 延迟与 5s toImage 超时 timer 全部耗尽，否则 binding 在
/// teardown 断言 "Timer is still pending"。
Future<void> settleAndDrain(WidgetTester tester) async {
  FormulaRenderHost.debugDrainQueueForTest();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 6));
  }
}

void main() {
  group('#250 FormulaRenderHost 并发槽位', () {
    // 关键测试时序：pumpWidget 与 render() 之间不可插 pump()——实测
    // 会让随后注册的 addPostFrameCallback 不被 pump 冲刷，build 不重建。
    testWidgets('6 个排队请求挂载 min(6,4)=4 个独立 capture，队首 4 个在飞',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: FormulaRenderHost(child: SizedBox.shrink()),
      ));

      final latexes = [for (var i = 0; i < 6; i++) 'a_{$i}^2'];
      for (final latex in latexes) {
        // ignore: unawaited_futures
        FormulaRenderHost.render(
          latex: latex,
          fontSize: 16,
          displayMode: false,
          isDark: false,
        );
      }
      await tester.pump();
      await tester.pump();

      expect(FormulaRenderHost.debugQueueLength(), 6);
      expect(FormulaRenderHost.debugActiveLatexes(), latexes.take(4).toList());
      expect(_offscreenCaptures().evaluate().length, 4,
          reason: 'host 必须真实挂载前 4 个请求的离屏 capture'
              '（修复前只挂队首 1 个）');

      // 每个 capture 槽位持有唯一 ValueKey——防旧实现无 key 的 State 复用错位
      final keys = tester
          .widgetList<Positioned>(find.byType(Positioned, skipOffstage: false))
          .where((w) => w.left == -10000)
          .map((w) => w.key)
          .toList();
      expect(keys.whereType<ValueKey<int>>().length, 4,
          reason: '在飞槽位必须以请求 id 为 key（identity dequeue 的前提）');

      await settleAndDrain(tester);
    });

    testWidgets('槽位数 = min(队列, 4)：2 请求 2 槽位', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: FormulaRenderHost(child: SizedBox.shrink()),
      ));
      for (var i = 0; i < 2; i++) {
        // ignore: unawaited_futures
        FormulaRenderHost.render(
          latex: 'x_$i',
          fontSize: 16,
          displayMode: false,
          isDark: false,
        );
      }
      await tester.pump();
      await tester.pump();

      expect(_offscreenCaptures().evaluate().length, 2,
          reason: '队列仅 2 个请求时槽位 = min(2,4) = 2');
      await settleAndDrain(tester);
    });
  });

  group('#250 WordExporter Mermaid 并发派发', () {
    test('多个 Mermaid 必须并发渲染（fake renderer 峰值在飞 == 请求数）',
        () async {
      const mermaidCount = 4;
      final md = List.generate(
        mermaidCount,
        (i) => '```mermaid\ngraph TD; A$i-->B$i;\n```',
      ).join('\n\n');

      var inFlight = 0;
      var peak = 0;
      final allCalled = Completer<void>();

      Future<String> fakeRenderer(String code) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        if (inFlight >= mermaidCount && !allCalled.isCompleted) {
          allCalled.complete();
        }
        // 等所有请求都进来后再放行——串行实现会卡在此处直至超时
        await allCalled.future
            .timeout(const Duration(seconds: 5), onTimeout: () {});
        await Future<void>.delayed(const Duration(milliseconds: 1));
        inFlight--;
        return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"/>';
      }

      final bytes = await WordExporter.export(
        '# t\n\n$md\n',
        renderMermaid: fakeRenderer,
      );
      expect(bytes, isNotEmpty);
      expect(peak, mermaidCount,
          reason: '调用方必须一次性派发 $mermaidCount 个 Mermaid，'
              '由 MermaidService 内部池限流；逐条 await = #250 根因');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
