/// CAP-WORD-018 DOCX ZIP integrity（L1 Artifact Integrity 强化）。
///
/// 验证 WordExporter.export 生成的**真实 .docx**：
/// - ZIP 可解包 + CRC 正确（archive 包解包时自动校验 CRC）
/// - [Content_Types].xml 存在且可解析
/// - word/document.xml / word/styles.xml / word/settings.xml 存在
/// - word/_rels/document.xml.rels 存在
/// - 无 dangling relationship（rels 中每个 Relationship Target 在 ZIP 内存在）
///
/// 这层证明「文件没坏」；Word/WPS 消费端打开验证（L2-L6）见 CAP-WORD-017~025。
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/domain/services/exporters/word_exporter.dart';
import 'package:xml/xml.dart' as xml;

/// 导出真实 docx 并解包，返回 (zip, 文件表)。
Future<(Archive, Map<String, ArchiveFile>)> _exportAndUnzip(String md) async {
  final bytes = await WordExporter.export(md, title: 'zip-integrity');
  expect(bytes.length, greaterThan(0));
  // ZIP magic: PK\x03\x04
  expect(bytes[0], 0x50); // P
  expect(bytes[1], 0x4b); // K
  final archive = ZipDecoder().decodeBytes(bytes);
  final files = {
    for (final f in archive) f.name: f,
  };
  return (archive, files);
}

void main() {
  group('CAP-WORD-018 DOCX ZIP integrity（真实导出产物）', () {
    test('ZIP 可解包 + CRC 校验通过（archive 解包自动校验 CRC）', () async {
      final md = '# 标题\n\n段落内容';
      final (archive, _) = await _exportAndUnzip(md);
      expect(archive, isNotEmpty);
      // ZipDecoder.decodeBytes 成功即 CRC 通过；再显式解压每个文件确认可读
      for (final f in archive) {
        final content = f.content; // 触发解压（CRC 校验）
        expect(content, isNotNull);
      }
    });

    test('[Content_Types].xml 存在且可解析', () async {
      final (_, files) = await _exportAndUnzip('# T\n正文');
      final types = files['[Content_Types].xml'];
      expect(types, isNotNull, reason: '[Content_Types].xml 必须存在');
      final xml = utf8.decode(types!.content as List<int>);
      expect(xml, contains('wordprocessingml.document.main+xml'),
          reason: 'Content_Types 应声明 docx 主文档类型');
      expect(xml, contains('xmlns'), reason: 'Content_Types 应为合法 XML');
    });

    test('word/document.xml / styles.xml / settings.xml 存在', () async {
      final (_, files) = await _exportAndUnzip('# T\n正文');
      for (final part in [
        'word/document.xml',
        'word/styles.xml',
        'word/settings.xml',
      ]) {
        expect(files.containsKey(part), isTrue, reason: '$part 必须存在');
        final xml = utf8.decode(files[part]!.content as List<int>);
        expect(xml.trim().isNotEmpty, isTrue, reason: '$part 非空');
        expect(xml, contains('<'), reason: '$part 应为 XML');
      }
    });

    test('word/_rels/document.xml.rels 存在且 Target 无 dangling', () async {
      final (_, files) = await _exportAndUnzip(
        '# 标题\n\n段落\n\n- 列表项\n\n| a | b |\n|---|---|\n| 1 | 2 |',
      );
      final rels = files['word/_rels/document.xml.rels'];
      expect(rels, isNotNull, reason: 'document.xml.rels 必须存在');
      final relsXml = utf8.decode(rels!.content as List<int>);
      expect(relsXml, contains('Relationship'), reason: 'rels 应为合法 XML');

      // 解析每个 Relationship 的 Target，验证对应文件存在于 ZIP 内
      // （去除 /word 前缀映射到实际路径；忽略外部 target 如 http）
      final relRe = RegExp(r'Target="([^"]+)"');
      final dangling = <String>[];
      for (final m in relRe.allMatches(relsXml)) {
        var target = m.group(1)!;
        if (target.startsWith('http') || target.startsWith('mailto')) continue;
        // 相对 target（如 media/image1.png 相对 word/ 解析）
        if (!target.startsWith('/')) {
          target = 'word/$target';
        } else {
          target = target.substring(1);
        }
        if (!files.containsKey(target)) {
          dangling.add(target);
        }
      }
      expect(dangling, isEmpty,
          reason: 'rels 中不应有 dangling relationship: $dangling');
    });

    test('中文内容在 document.xml 中保真', () async {
      final (_, files) = await _exportAndUnzip('中文标题\n中文段落内容');
      final xml = utf8.decode(files['word/document.xml']!.content as List<int>);
      expect(xml, contains('中文标题'));
      expect(xml, contains('中文段落内容'));
    });
  });

  group('CAP-WORD-018b 解析器级验证（XmlDocument.parse well-formed）', () {
    test('全部 XML parts 解析器级 well-formed（非字符串代理）', () async {
      const md = '# 标题\n\n中文段落 **粗体**\n\n- 列表项A\n- 列表项B\n\n'
          '| 列1 | 列2 |\n|---|---|\n| 1 | 2 |\n\n公式 \$E=mc^2\$ 结尾';
      final (_, files) = await _exportAndUnzip(md);

      const xmlParts = [
        '[Content_Types].xml',
        'word/document.xml',
        'word/styles.xml',
        'word/settings.xml',
        'word/_rels/document.xml.rels',
      ];
      for (final part in xmlParts) {
        final content = files[part];
        expect(content, isNotNull, reason: '$part 必须存在');
        final raw = utf8.decode(content!.content as List<int>);
        // 解析器级验证：XmlDocument.parse 对 well-formed 输入成功，
        // 对非法输入抛 XmlParserException/XmlTagException —— 比字符串
        // contains 代理检查严格得多（能发现未闭合标签/属性缺引号/实体非法）
        final doc = xml.XmlDocument.parse(raw);
        expect(doc.rootElement.name.toString(), isNotEmpty,
            reason: '$part 解析后应有根元素');
      }
    });

    test('document.xml 标签嵌套深度与元素计数（结构合理性）', () async {
      const md = '# 标题\n\n段落\n\n- 列表A\n- 列表B\n\n| a | b |\n|---|---|\n| 1 | 2 |';
      final (_, files) = await _exportAndUnzip(md);
      final raw = utf8.decode(files['word/document.xml']!.content as List<int>);
      final doc = xml.XmlDocument.parse(raw);

      // 根元素必须是 w:document（WordprocessingML 主文档）
      expect(doc.rootElement.name.local, 'document',
          reason: '根元素应为 document（local name，忽略前缀）');

      // 遍历统计 w:p / w:tbl / w:tr —— 结构元素存在性
      final paragraphs = doc.rootElement.descendants
          .where((n) => n is xml.XmlElement && n.name.local == 'p')
          .length;
      final tables = doc.rootElement.descendants
          .where((n) => n is xml.XmlElement && n.name.local == 'tbl')
          .length;
      expect(paragraphs, greaterThanOrEqualTo(2), reason: '应有段落（含列表项）');
      expect(tables, greaterThanOrEqualTo(1), reason: '应有表格');

      // 嵌套深度合理（防止无限嵌套/异常深结构）：不超过 15 层
      var maxDepth = 0;
      void walk(xml.XmlNode node, int depth) {
        if (depth > maxDepth) maxDepth = depth;
        for (final c in node.children) {
          walk(c, depth + 1);
        }
      }

      walk(doc.rootElement, 1);
      expect(maxDepth, lessThan(15), reason: '嵌套深度应合理（<15，实际 $maxDepth）');
    });

    test('XML 属性合法性：所有属性名/值可解析（含中文与转义实体）', () async {
      const md = 'a & b < c > "d" 中文\n\n| x | y |\n|---|---|\n| 1 | 2 |';
      final (_, files) = await _exportAndUnzip(md);
      final raw = utf8.decode(files['word/document.xml']!.content as List<int>);
      final doc = xml.XmlDocument.parse(raw);

      var attrCount = 0;
      var entityOk = true;
      for (final el in doc.rootElement.descendants.whereType<xml.XmlElement>()) {
        for (final attr in el.attributes) {
          attrCount++;
          // 属性值经解析器解码后不应残留原始转义实体（&amp; 应为 &）
          if (attr.value.contains('&amp;')) entityOk = false;
        }
      }
      expect(attrCount, greaterThan(0), reason: '应有属性被解析');
      expect(entityOk, isTrue,
          reason: '属性值不应残留未解码实体（XmlDocument.parse 已解码）');
    });
  });
}
