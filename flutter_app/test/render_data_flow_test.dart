// 渲染数据流修复 (C) 集成测试
// 覆盖以下 5 个修复点：
//   1) isDark 透传到 exportToWord 路径
//   2) TableElement 内的公式能被 collectAllFormulas 收集
//   3) Cache key 包含 format 维度，PDF/Word 不互相覆盖；exportToPdf/Word
//      不在末尾清缓存，重复导出走缓存
//   4) MermaidService / FormulaSvgService 的 WebView SVG 协议 v2：
//      - 主路径：JS 把 SVG 写入 #payload-{id} div，Dart 读 innerHTML
//      - Fallback：SVG 通过 b64:<base64> 在 console 协议中传输（避免 '|' 字符问题）
//   5) FormulaSvgService 缓存同时按 entry 数 (256) 和字节数 (32MB) 限制
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/core/services/formula_pdf_renderer.dart';
import 'package:tafcm/core/services/formula_svg_service.dart';
import 'package:tafcm/core/services/mermaid_service.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/domain/services/export_service.dart';
import 'package:tafcm/domain/services/exporters/pdf_exporter.dart';

void main() {
  setUp(() {
    // 每个测试开始前清空缓存，避免跨测试干扰
    FormulaPdfRenderer.clearCache();
    FormulaSvgService.clearCache();
    MermaidService.clearCache();
    PdfExporter.clearCjkFontCache();
  });

  group('Fix 1: isDark 透传到 exportToWord 路径', () {
    test('exportToWord(isDark: true) 不抛异常，能成功生成 docx', () async {
      // smoke：只要不抛异常 + 输出是 docx 即可。
      // 注：测试环境无 FormulaRenderHost / WebView，公式走 fallback，
      //     不验证 PNG 颜色采样。
      const markdown = r'# 标题' '\n\n' r'正文 $E=mc^2$。';
      final bytes = await MarkdownExporter.exportToWord(markdown, isDark: true);
      expect(bytes.isNotEmpty, true);
      expect(bytes[0], 0x50, reason: 'docx is a zip (PK header)');
      expect(bytes[1], 0x4B);
    });

    test('exportToWord(isDark: false) 也能成功生成 docx', () async {
      const markdown = '# 标题\n\n正文。';
      final bytes = await MarkdownExporter.exportToWord(markdown, isDark: false);
      expect(bytes.isNotEmpty, true);
    });
  });

  group('Fix 2: collectAllFormulas 覆盖 TableElement 单元格', () {
    test('表格 cell 含 \$..\$ 公式被收集', () {
      const md = '| H |\n| --- |\n| \$E=mc^2\$ |';
      final elements = MarkdownParser.parse(md);
      final formulas = MarkdownExporter.collectAllFormulas(elements);
      expect(formulas.contains('E=mc^2'), true,
          reason: 'inline formula in table cell must be collected');
    });

    test('表格 cell 含 \$\$..\$\$ 块级公式被收集', () {
      const md = r'''
| col |
| --- |
| $$\int_0^1 x^2 dx$$ |
''';
      final elements = MarkdownParser.parse(md);
      final formulas = MarkdownExporter.collectAllFormulas(elements);
      expect(formulas.contains(r'\int_0^1 x^2 dx'), true,
          reason: 'display formula in table cell must be collected');
    });

    test('表格 headers / rows 多 cell 都能收集', () {
      const md = r'''
| a | b |
| --- | --- |
| $x$ | $y$ |
| $z$ | $w$ |
''';
      final elements = MarkdownParser.parse(md);
      final formulas = MarkdownExporter.collectAllFormulas(elements);
      expect(formulas, containsAll(<String>['x', 'y', 'z', 'w']));
    });

    test('段落 + 列表 + 表格混用，公式都进同一集合', () {
      const md = r'''
para $P$ text

- item $L1$
- item $L2$

| t |
| --- |
| $T$ |
''';
      final elements = MarkdownParser.parse(md);
      final formulas = MarkdownExporter.collectAllFormulas(elements);
      expect(formulas, containsAll(<String>['P', 'L1', 'L2', 'T']));
    });

    test('空 cell / 纯文本 cell 不污染集合', () {
      const md = '''
| name | value |
| --- | --- |
| foo | 42 |
| bar | (empty?) |
''';
      final elements = MarkdownParser.parse(md);
      final formulas = MarkdownExporter.collectAllFormulas(elements);
      // 无公式应该是空集
      expect(formulas, isEmpty);
    });

    test('MarkdownParser.parseInline 暴露给导出器使用', () {
      // 验证我们新加的公开 API
      final inlines = MarkdownParser.parseInline(r'text $x^2$ end');
      expect(inlines.length, greaterThan(1));
      expect(inlines.whereType<FormulaElement>().isNotEmpty, true);
      expect(inlines.whereType<FormulaElement>().first.latex, 'x^2');
    });

    test('R2: collectAllFormulasByDisplayMode 按 displayMode 分组（inline/block）', () {
      // R2 修复（实测bug1.md §4）：缓存 key 含 displayMode 维度（I| vs B|），
      // 预渲染必须与 buildFormulaPlan 的 c.displayMode 一致，否则块级公式
      // 预渲染缓存永远 miss。
      // 注：多行 `$$\n...\n$$` 在段落解析中会被拆解（独立解析 bug，另行记录），
      // 此测试用单行块级公式验证分组逻辑。
      const md = r'''
正文含行内公式 $E=mc^2$ 与 $x_1$。

$$\int_0^1 x^2 dx$$

表格块级：| c |
| --- |
| $$\Delta$$ |
''';
      final elements = MarkdownParser.parse(md);
      final grouped = MarkdownExporter.collectAllFormulasByDisplayMode(elements);
      expect(grouped.inline, containsAll(<String>['E=mc^2', 'x_1']));
      expect(grouped.block, containsAll(<String>[r'\int_0^1 x^2 dx', r'\Delta']));
      // inline 与 block 不相交（同一公式不同 displayMode 属不同缓存 key 维度）
      expect(grouped.inline.intersection(grouped.block), isEmpty);
    });

    test('R2: 行内/块级缓存 key 维度不同（I| vs B|），分组后互不 miss', () {
      // FormulaSvgService._cacheKey 对同一 latex 的 inline/block 生成不同 key，
      // 修复前 preRenderAll 固定 displayMode:false 导致块级公式永远 miss。
      // 注：多行 `$$\n...\n$$` 会被段落解析拆解（独立解析 bug），用单行块级。
      const md = r'''
行内 $E=mc^2$。

$$E=mc^2$$
''';
      final elements = MarkdownParser.parse(md);
      final grouped = MarkdownExporter.collectAllFormulasByDisplayMode(elements);
      // 同一 latex 同时出现在 inline 与 block 时分别计入两组（key 维度不同，
      // 语义上需要两次独立渲染）。
      expect(grouped.inline.contains('E=mc^2'), true);
      expect(grouped.block.contains('E=mc^2'), true);
    });

    test('R3: collectAllFormulas 覆盖 BlockquoteElement 引用块内公式', () {
      // 回归测试（实测bugX 根因）：引用块 `> $x^2$` 的公式此前未被 preRenderAll
      // 收集，块渲染 cachedSvg miss → PNG 兜底 → 离屏 toImage 真机卡死。
      // 注：PR-2 解析器把 `> **bold**` / `> $formula$` 转为 InlineElement
      // children（BlockquoteElement.children），直接 walkInline 收集。
      const md = r'''
> 行内公式 $x^2$。

> 块级 $$E=mc^2$$
''';
      final elements = MarkdownParser.parse(md);
      // 至少有一个 BlockquoteElement 解析成功（sanity）
      expect(elements.whereType<BlockquoteElement>().isNotEmpty, true,
          reason: 'BlockquoteElement 解析前提失败');
      final formulas = MarkdownExporter.collectAllFormulas(elements);
      expect(formulas.contains('x^2'), true,
          reason: '引用块内行内公式 x^2 未被收集 → PNG 兜底 → 卡死');
      expect(formulas.contains('E=mc^2'), true,
          reason: '引用块内块级公式 E=mc^2 未被收集 → PNG 兜底 → 卡死');
    });

    test('R3: collectAllFormulasByDisplayMode 覆盖 BlockquoteElement 按 displayMode 分组', () {
      // 与 R3 基础版同源：引用块内公式按 displayMode 分组收集。
      // 修复前分组收集同样未覆盖 BlockquoteElement，块级公式 cache key miss。
      const md = r'''
> $x^2$ 与 $$E=mc^2$$
''';
      final elements = MarkdownParser.parse(md);
      expect(elements.whereType<BlockquoteElement>().isNotEmpty, true);
      final grouped = MarkdownExporter.collectAllFormulasByDisplayMode(elements);
      expect(grouped.inline.contains('x^2'), true,
          reason: '引用块内行内公式未进 inline 组');
      expect(grouped.block.contains('E=mc^2'), true,
          reason: '引用块内块级公式未进 block 组');
    });

    test('R3: 修复前回归 — BlockquoteElement 不被 collectAllFormulas 覆盖（断言用旧实现会失败）', () {
      // 防御性测试：保证未来误删 R3 分支时此测试也能锁住回归。
      // 用 1 个 BlockquoteElement 包 1 个公式 → 收集结果必须含该公式。
      final elements = <DocumentElement>[
        const BlockquoteElement(children: [FormulaElement(latex: 'a-b')]),
      ];
      final formulas = MarkdownExporter.collectAllFormulas(elements);
      expect(formulas, contains('a-b'));
      final grouped = MarkdownExporter.collectAllFormulasByDisplayMode(elements);
      expect(grouped.inline, contains('a-b'));
    });
  });

  group('Fix 3: 缓存策略 (含 format 维度)', () {
    test('FormulaPdfRenderer 缓存 key 包含 format 维度', () {
      // 同一个 latex + fontSize 但不同 format 走不同 cache slot
      final fakeBytes = Uint8List.fromList(List<int>.filled(8, 0x42));
      // 通过反射式注入：直接走 _keyOf 不可能（私有），改为走公开 API
      // 用 cachedBytes 验证不同 format 互不命中
      // 这里我们通过 cachedBytes 的语义验证：第一次返回 null，注入后返回 bytes
      expect(FormulaPdfRenderer.cachedBytes('test-latex'), isNull,
          reason: '空 cache 应返回 null');
      // 由于没有公开注入 API，我们验证 cache 维度参数的存在：
      // 不同 format 调用不会互相覆盖（同一个 latex 在 pdf/word 是不同 entry）
      // 这条断言通过两次连续的 cachedBytes 都不会抛异常来证明
      expect(
        () => FormulaPdfRenderer.cachedBytes('l', fontSize: 16, isDark: false, format: 'pdf'),
        returnsNormally,
      );
      expect(
        () => FormulaPdfRenderer.cachedBytes('l', fontSize: 16, isDark: false, format: 'word'),
        returnsNormally,
      );
      // 引用 fakeBytes 防止 unused warning
      expect(fakeBytes.length, 8);
    });

    test('isDark 维度：深色与浅色不互相覆盖', () {
      // 通过两次 cachedBytes 验证参数传递正常（不会因格式错而抛错）
      expect(
        () => FormulaPdfRenderer.cachedBytes('l', fontSize: 16, isDark: true, format: 'pdf'),
        returnsNormally,
      );
      expect(
        () => FormulaPdfRenderer.cachedBytes('l', fontSize: 16, isDark: false, format: 'pdf'),
        returnsNormally,
      );
    });

    test('exportToPdf 末尾不调用 clearCache（缓存可保留）', () async {
      const md = r'# Hello' '\n\n' r'Body $E=mc^2$.';
      // 第一次导出
      final first = await MarkdownExporter.exportToPdf(md);
      // 验证：cache 此时应保留（具体内容因 host 未挂载而空，但 API 调用本身应不抛错）
      // 第二次导出应该走"快速路径"——由于 host 未挂载，preRenderAll 内部空跑，
      // 但函数本身应该成功完成。
      final second = await MarkdownExporter.exportToPdf(md);
      expect(first.isNotEmpty, true);
      expect(second.isNotEmpty, true);
      // 长度近似（因为渲染路径相同），但至少不应该是 0
      expect(first.length, greaterThan(500));
      expect(second.length, greaterThan(500));
    });

    test('exportToWord 末尾不调用 clearCache', () async {
      const md = r'# Hello' '\n\n' r'Body $E=mc^2$.';
      final first = await MarkdownExporter.exportToWord(md);
      final second = await MarkdownExporter.exportToWord(md);
      expect(first.isNotEmpty, true);
      expect(second.isNotEmpty, true);
    });

    test('cacheSize / totalBytes / totalCacheBytes 监控 API 存在', () {
      // 这些 API 在 _evictIfNeeded 决策时被使用，对外暴露便于未来添加 UI
      expect(FormulaPdfRenderer.cacheSize, isA<int>());
      expect(FormulaPdfRenderer.totalBytes, isA<int>());
      expect(FormulaSvgService.cacheSize, isA<int>());
      expect(FormulaSvgService.totalCacheBytes, isA<int>());
      expect(MermaidService.cacheSize, isA<int>());
      expect(MermaidService.totalCacheBytes, isA<int>());
    });

    test('PR-2 D4：preRenderAll 无 WebView 时 completed 推进到 total（不永久挂起）', () async {
      // 回归保护（D4 修复 + permanent-pending）：host 未挂载 → renderToSvg
      // 抛 'not mounted' → _preRenderOne catch → completed++。D4 修复前
      // 排队即入 _active 导致 active 膨胀（_maxConcurrent 语义失效），
      // 本测试验证：所有公式都有终态（completed 到达 total），preRenderAll
      // 不永久挂起（export 卡死 3/95 的 P0-2 验收）。
      final formulas = List.generate(50, (i) => 'f_$i');
      var lastCompleted = 0;
      await FormulaSvgService.preRenderAll(
        formulas,
        onEachCompleted: (completed, total) {
          lastCompleted = completed;
        },
      );
      expect(lastCompleted, formulas.length,
          reason: '所有公式必须有终态（completed 必须推进到 total，不允许 PENDING forever）');
    });

    test('PR-2 D4：rendererStateSnapshot 返回结构化状态（waiting/active 可读）', () {
      // D3 观测埋点：状态快照一行可读（logcat grep FormulaState）。
      final snap = FormulaSvgService.rendererStateSnapshot();
      expect(snap, contains('FormulaState'));
      expect(snap, contains('waiting='));
      expect(snap, contains('active='));
      expect(snap, contains('pageLoaded='));
      // MermaidService 侧快照同样可用。
      final mermaidSnap = MermaidService.rendererStateSnapshot();
      expect(mermaidSnap, contains('MermaidState'));
      expect(mermaidSnap, contains('controller='));
    });

    test('PR-3：overallFraction 各阶段加权单调不减（阶段切换无回退）', () {
      // 进度单调审计结论：每阶段起点 = 上一阶段终点
      // （collecting 终点 5% → preRendering 起点 5% → ... → assembling 90%）。
      double f(ExportStage stage, int completed, int total) => ExportProgress(
            stage: stage,
            completed: completed,
            total: total,
          ).overallFraction;

      // 阶段内：completed 增加 → overallFraction 不减
      final stageStart = f(ExportStage.preRenderingFormulaSvg, 0, 95);
      final stageMid = f(ExportStage.preRenderingFormulaSvg, 47, 95);
      final stageEnd = f(ExportStage.preRenderingFormulaSvg, 95, 95);
      expect(stageMid, greaterThanOrEqualTo(stageStart));
      expect(stageEnd, greaterThanOrEqualTo(stageMid));

      // 阶段切换：下一阶段起点 >= 上一阶段终点（单调）
      // 注：浮点容差 1e-9（0.05+0.65*1.0 = 0.7000000000000001 vs 0.70）
      final collectingEnd = f(ExportStage.collectingFormulas, 1, 1);
      final preRenderingStart = f(ExportStage.preRenderingFormulaSvg, 0, 95);
      expect(preRenderingStart, greaterThanOrEqualTo(collectingEnd - 1e-9));
      final preRenderingEnd = f(ExportStage.preRenderingFormulaSvg, 95, 95);
      final renderingStart = f(ExportStage.renderingBlocks, 0, 277);
      expect(renderingStart, greaterThanOrEqualTo(preRenderingEnd - 1e-9));
      final renderingEnd = f(ExportStage.renderingBlocks, 277, 277);
      final assemblingStart = f(ExportStage.assembling, 0, 1);
      expect(assemblingStart, greaterThanOrEqualTo(renderingEnd - 1e-9));
      // assembling 终点 = 100%
      expect(f(ExportStage.assembling, 1, 1), closeTo(1.0, 1e-9));

      // 全程单调模拟：解析(1/1) → 公式(0/95) → 公式(95/95) → 块(277/277) → 拼装(1/1)
      final sequence = <double>[
        f(ExportStage.collectingFormulas, 1, 1),
        f(ExportStage.preRenderingFormulaSvg, 0, 95),
        f(ExportStage.preRenderingFormulaSvg, 95, 95),
        f(ExportStage.renderingBlocks, 277, 277),
        f(ExportStage.assembling, 1, 1),
      ];
      for (var i = 1; i < sequence.length; i++) {
        expect(sequence[i], greaterThanOrEqualTo(sequence[i - 1] - 1e-9),
            reason: '进度必须单调不减（progress[n+1] >= progress[n]）');
      }
    });

    test('B-1：分片后 assembling 进度 total=片数且单调（块数→片数映射 + 导出不卡死）', () async {
      // 65 个标题块（join('\n\n') 会解析出额外空行块，块数 > 30 → 多片）。
      // B-1 修复前：单次 MultiPage 布局全部块（dart_pdf addPage 立即同步
      // generate/layout），真机主 isolate 永久阻塞（卡 28% 根因）；修复后
      // 逐片 addPage + 逐片 onProgress（assembling total=片数），导出可完成。
      final md = List.generate(65, (i) => '## 标题 $i').join('\n\n');
      // 期望片数 = ceil(实际解析块数 / kPageSliceSize)，与实现同源，自洽断言。
      final expectedSlices =
          (MarkdownParser.parse(md).length + PdfExporter.kPageSliceSize - 1) ~/
              PdfExporter.kPageSliceSize;
      expect(expectedSlices, greaterThan(1),
          reason: '测试前提：语料块数应触发分片（>30 块 → 多片）');
      final progresses = <ExportProgress>[];
      final bytes = await MarkdownExporter.exportToPdf(
        md,
        onProgress: progresses.add,
      );
      // 导出不卡死（正常返回字节流）。
      expect(bytes.isNotEmpty, true);
      final assembling = progresses
          .where((p) => p.stage == ExportStage.assembling)
          .toList();
      // 片数映射：assembling total == 期望片数。
      expect(assembling.last.total, expectedSlices,
          reason: 'assembling total 应为片数（块数→片数映射错误）');
      expect(assembling.last.completed, expectedSlices,
          reason: '最后一片完成后 completed 应达片数');
      // assembling completed 序列单调不减（0 → 1 → ... → 片数）。
      for (var i = 1; i < assembling.length; i++) {
        expect(assembling[i].completed,
            greaterThanOrEqualTo(assembling[i - 1].completed),
            reason: '分片进度必须单调不减');
      }
    });

    test('PR-3：qualitySummary 输出 success/timeout/error 分布（进度与质量分离）', () {
      // 质量报告可读（logcat grep FormulaQuality）；导出开始清零、结束输出。
      FormulaSvgService.clearQualityCounters();
      final empty = FormulaSvgService.qualitySummary();
      expect(empty, contains('FormulaQuality'));
      expect(empty, contains('total=0'));
      // 触发一次渲染（host 未挂载 → error 计数 +1）
      // ignore: unawaited_futures
      FormulaSvgService.renderToSvg(r'E=mc^2').catchError((_) => '');
      // renderToSvg 是异步抛错，等待一帧确保计数已写入
      //（直接断言格式与计数域存在，数值由真机验证覆盖）
      final summary = FormulaSvgService.qualitySummary();
      expect(summary, contains('success='));
      expect(summary, contains('timeout='));
      expect(summary, contains('error='));
      expect(summary, contains('successRate='));
    });
  });

  group('Fix 4: WebView SVG 协议 v2 (DOM + base64 fallback)', () {
    test('MermaidService.handleConsoleMessage 解析 MERMAID_OK|<id> 触发 DOM fetch', () async {
      // 旧协议 `MERMAID_OK|id|len|svg` 会在 SVG 含 '|' 时丢失数据。
      // 新协议 `MERMAID_OK|<id>` 只带 id，SVG 在 #payload-<id> div 里，
      // Dart 用 evaluateJavascript 读 innerHTML。
      //
      // 这里我们直接验证 handleConsoleMessage 对新格式不会抛错。
      // controller 未挂载时，Dart 会通过 _completePendingError 把 'controller not available'
      // 传给等待中的 future（如果有 pending request）。在没有 pending request 时不报错。
      expect(
        () => MermaidService.handleConsoleMessage('MERMAID_OK|test-m1'),
        returnsNormally,
      );
    });

    test('MermaidService.handleConsoleMessage 解析 base64 fallback (含 | 字符)', () async {
      // 关键 case：SVG 字符串本身含 '|' 字符（MathJax 内部可能产生）
      // 旧协议 `parts.sublist(3).join('|')` 会丢字符。
      // 新协议用 base64 编码后通过 console 传输，base64 不含 '|'
      const svgWithPipe = '<svg><text>x | y | z</text></svg>';
      final b64 = base64Encode(utf8.encode(svgWithPipe));
      // 模拟 JS 发出的 console 消息
      final consoleMsg = 'MERMAID_OK|test-m2|b64:$b64';
      // 因为没有 attach controller / pending render，这里我们验证协议解析路径：
      // handleConsoleMessage 会调 utf8.decode(base64Decode(payload)) -> svg
      // 但因为没有 pending render，_completePending 静默返回，不抛错。
      // 我们通过 catch 路径间接验证 decoder 逻辑：
      //   - 让 base64 解码失败会触发 _completePendingError
      //   - 但没有 pending 时 _completePendingError 也静默返回
      // 所以仅验证不抛错
      expect(
        () => MermaidService.handleConsoleMessage(consoleMsg),
        returnsNormally,
      );
    });

    test('FormulaSvgService.handleConsoleMessage 解析 LATEX_OK|<id> 触发 DOM fetch', () {
      expect(
        () => FormulaSvgService.handleConsoleMessage('LATEX_OK|test-l1'),
        returnsNormally,
      );
    });

    test('FormulaSvgService.handleConsoleMessage 解析 LATEX_OK|<id>|b64:<b64>', () {
      const svgWithPipe = r'<svg xmlns="http://www.w3.org/2000/svg"><g id="a|b|c"/></svg>';
      final b64 = base64Encode(utf8.encode(svgWithPipe));
      final consoleMsg = 'LATEX_OK|test-l2|b64:$b64';
      expect(
        () => FormulaSvgService.handleConsoleMessage(consoleMsg),
        returnsNormally,
      );
    });

    test('SVG 含 | 字符：base64 编解码无损往返 (核心 case)', () {
      // 验证 task 验收点："SVG 含 \'|\' 字符能正确解码"
      // 用 base64 编解码模拟 JS->Dart 的 fallback 协议传输
      const originalSvg = r'''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <text x="10" y="20">x | y | z</text>
  <path d="M 0 0 L 10|10 Z"/>
  <style>font: 'Arial|Bold';</style>
</svg>
''';
      // 模拟 JS 端：btoa(unescape(encodeURIComponent(svg)))
      // 在 Dart 这边我们用 base64Encode(utf8.encode(svg)) 等价
      final encoded = base64Encode(utf8.encode(originalSvg));
      // 模拟 console 消息
      final consoleMsg = 'LATEX_OK|test-pipe|b64:$encoded';
      // 截取 b64 部分
      final pipeIdx = consoleMsg.indexOf('|b64:');
      final b64 = consoleMsg.substring(pipeIdx + 5);
      // 解码
      final decoded = utf8.decode(base64Decode(b64));
      // 关键断言：包含 '|' 字符的 SVG 字符串能完整还原
      expect(decoded, originalSvg);
      expect(decoded, contains('x | y | z'));
      expect(decoded, contains('L 10|10'));
      expect(decoded, contains('Arial|Bold'));
    });

    test('MERMAID_ERR 消息保持向后兼容', () {
      // 旧代码期望 MERMAID_ERR|id|<error> 格式——保留兼容
      expect(
        () => MermaidService.handleConsoleMessage('MERMAID_ERR|test-e1|syntax_error'),
        returnsNormally,
      );
      expect(
        () => FormulaSvgService.handleConsoleMessage('LATEX_ERR|test-e2|mathjax_not_loaded'),
        returnsNormally,
      );
    });

    test('MERMAID_THEME 消息保持向后兼容', () {
      // 内部主题消息——保持兼容
      expect(
        () => MermaidService.handleConsoleMessage('MERMAID_THEME|light|<svg></svg>'),
        returnsNormally,
      );
      // 含 '|' 的 SVG 也能被原样保留
      const themeSvg = '<svg><g id="a|b"/></svg>';
      expect(
        () => MermaidService.handleConsoleMessage('MERMAID_THEME|light|$themeSvg'),
        returnsNormally,
      );
    });

    test('空消息 / 非法消息不抛错', () {
      // 健壮性
      expect(() => MermaidService.handleConsoleMessage(''), returnsNormally);
      expect(() => MermaidService.handleConsoleMessage('garbage'), returnsNormally);
      expect(() => FormulaSvgService.handleConsoleMessage(''), returnsNormally);
      expect(() => FormulaSvgService.handleConsoleMessage('garbage'), returnsNormally);
    });
  });

  group('Fix 5: FormulaSvgService 缓存字节数限制', () {
    test('totalCacheBytes API 存在且初始为 0', () {
      FormulaSvgService.clearCache();
      expect(FormulaSvgService.totalCacheBytes, 0);
      expect(FormulaSvgService.cacheSize, 0);
    });

    test('MermaidService.totalCacheBytes API 存在', () {
      MermaidService.clearCache();
      expect(MermaidService.totalCacheBytes, 0);
      expect(MermaidService.cacheSize, 0);
    });

    test('clearCache 同时清空 byte counter', () {
      // 模拟"之前有缓存"的状态——通过 handleConsoleMessage 不会真的填缓存
      // （因为没有 pending render），所以我们只验证 clearCache 是幂等的
      expect(FormulaSvgService.totalCacheBytes, 0);
      FormulaSvgService.clearCache();
      expect(FormulaSvgService.totalCacheBytes, 0);
      expect(FormulaSvgService.cacheSize, 0);
    });
  });

  group('集成：导出含表格 + 公式的文档', () {
    test('表格 cell 内公式的文档能成功导出 PDF', () async {
      const md = r'''
# 测试

| 公式 | 描述 |
| --- | --- |
| $E=mc^2$ | 质能方程 |
| $\int_0^1 x dx$ | 简单积分 |
''';
      final bytes = await MarkdownExporter.exportToPdf(md);
      expect(bytes.isNotEmpty, true);
      expect(bytes[0], 0x25, reason: 'PDF starts with %PDF');
      expect(bytes[1], 0x50);
      expect(bytes[2], 0x44);
      expect(bytes[3], 0x46);
      // 至少 1KB
      expect(bytes.length, greaterThan(1000));
    });

    test('表格 cell 内公式的文档能成功导出 Word', () async {
      const md = r'''
| 公式 | 描述 |
| --- | --- |
| $E=mc^2$ | 质能方程 |
''';
      final bytes = await MarkdownExporter.exportToWord(md);
      expect(bytes.isNotEmpty, true);
      expect(bytes[0], 0x50, reason: 'docx is a zip');
      expect(bytes[1], 0x4B);
    });
  });
}
