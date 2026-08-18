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
import 'package:formula_fix/domain/services/exporters/word_exporter.dart';

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
}
