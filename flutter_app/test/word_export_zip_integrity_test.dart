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
import 'package:formula_fix/domain/services/exporters/word_exporter.dart';

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
}
