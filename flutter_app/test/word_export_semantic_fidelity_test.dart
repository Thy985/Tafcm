/// CAP-WORD-023/024/025 语义 Fidelity（L4 Semantic Fidelity）。
///
/// 验证 WordExporter.export 生成的**真实 .docx** 中核心语义未丢：
/// 从 word/document.xml 提取语义模型（paragraph/heading/list/table/
/// formula count + text checksum），与 Markdown 源推导的期望模型对比。
///
/// 不逐 XML 节点比较，而是语义级比较（用户拿到 Word 后核心内容仍在）。
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/domain/services/exporters/pdf_exporter.dart';
import 'package:tafcm/domain/services/exporters/word_exporter.dart';
import 'package:tafcm/domain/services/exporters/word_ooxml_builder.dart';

/// 语义模型：从 document.xml 提取的计数。
class DocxSemanticModel {
  final int paragraphCount; // w:p 总数（含列表项/标题段落）
  final int headingCount; // 含 w:pStyle 且 style 名含 Heading/heading
  final int listCount; // 含 w:numPr（编号/项目符号）
  final int tableCount; // w:tbl
  final int formulaCount; // m:oMath
  final String textChecksum; // 全部 w:t 文本拼接的简单 hash
  final String allText; // 完整 w:t 拼接（用于 contains 断言）

  const DocxSemanticModel({
    required this.paragraphCount,
    required this.headingCount,
    required this.listCount,
    required this.tableCount,
    required this.formulaCount,
    required this.textChecksum,
    required this.allText,
  });

  @override
  String toString() =>
      'p=$paragraphCount h=$headingCount list=$listCount tbl=$tableCount '
      'f=$formulaCount sum=$textChecksum';
}

/// 从 document.xml 字符串提取语义模型。
DocxSemanticModel extractSemanticModel(String docXml) {
  final paragraphs = RegExp(r'<w:p(?:\s|>)').allMatches(docXml).length;
  final headings = RegExp(r'Heading|heading')
      .allMatches(docXml)
      .length;
  final lists = RegExp(r'w:numPr').allMatches(docXml).length;
  final tables = RegExp(r'<w:tbl(?:\s|>)').allMatches(docXml).length;
  final formulas = RegExp(r'm:oMath').allMatches(docXml).length;

  final texts = RegExp(r'<w:t[^>]*>([^<]*)</w:t>')
      .allMatches(docXml)
      .map((m) => m.group(1)!)
      .toList();
  final joined = texts.join('|');
  // 简单 checksum：长度 + 首个/末个 16 字符（避免超大字符串）
  final checksum = 'len=${joined.length}:${joined.substring(0, joined.length > 16 ? 16 : joined.length)}';

  return DocxSemanticModel(
    paragraphCount: paragraphs,
    headingCount: headings,
    listCount: lists,
    tableCount: tables,
    formulaCount: formulas,
    textChecksum: checksum,
    allText: joined,
  );
}

/// 导出真实 docx → 解包 → 提取语义模型。
Future<DocxSemanticModel> _semanticOf(String md) async {
  final bytes = await WordExporter.export(md, title: 'semantic');
  final archive = ZipDecoder().decodeBytes(bytes);
  final docFile = archive.files.firstWhere((f) => f.name == 'word/document.xml');
  final docXml = utf8.decode(docFile.content as List<int>);
  return extractSemanticModel(docXml);
}

void main() {
  group('CAP-WORD-023/024/025 语义 Fidelity（真实 docx）', () {
    test('CAP-WORD-023：标题 + 中文 + 列表 + 表格语义保留', () async {
      const md = '# 标题一\n\n## 标题二\n\n中文段落内容\n\n- 列表项A\n- 列表项B\n\n| 列1 | 列2 |\n|---|---|\n| 1 | 2 |';
      final model = await _semanticOf(md);

      // 标题：2 个（H1+H2）→ 语义模型应含 heading 标记
      expect(model.headingCount, greaterThanOrEqualTo(2),
          reason: '标题语义应保留（heading 标记）: $model');

      // 列表：2 个列表项 → w:numPr 标记存在
      expect(model.listCount, greaterThanOrEqualTo(2),
          reason: '列表语义应保留（numPr）: $model');

      // 表格：1 个 → w:tbl
      expect(model.tableCount, greaterThanOrEqualTo(1),
          reason: '表格语义应保留（tbl）: $model');

      // 文本 checksum 含中文（用完整文本 allText，checksum 只取前 16 字符）
      expect(model.allText, contains('中文段落内容'.substring(0, 4)),
          reason: '中文文本应保留: $model');
    });

    test('CAP-WORD-024：公式语义保留（BUG-WORD-001 修复后无渲染必含 fallback 文本）',
        () async {
      const md = r'公式 $E=mc^2$ 结尾';
      final model = await _semanticOf(md);
      // 测试环境无 SVG/PNG 渲染器 → formulaRels entry widthEmu=0（渲染失败）。
      // BUG-WORD-001 修复：widthEmu<=0 必须走 _formulaFallback(latex)，
      // 公式内容以文本形式保留（E=mc^2 出现在 w:t 中），而非空图片引用。
      expect(model.allText, contains('E=mc'),
          reason: '无渲染时公式必须以 fallback 文本保留（BUG-WORD-001 回归）: $model');
      // 修复前：公式走空图片引用（w:drawing 指向不存在 media）→ allText 无 E=mc
    });

    test('CAP-WORD-024b：无渲染时文档中无悬空公式图片引用（rels 无 dangling）',
        () async {
      const md = r'公式 $E=mc^2$ 结尾';
      final bytes = await WordExporter.export(md, title: 'semantic-no-dangling');
      final archive = ZipDecoder().decodeBytes(bytes);
      // 渲染失败（widthEmu=0）的公式不应生成 rel 指向不存在 media
      final relsFile = archive.files
          .firstWhere((f) => f.name == 'word/_rels/document.xml.rels');
      final relsXml = utf8.decode(relsFile.content as List<int>);
      // 若文档中无公式图片 rel，则不会有 media/formula_*.png 引用
      final formulaRels = RegExp(r'media/formula_\d+\.png').allMatches(relsXml).length;
      final mediaFiles = archive.files.where((f) => f.name.contains('media/formula')).length;
      expect(formulaRels, mediaFiles,
          reason: 'rels 中公式图片引用数应等于实际 media 文件数（无 dangling）: '
              'rels=$formulaRels media=$mediaFiles');
    });

    test('CAP-WORD-025：复杂混合文档语义模型稳定（两次导出一致）', () async {
      const md = '# 标题\n\n段落 **粗体** 和 *斜体*\n\n- A\n- B\n\n'
          r'公式 $x^2$' '\n\n| a | b |\n|---|---|\n| 1 | 2 |';
      final m1 = await _semanticOf(md);
      final m2 = await _semanticOf(md);
      // 同源导出语义模型应一致（确定性）
      expect(m1.paragraphCount, m2.paragraphCount);
      expect(m1.tableCount, m2.tableCount);
      expect(m1.listCount, m2.listCount);
      expect(m1.textChecksum, m2.textChecksum,
          reason: '同源导出语义模型应稳定: $m1 vs $m2');
    });
  });

  group('#326 displayMode 复合 key（builder 级回归）', () {
    test('同一 latex 行内+块级各解析为独立 rel，不共用同一张 PNG', () {
      // 文档：第一段含行内公式 $x$，第二段含块级公式 $$x$$（latex 同为 'x'）。
      final elements = <DocumentElement>[
        const ParagraphElement(children: [
          TextElement('行内: '),
          FormulaElement(latex: 'x', displayMode: false),
        ]),
        const ParagraphElement(children: [
          FormulaElement(latex: 'x', displayMode: true),
        ]),
      ];
      // 手构 formulaRels：行内 rIdImage1（小尺寸）、块级 rIdImage2（大尺寸）。
      // 复合 key（formulaRelKey，`I:`/`B:` 前缀）让两者在 Map 中共存；
      // 旧实现按 latex 单键索引时第二个会覆盖第一个，Map 只剩 rIdImage2，
      // 行内公式被错误地引用块级图——本测试在旧代码下第一个 expect 失败。
      final formulaRels = <String, FormulaImageInfo?>{
        formulaRelKey(false, 'x'): const FormulaImageInfo(
            relId: 'rIdImage1', widthEmu: 100000, heightEmu: 50000),
        formulaRelKey(true, 'x'): const FormulaImageInfo(
            relId: 'rIdImage2', widthEmu: 200000, heightEmu: 100000),
      };
      final docXml = WordOoxmlBuilder.buildDocumentXml(
        elements,
        null,
        formulaRels,
        const <String, MermaidImageInfo>{},
      );
      // 两个公式都应解析为各自的图片引用（widthEmu>0 不走 latex fallback）。
      expect(docXml, contains('r:embed="rIdImage1"'),
          reason: '行内公式必须引用 rIdImage1（行内图），不能被块级图覆盖');
      expect(docXml, contains('r:embed="rIdImage2"'),
          reason: '块级公式必须引用 rIdImage2（块级图）');
      // 两处都应是 drawing（图片），而非 latex 文本回退。
      expect(
        RegExp(r'<w:drawing>').allMatches(docXml).length,
        2,
        reason: '两个公式都应渲染为 drawing（图片），而非 latex 文本回退',
      );
    });

    test('渲染失败的公式（widthEmu=0）仍走 latex fallback，不丢内容', () {
      // 复合 key 与 fallback 路径不冲突：widthEmu<=0 的条目走 _formulaFallback。
      final elements = <DocumentElement>[
        const ParagraphElement(children: [
          FormulaElement(latex: 'y', displayMode: false),
        ]),
      ];
      final formulaRels = <String, FormulaImageInfo?>{
        formulaRelKey(false, 'y'): const FormulaImageInfo(
            relId: 'rIdImage1', widthEmu: 0, heightEmu: 0),
      };
      final docXml = WordOoxmlBuilder.buildDocumentXml(
        elements,
        null,
        formulaRels,
        const <String, MermaidImageInfo>{},
      );
      // 渲染失败 → 不应有 drawing，而应出现 latex 文本回退（'y'）。
      expect(docXml, isNot(contains('r:embed="rIdImage1"')),
          reason: '渲染失败的公式不应生成图片引用');
      expect(docXml, contains('>y<'),
          reason: '渲染失败应走 latex 文本回退，保留公式源文本');
    });

    test('review P2：Heading/TaskListItem 内公式被收集器覆盖', () {
      // #326 顺带补 P2（pre-existing 缺口）：_collectFormulas 与
      // collectAllFormulasByDisplayMode 此前只覆盖 Paragraph/List/Table/
      // Blockquote，标题/任务项内公式不进 allFormulas → 不预渲染 → 文本回退。
      // 用 pdf 侧 public API 守门两侧收集口径。
      // round-3 扩展：同时覆盖 ADR-0029 嵌套列表（ListElement.nested）深层公式。
      final elements = <DocumentElement>[
        const HeadingElement(level: 1, children: [
          FormulaElement(latex: 'h'),
        ]),
        const TaskListItemElement(children: [
          FormulaElement(latex: 't'),
        ]),
        const ListElement(
          children: [FormulaElement(latex: 'n')],
          nested: [
            ListElement(
              children: [FormulaElement(latex: 'n2')],
              nested: [
                ListElement(children: [FormulaElement(latex: 'n3')]),
              ],
            ),
          ],
        ),
      ];
      final grouped = PdfExporter.collectAllFormulasByDisplayMode(elements);
      expect(grouped.inline, containsAll(['h', 't', 'n', 'n2', 'n3']),
          reason: 'Heading/TaskListItem + 嵌套列表任意深度行内公式必须被收集');
    });

    test('review round-2：italic 内渲染失败公式(widthEmu=0)走 fallback，不写 dangling drawing', () {
      // _renderItalicInline / _renderStrikeInline 此前只查 info!=null，
      // widthEmu=0 仍写 drawing 引空 PNG → buildImageRelsXml 跳过 → dangling。
      // 与 _renderInlineRuns 同口径加 widthEmu>0 guard。
      final elements = <DocumentElement>[
        const ParagraphElement(children: [
          ItalicElement(children: [
            FormulaElement(latex: 'z', displayMode: false),
          ]),
        ]),
      ];
      final formulaRels = <String, FormulaImageInfo?>{
        formulaRelKey(false, 'z'): const FormulaImageInfo(
            relId: 'rIdImage1', widthEmu: 0, heightEmu: 0),
      };
      final docXml = WordOoxmlBuilder.buildDocumentXml(
        elements,
        null,
        formulaRels,
        const <String, MermaidImageInfo>{},
      );
      expect(docXml, isNot(contains('r:embed="rIdImage1"')),
          reason: 'italic 内渲染失败公式不应写 drawing 引用');
      expect(docXml, contains('>z<'),
          reason: '应走 fallback latex 文本，保留公式源文本');
    });
  });
}
