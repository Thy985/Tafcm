/// issue #318 回归守门（一）：`FrontMatterParser.parse` 的解析状态判定。
///
/// 覆盖 parse 三态（noFrontMatter / valid / malformed）与
/// `closedBlockOf`（encoding 声明探测的搜索范围限定）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/services/front_matter_parser.dart';

void main() {
  group('parse 状态判定', () {
    test('首行 --- 且无闭合标记 → malformed，body 为整份原文（含首行 ---）',
        () {
      const raw = '---\n# 我的文档\n\n第一段正文\n第二段正文';
      final r = FrontMatterParser.parse(raw);
      expect(r.status, FrontMatterStatus.malformed);
      expect(r.meta, isNull, reason: 'malformed 不得给出可采信的 meta');
      expect(r.isValid, isFalse);
      expect(r.body, raw, reason: '一行都不能少');
      expect(r.raw, raw);
    });

    test('malformed：正文里没有 key: value 形态的行时也不得被当作 meta', () {
      // 无冒号的正文行在旧实现里被丢弃、meta 也为空 → 编辑器显示空白。
      const raw = '---\n这是一段中文正文，没有冒号\nAnother paragraph';
      final r = FrontMatterParser.parse(raw);
      expect(r.status, FrontMatterStatus.malformed);
      expect(r.body, raw);
    });

    test('malformed：单行 --- 也不是 front matter', () {
      final r = FrontMatterParser.parse('---');
      expect(r.status, FrontMatterStatus.malformed);
      expect(r.body, '---');
    });

    test('首行 --- 且有闭合标记 → valid，meta/body 正确解析', () {
      const raw =
          '---\nid: abc\ncreatedAt: 2026-01-01T00:00:00.000\n---\n# T\n\n正文';
      final r = FrontMatterParser.parse(raw);
      expect(r.status, FrontMatterStatus.valid);
      expect(r.isValid, isTrue);
      expect(r.meta!['id'], 'abc');
      expect(r.meta!['createdAt'], '2026-01-01T00:00:00.000');
      expect(r.body, '# T\n\n正文');
      expect(r.raw, raw);
    });

    test('valid：嵌套 YAML（列表 / 缩进行）不破坏判定', () {
      const raw = '---\ntitle: 我的文档\ntags:\n  - a\n  - b\n---\n正文行';
      final r = FrontMatterParser.parse(raw);
      expect(r.status, FrontMatterStatus.valid);
      expect(r.meta!['title'], '我的文档');
      expect(r.body, '正文行');
    });

    test('valid：空 front matter（--- 紧接 ---）仍视为 valid，body 为全文', () {
      const raw = '---\n---\n# T\n正文';
      final r = FrontMatterParser.parse(raw);
      expect(r.status, FrontMatterStatus.valid);
      expect(r.meta, isEmpty);
      expect(r.body, '# T\n正文');
    });

    test('valid：块后即文件末尾（无正文）→ body 为空串，不吞 meta', () {
      const raw = '---\nid: x\n---\n';
      final r = FrontMatterParser.parse(raw);
      expect(r.status, FrontMatterStatus.valid);
      expect(r.meta!['id'], 'x');
      expect(r.body, isEmpty);
    });

    test('首行非 --- → noFrontMatter，body 为全文', () {
      const raw = 'plain body\n# Title\n---\n分割线';
      final r = FrontMatterParser.parse(raw);
      expect(r.status, FrontMatterStatus.noFrontMatter);
      expect(r.meta, isNull);
      expect(r.body, raw);
    });

    test('首行 --- 是水平线、正文另有 --- → malformed（不被误当 front matter）',
        () {
      // 旧实现把第二条 --- 当闭合标记，前 4 行正文被整段吞掉。
      const raw = '---\n# 标题\n\n正文首段\n\n---\n正文尾段';
      final r = FrontMatterParser.parse(raw);
      expect(r.status, FrontMatterStatus.malformed);
      expect(r.body, raw);
    });

    test('首行 --- 块内含冒号正文行 → 视为 valid（YAML 形态优先，行为不变）',
        () {
      const raw = '---\nfoo: bar\n---\n正文';
      final r = FrontMatterParser.parse(raw);
      expect(r.status, FrontMatterStatus.valid);
      expect(r.meta!['foo'], 'bar');
      expect(r.body, '正文');
    });
  });

  group('closedBlockOf（encoding 声明探测范围）', () {
    test('无 front matter → null（正文里的 encoding: 行不被当声明）', () {
      expect(
        FrontMatterParser.closedBlockOf('# YAML 教程\nencoding: gbk\n正文'),
        isNull,
      );
    });

    test('未闭合 → null', () {
      expect(FrontMatterParser.closedBlockOf('---\nencoding: gbk\n正文'),
          isNull);
    });

    test('已闭合 → 返回含首尾 --- 的块文本，且不含正文', () {
      final block = FrontMatterParser.closedBlockOf(
          '---\nid: x\nencoding: gb18030\n---\n正文里也有 encoding: big5');
      expect(block, isNotNull);
      expect(block, contains('encoding: gb18030'));
      expect(block, isNot(contains('正文里也有')));
    });
  });

  group('build 与 parse 往返（合法 front matter 行为不变）', () {
    test('build → parse 还原 meta 与 body', () {
      final md = FrontMatterParser.build(
        id: 'abc',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 2, 2),
        title: 'Hello',
        content: 'body text\nsecond line',
      );
      final r = FrontMatterParser.parse(md);
      expect(r.status, FrontMatterStatus.valid);
      expect(r.meta!['id'], 'abc');
      expect(r.meta!['createdAt'], '2026-01-01T00:00:00.000');
      expect(r.meta!['updatedAt'], '2026-02-02T00:00:00.000');
      expect(r.body, startsWith('# Hello'));
      expect(r.body, contains('body text\nsecond line'));
    });

    test('build 带 encoding 声明 → parse 仍为 valid 且能读回声明', () {
      final md = FrontMatterParser.build(
        id: 'abc',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        title: 'T',
        content: 'c',
        encoding: 'gb18030',
      );
      final r = FrontMatterParser.parse(md);
      expect(r.status, FrontMatterStatus.valid);
      expect(r.meta!['encoding'], 'gb18030');
    });
  });
}
