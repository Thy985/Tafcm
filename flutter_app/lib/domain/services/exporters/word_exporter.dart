/// Markdown → Word (.docx) 导出器。
///
/// 把 Markdown 文档打包为符合 ECMA-376 规范的 .docx 文件：
///   - document.xml（body 内容）由 [WordOoxmlBuilder] 拼装
///   - styles.xml / settings.xml / numbering.xml 取自 [WordOoxmlTemplates]
///   - 公式渲染为 PNG 图片（FormulaPdfRenderer cache）并通过 rIdImageN 引用
///   - Mermaid 图表渲染为 SVG 并通过 rIdMermaidN 引用
///
/// public API：仅 [WordExporter.export] 一个静态方法。
library;

import 'dart:convert' show utf8;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import '../../../core/parser/markdown_parser.dart';
import '../../../core/services/formula_pdf_renderer.dart';
import '../../../core/services/formula_svg_service.dart';
import '../../../core/services/mermaid_service.dart';
import '../../../data/models/document.dart';
import '../export_cancel_token.dart';
import '../export_service.dart' show ExportException, ExportProgress, ExportStage, ExportProgressCallback;
import 'word_ooxml_builder.dart';
import '../word_ooxml_templates.dart';

/// Mermaid 代码 → SVG 的渲染函数签名。默认实现为
/// [MermaidService.renderToSvg]；测试可注入 fake（AGENTS.md §1.3 显式依赖）。
typedef MermaidSvgRenderer = Future<String> Function(String code);

class WordExporter {
  WordExporter._();

  /// 入口：把 Markdown 文本导出为 docx 字节流。
  ///
  /// [onProgress]（3.4.4 Slice 7）：阶段切换 + 公式/图片资源预渲染每项完成时回调。
  /// [cancelToken]（issue #323）：协作式取消令牌，在阶段边界检查。
  static Future<Uint8List> export(
    String markdown, {
    String? title,
    bool isDark = false,
    ExportProgressCallback? onProgress,
    MermaidSvgRenderer? renderMermaid,
    ExportCancelToken? cancelToken,
  }) async {
    if (markdown.isEmpty) {
      throw ExportException('Cannot export empty content');
    }
    cancelToken?.throwIfCancelled();
    // PR-C：导出开始前清空 telemetry，聚合报告只含本次导出样本。
    FormulaSvgService.clearTelemetry();
    // PR-3：导出级质量计数器清零（success/timeout/error 分布）。
    FormulaSvgService.clearQualityCounters();

    // Phase 1: 解析 + 收集公式 / Mermaid 集合。
    onProgress?.call(const ExportProgress(
      stage: ExportStage.collectingFormulas,
      completed: 0,
      total: 1,
    ));

    final elements = MarkdownParser.parse(
      markdown,
      onError: (lineIndex, error, line) =>
          debugPrint('[WordExporter] parse line $lineIndex failed: $error'),
    );

    // 收集所有公式（paragraph / list / table cell / blockquote）。
    // #326：allFormulas 记录 (latex, displayMode)，formulaRels 按复合 key
    // （`B:`/`I:` 前缀，见 formulaRelKey）索引——同一段 latex 行内与块级
    // 各占一个 rel + media 文件，不再共用同一张 PNG。
    final allFormulas = <({String latex, bool displayMode})>[];
    final formulaRels = <String, FormulaImageInfo>{};
    final allMermaids = <String>[];
    final mermaidRels = <String, MermaidImageInfo>{};

    for (final e in elements) {
      _collectFormulas(e, allFormulas, formulaRels);
      _collectMermaids(e, allMermaids, mermaidRels);
    }

    // 报告 Phase 2 开始；total = 公式数 + Mermaid 数。
    final phase2Total = allFormulas.length + allMermaids.length;
    var phase2Done = 0;
    onProgress?.call(ExportProgress(
      stage: ExportStage.preRenderingFormulaSvg,
      completed: phase2Done,
      total: phase2Total,
    ));

    if (allFormulas.isNotEmpty) {
      // Word 导出走独立的 cache key 维度，避免与 PDF 像素密度不同导致的互相覆盖。
      // #326：按 displayMode 分两批预渲染（行内 false / 块级 true），缓存 key
      // 含 displayMode 维度，与下方 cachedBytes 查询严格对齐。phase2Done 贯穿
      // 公式→Mermaid 两阶段（inline 数 → +block 数 → +mermaid 数），total 用
      // phase2Total（公式+Mermaid 总数），保持进度不回退。
      final inline = allFormulas
          .where((r) => !r.displayMode)
          .map((r) => r.latex)
          .toSet();
      final block = allFormulas
          .where((r) => r.displayMode)
          .map((r) => r.latex)
          .toSet();
      cancelToken?.throwIfCancelled();
      if (inline.isNotEmpty) {
        await FormulaPdfRenderer.preRenderAll(
          inline,
          fontSize: 16,
          isDark: isDark,
          format: FormulaPdfRenderer.formatWord,
          displayMode: false,
          // 3.4.4 Slice 7：逐公式完成回调，更新 Pre-render 进度。
          onEachCompleted: (completed, total) {
            phase2Done = completed;
            onProgress?.call(ExportProgress(
              stage: ExportStage.preRenderingFormulaSvg,
              completed: phase2Done,
              total: phase2Total,
            ));
          },
        );
      }
      cancelToken?.throwIfCancelled();
      if (block.isNotEmpty) {
        await FormulaPdfRenderer.preRenderAll(
          block,
          fontSize: 16,
          isDark: isDark,
          format: FormulaPdfRenderer.formatWord,
          displayMode: true,
          onEachCompleted: (completed, total) {
            // 与 inline 批口径一致：回调先把 phase2Done 同步到当前完成数，
            // 否则 Mermaid 阶段从旧值 ++，进度曲线先跳再回退（review P1）。
            phase2Done = inline.length + completed;
            onProgress?.call(ExportProgress(
              stage: ExportStage.preRenderingFormulaSvg,
              completed: phase2Done,
              total: phase2Total,
            ));
          },
        );
        phase2Done = inline.length + block.length;
      }
    }

    // 渲染 Mermaid 为 SVG。
    // #250：一次性并发派发全部图表，由 MermaidService 内部并发池
    //（max 4）限流。旧实现逐条 `await`，把共享 WebView 池退化为
    // 严格串行（N × 单图时间），是 Word 大文档导出慢的根因之一。
    cancelToken?.throwIfCancelled();
    if (allMermaids.isNotEmpty) {
      final renderer = renderMermaid ?? MermaidService.renderToSvg;
      await Future.wait(
        allMermaids.map((code) async {
          try {
            final svg = await renderer(code);
            final info = mermaidRels[code];
            if (info != null) {
              mermaidRels[code] = MermaidImageInfo(
                relId: info.relId,
                svg: svg,
              );
            }
          } catch (e) {
            debugPrint('Mermaid SVG render failed for Word: $e');
          }
          phase2Done++;
          onProgress?.call(ExportProgress(
            stage: ExportStage.preRenderingFormulaSvg,
            completed: phase2Done,
            total: phase2Total,
          ));
        }),
        eagerError: false,
      );
    }

    // Phase 3: 计算每个公式图片的实际尺寸并更新 formulaRels —— 仍归入
    // renderingBlocks（Word 不便按 block 颗粒度报告，归为"块后处理"）。
    onProgress?.call(const ExportProgress(
      stage: ExportStage.renderingBlocks,
      completed: 0,
      total: 1,
    ));
    for (final formula in allFormulas) {
      final bytes = FormulaPdfRenderer.cachedBytes(
        formula.latex,
        fontSize: 16,
        isDark: isDark,
        format: FormulaPdfRenderer.formatWord,
        displayMode: formula.displayMode,
      );
      if (bytes != null) {
        final dims = parsePngDimensions(bytes);
        if (dims != null) {
          final key = formulaRelKey(formula.displayMode, formula.latex);
          final info = formulaRels[key];
          if (info != null) {
            formulaRels[key] = FormulaImageInfo(
              relId: info.relId,
              widthEmu: dims.width * 9525,
              heightEmu: dims.height * 9525,
            );
          }
        }
      }
    }
    onProgress?.call(const ExportProgress(
      stage: ExportStage.renderingBlocks,
      completed: 1,
      total: 1,
    ));

    final docXml = WordOoxmlBuilder.buildDocumentXml(
      elements, title, formulaRels, mermaidRels);
    final imageRelsXml =
        WordOoxmlBuilder.buildImageRelsXml(formulaRels, mermaidRels);

    // [Content_Types].xml 现在包含 styles/settings/numbering 的 Override，
    // 见 WordOoxmlTemplates.contentTypesXml。
    const contentTypesXml = WordOoxmlTemplates.contentTypesXml;
    const rootRelsXml = WordOoxmlTemplates.rootRelsXml;

    // Phase 4: 拼装/归档为 zip 字节流。
    // issue #323：拼装前取消检查点——取消时不产出任何字节/临时文件。
    cancelToken?.throwIfCancelled();
    onProgress?.call(const ExportProgress(
      stage: ExportStage.assembling,
      completed: 0,
      total: 1,
    ));
    final archive = Archive();

    // 注意：ArchiveFile 写入 String content 时实际产生的是 utf8 字节流，
    // 但 `size` 字段如果传 `String.length`（UTF-16 code units），非 ASCII 字符
    // （中文/特殊符号）越多，header 里 uncompSize 与实际字节数偏差越大
    // （差值 = 多字节字符数 × 2）。严格 zip 读取器（Python zipfile 等）会因此
    // 报 `Bad CRC-32` 拒绝打开。下面统一用 `utf8.encode(...)` 把 String 转
    // 成 Uint8List，让 size 与 content 走同一份字节数，避免该规范违例。
    final contentTypesBytes = utf8.encode(contentTypesXml);
    final rootRelsBytes = utf8.encode(rootRelsXml);
    final docBytes = utf8.encode(docXml);
    final imageRelsBytes = utf8.encode(imageRelsXml);

    archive.addFile(ArchiveFile(
        '[Content_Types].xml', contentTypesBytes.length, contentTypesBytes));
    archive.addFile(
        ArchiveFile('_rels/.rels', rootRelsBytes.length, rootRelsBytes));
    archive.addFile(ArchiveFile(
        'word/document.xml', docBytes.length, docBytes));
    archive.addFile(ArchiveFile('word/_rels/document.xml.rels',
        imageRelsBytes.length, imageRelsBytes));

    // 补全 OOXML 必需 Part：styles / settings / numbering。
    // 这些文件让导出的 docx 在 Word/WPS/LibreOffice 中能识别 pStyle 和 numId。
    const stylesXml = WordOoxmlTemplates.stylesXml;
    const settingsXml = WordOoxmlTemplates.settingsXml;
    const numberingXml = WordOoxmlTemplates.numberingXml;
    final stylesBytes = utf8.encode(stylesXml);
    final settingsBytes = utf8.encode(settingsXml);
    final numberingBytes = utf8.encode(numberingXml);
    archive.addFile(ArchiveFile(
        'word/styles.xml', stylesBytes.length, stylesBytes));
    archive.addFile(ArchiveFile(
        'word/settings.xml', settingsBytes.length, settingsBytes));
    archive.addFile(ArchiveFile(
        'word/numbering.xml', numberingBytes.length, numberingBytes));

    int i = 0;
    for (final formula in allFormulas) {
      i++;
      final bytes = FormulaPdfRenderer.cachedBytes(
        formula.latex,
        fontSize: 16,
        isDark: isDark,
        format: FormulaPdfRenderer.formatWord,
        displayMode: formula.displayMode,
      );
      if (bytes != null) {
        final name = 'word/media/formula_$i.png';
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }
    }

    // 添加 Mermaid SVG 文件
    i = 0;
    for (final code in allMermaids) {
      i++;
      final info = mermaidRels[code];
      if (info != null && info.svg != null) {
        final name = 'word/media/mermaid_$i.svg';
        // 同样要 utf8.encode，避免 SVG 里的非 ASCII 字符引发 zip header
        // uncompSize 偏差。
        final svgBytes = utf8.encode(info.svg!);
        archive.addFile(ArchiveFile(name, svgBytes.length, svgBytes));
      }
    }

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw ExportException('Failed to encode Word document');
    }
    // 不在导出末尾清理缓存——重复导出同一文档应能命中缓存。
    // 缓存在 editor_screen 退出 / app pause 时由调用方清理。
    onProgress?.call(const ExportProgress(
      stage: ExportStage.assembling,
      completed: 1,
      total: 1,
    ));
    // PR-C：导出结束输出 telemetry 聚合报告（logcat grep FormulaTelemetry）。
    debugPrint(FormulaSvgService.telemetrySummary());
    // PR-3：导出质量报告（进度与质量分离——logcat grep FormulaQuality）。
    debugPrint(FormulaSvgService.qualitySummary());
    return Uint8List.fromList(encoded);
  }

  // --- 公式 / Mermaid 收集 ---

  static void _collectFormulas(
    DocumentElement element,
    List<({String latex, bool displayMode})> allFormulas,
    Map<String, FormulaImageInfo> formulaRels,
  ) {
    void register(String latex, bool displayMode) {
      final key = formulaRelKey(displayMode, latex);
      if (formulaRels.containsKey(key)) return;
      final idx = allFormulas.length + 1;
      allFormulas.add((latex: latex, displayMode: displayMode));
      formulaRels[key] = FormulaImageInfo(
        relId: 'rIdImage$idx',
        widthEmu: 0,
        heightEmu: 0,
      );
    }

    void walkInline(List<InlineElement> children) {
      for (final c in children) {
        if (c is FormulaElement) register(c.latex, c.displayMode);
      }
    }

    // ADR-0029 嵌套列表：ListElement.nested 可任意深度递归，
    // 不遍历则深层列表项内公式漏收集 → cachedBytes miss（review round-3）。
    void walkList(ListElement list) {
      walkInline(list.children);
      for (final n in list.nested) {
        walkList(n);
      }
    }

    if (element is ParagraphElement) {
      walkInline(element.children);
    } else if (element is ListElement) {
      walkList(element);
    } else if (element is TableElement) {
      // #326：与 PdfExporter.collectAllFormulas 同口径覆盖 table headers + cells，
      // 不再依赖 set 兜底（原 set 丢失 displayMode 维度）。
      for (final h in element.headers) {
        walkInline(h);
      }
      for (final row in element.rows) {
        for (final cell in row) {
          walkInline(cell);
        }
      }
    } else if (element is BlockquoteElement) {
      walkInline(element.children);
    } else if (element is HeadingElement) {
      // review P2：标题 inline AST 内可含公式，不收集则 cachedBytes miss →
      // Word 导出文本 fallback。
      walkInline(element.children);
    } else if (element is TaskListItemElement) {
      walkInline(element.children);
    }
  }

  static void _collectMermaids(
    DocumentElement element,
    List<String> allMermaids,
    Map<String, MermaidImageInfo> mermaidRels,
  ) {
    int register(String code) {
      if (mermaidRels.containsKey(code)) return 0;
      final idx = allMermaids.length + 1;
      allMermaids.add(code);
      mermaidRels[code] = MermaidImageInfo(relId: 'rIdMermaid$idx', svg: null);
      return idx;
    }

    if (element is MermaidElement) {
      register(element.code);
    }
  }
}
