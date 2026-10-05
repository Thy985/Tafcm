/// issue #318 回归守门（二）：持久层「解析不确定时不得破坏性覆写」。
///
/// 场景来源：文档首行是 `---`（合法 Markdown 水平线）且后文无闭合标记时，
/// 旧实现把全部正文当 front matter 消费、`body` 退化为 `''`；编辑器一次
/// 防抖自动保存即把文件覆写成「front matter + 空正文」，原文不可恢复。
///
/// 覆盖：解析 → 序列化写回 → 重新解析 的完整链路、renameDocument 链路，
/// 以及「无 front matter 的文件正文里出现 `encoding: gbk` 行」不得被当成
/// 编码声明（否则整文件按 GBK 解码 / 写回，静默改写文件编码）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/services/file_repository.dart';
import 'package:tafcm/core/services/front_matter_parser.dart';

late Directory _tmp;
late FileRepository _repo;

/// PROBE2-b 样本：首行 `---` + 无闭合标记 + 正文不含 `key: value` 行。
const String _hrDoc = '---\n第一行正文\n第二行正文\n第三行正文';

/// 同上但正文带 `# H1`，覆盖标题改写链路。
const String _hrDocWithH1 = '---\n# 旧标题\n\n正文首段\n正文尾段';

String _p(String name) => '${_tmp.path}${Platform.pathSeparator}$name';

Future<File> _writeFixture(String name, String content) async {
  final f = File(_p(name));
  await f.writeAsString(content, encoding: utf8);
  return f;
}

void main() {
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('tafcm_318_');
    _repo = FileRepository()..testDocsDir = _tmp.path;
  });

  tearDown(() {
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  group('读端：首行 --- 未闭合', () {
    test('readDocument 返回整份原文（编辑器不得显示为空）', () async {
      await _writeFixture('hr.md', _hrDoc);
      final doc = await _repo.readDocument(_p('hr.md'));
      expect(doc.content, _hrDoc, reason: '正文一字不差');
      expect(doc.content, contains('第一行正文'));
      expect(doc.content, startsWith('---'));
    });

    test('readDocument 从正文首个 # H1 推导标题', () async {
      await _writeFixture('hr_h1.md', _hrDocWithH1);
      final doc = await _repo.readDocument(_p('hr_h1.md'));
      expect(doc.content, _hrDocWithH1);
      expect(doc.title, '旧标题');
    });

    test('首行 --- 是水平线、正文另有 --- 时同样整份保留', () async {
      const raw = '---\n标题行\n\n正文首段\n\n---\n正文尾段';
      await _writeFixture('hr2.md', raw);
      final doc = await _repo.readDocument(_p('hr2.md'));
      expect(doc.content, raw);
    });

    test('malformed 文档不采信正文里的 key: value 行作 id', () async {
      const raw = '---\nid: 冒名_id\n正文';
      await _writeFixture('fake_meta.md', raw);
      final doc = await _repo.readDocument(_p('fake_meta.md'));
      expect(doc.id, 'fake_meta', reason: 'id 回落到文件名');
      expect(doc.content, raw);
    });
  });

  group('写端：自动保存（parse → build → 重新 parse）不丢正文', () {
    test('首行 --- 未闭合文档保存后原文逐字仍在', () async {
      await _writeFixture('hr.md', _hrDoc);

      // 模拟：打开文档 → 触发一次防抖自动保存。
      final before = await _repo.readDocument(_p('hr.md'));
      expect(before.content, _hrDoc);
      await _repo.writeDocument(_p('hr.md'),
          title: before.title, content: before.content);

      final after = await _repo.readDocument(_p('hr.md'));
      expect(after.content, contains(_hrDoc),
          reason: '原文必须逐字保留（PROBE2-b）');
      for (final line in _hrDoc.split('\n')) {
        expect(after.content.split('\n'), contains(line),
            reason: '丢行：$line');
      }
      // 文件确实被重新写成了合法 front matter 形态。
      expect(FrontMatterParser.parse(await File(_p('hr.md')).readAsString())
          .status, FrontMatterStatus.valid);
    });

    test('再次保存后正文稳定（第二次保存不再丢行）', () async {
      await _writeFixture('hr.md', _hrDoc);
      final first = await _repo.readDocument(_p('hr.md'));
      await _repo.writeDocument(_p('hr.md'),
          title: first.title, content: first.content);
      final second = await _repo.readDocument(_p('hr.md'));
      await _repo.writeDocument(_p('hr.md'),
          title: second.title, content: second.content);
      final third = await _repo.readDocument(_p('hr.md'));
      expect(third.content, second.content, reason: '保存链稳定');
      expect(third.content, contains(_hrDoc));
    });

    test('带 H1 的 --- 开头文档：保存后标题正确且正文逐字保留', () async {
      await _writeFixture('hr_h1.md', _hrDocWithH1);
      final before = await _repo.readDocument(_p('hr_h1.md'));
      await _repo.writeDocument(_p('hr_h1.md'),
          title: before.title, content: before.content);
      final after = await _repo.readDocument(_p('hr_h1.md'));
      expect(after.title, '旧标题');
      expect(after.content, contains('正文首段'));
      expect(after.content, contains('正文尾段'));
      expect(after.content, contains('---'));
    });
  });

  group('renameDocument 链路', () {
    test('首行 --- 未闭合文档改名后正文不丢', () async {
      await _writeFixture('hr_h1.md', _hrDocWithH1);
      await _repo.renameDocument(_p('hr_h1.md'), '新标题');
      final doc = await _repo.readDocument(_p('hr_h1.md'));
      expect(doc.title, '新标题');
      expect(doc.content, contains('正文首段'));
      expect(doc.content, contains('正文尾段'));
      expect(doc.content.split('\n'), contains('---'));
    });

    test('首行 --- 未闭合且无 H1 的文档：改名只前插标题，其余原样', () async {
      await _writeFixture('hr.md', _hrDoc);
      await _repo.renameDocument(_p('hr.md'), '新标题');
      final doc = await _repo.readDocument(_p('hr.md'));
      expect(doc.title, '新标题');
      for (final line in _hrDoc.split('\n')) {
        expect(doc.content.split('\n'), contains(line), reason: '丢行：$line');
      }
      // 改名不改文件名（uuid 路径不变）。
      expect(await File(_p('hr.md')).exists(), isTrue);
    });
  });

  group('encoding 声明探测范围（issue #318 近邻缺陷）', () {
    test('无 front matter 但正文含 encoding: gbk 行 → 不按 GBK 解码', () async {
      const raw = '# YAML 入门\n\n示例配置：\n\nencoding: gbk\n\n中文正文一句。';
      await _writeFixture('tutorial.md', raw);

      final doc = await _repo.readDocument(_p('tutorial.md'));
      expect(doc.content, raw, reason: '不得被 GBK 误解码成乱码');

      // 写回：文件仍是 UTF-8 字节，编码不被静默改写。
      await _repo.writeDocument(_p('tutorial.md'),
          title: doc.title, content: doc.content);
      final bytes = await File(_p('tutorial.md')).readAsBytes();
      expect(utf8.decode(bytes), contains('中文正文一句。'));
      expect(utf8.decode(bytes), contains('encoding: gbk'),
          reason: '该行是正文，不该被删');

      // 重新生成的 front matter 不含 encoding 声明。
      final reparsed = FrontMatterParser.parse(utf8.decode(bytes));
      expect(reparsed.status, FrontMatterStatus.valid);
      expect(reparsed.meta!['encoding'], isNull);
    });

    test('首行 --- 未闭合 + 正文含 encoding: 行 → 不按 GBK 解码', () async {
      const raw = '---\nencoding: gbk\n中文正文一句。';
      await _writeFixture('hr_enc.md', raw);
      final doc = await _repo.readDocument(_p('hr_enc.md'));
      expect(doc.content, raw);
      await _repo.writeDocument(_p('hr_enc.md'),
          title: doc.title, content: doc.content);
      final bytes = await File(_p('hr_enc.md')).readAsBytes();
      expect(utf8.decode(bytes), contains('中文正文一句。'));
      final reparsed = FrontMatterParser.parse(utf8.decode(bytes));
      expect(reparsed.meta!['encoding'], isNull);
    });
  });
}
