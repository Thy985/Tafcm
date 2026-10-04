// issue #343 回归保护：保存时相邻段落被合并。
//
// 复刻生产保存路径：MarkdownParser.parse → 过滤 EmptyLineElement
// → joinBlocks → 重新解析。断言块数守恒 + 内容保真。
//
// 修复前 `joinBlocks` 不存在、生产路径用 `join('\n')`，相邻段落
// 9 块 → 7 块塌缩。本测试在 fix/parser-paragraph-separator 分支上
// 应全绿；若有人回退 joinBlocks 为裸 join('\n')，多个用例即失败。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/editing/block_serializer.dart';
import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/data/models/document.dart';

/// 复刻 InMemoryDocumentEditor.serializedContent 的生产语义。
String save(List<DocumentElement> blocks) => joinBlocks(blocks);

/// 解析 + 过滤 EmptyLineElement（与 EditorPage._loadFromFile 一致）。
List<DocumentElement> load(String src) =>
    MarkdownParser.parse(src).where((e) => e is! EmptyLineElement).toList();

/// 完整往返：原文 → 加载 → 保存 → 磁盘字符串。
String roundTrip(String src) => save(load(src));

void main() {
  group('issue #343: 段落合并回归', () {
    test('两段之间空行保留为两块', () {
      const src = 'para one\n\npara two\n';
      final before = load(src);
      expect(before.length, 2,
          reason: '原文本应解析为 2 个段落块');
      final out = roundTrip(src);
      final after = load(out);
      expect(after.length, 2, reason: '保存后块数必须守恒。out=\n$out');
      expect(out.contains('para one\n\npara two'), isTrue,
          reason: '磁盘上段落间必须保留空行');
    });

    test('三段之间空行保留为三块', () {
      const src = 'p1\n\np2\n\np3\n';
      expect(load(src).length, 3);
      final out = roundTrip(src);
      expect(load(out).length, 3, reason: 'out=\n$out');
    });

    test('真实文档（标题+段落+列表+段落）块数守恒', () {
      const doc = '''# 用户手册

本产品是一个移动端 Markdown 编辑器。

它支持公式渲染与图表渲染。

## 功能列表

- 支持块级公式
- 支持 Mermaid 图

## 常见问题

遇到问题时请先检查网络连接。

如果仍未解决请联系技术支持。
''';
      final before = load(doc);
      expect(before.length, 9, reason: '原始块数');
      final out = roundTrip(doc);
      final after = load(out);
      expect(after.length, 9,
          reason: '保存后块数必须守恒（修复前会塌缩到 7）。out=\n$out');
    });

    test('保存幂等：保存两次结果相同', () {
      const src = 'p1\n\np2\n\np3\n';
      final once = roundTrip(src);
      final twice = roundTrip(once);
      expect(twice, once, reason: '往返应为 fixpoint');
    });

    test('内容字符零丢失', () {
      const src = '第一段内容。\n\n第二段内容。\n\n第三段内容。\n';
      final out = roundTrip(src);
      for (final fragment in ['第一段内容。', '第二段内容。', '第三段内容。']) {
        expect(out.contains(fragment), isTrue,
            reason: '内容片段必须保留：$fragment');
      }
    });
  });

  group('非段落块间分隔：自终止块保持单换行', () {
    test('标题后接段落：两块', () {
      const src = '# heading\n\npara text\n';
      expect(load(src).length, 2);
      final out = roundTrip(src);
      expect(load(out).length, 2, reason: 'out=\n$out');
    });

    test('段落后接标题：两块', () {
      const src = 'para text\n\n# heading\n';
      expect(load(src).length, 2);
      final out = roundTrip(src);
      expect(load(out).length, 2, reason: 'out=\n$out');
    });

    test('紧凑列表保持紧凑（两个 ListElement 不被空行撑成 loose）', () {
      const src = '- item one\n- item two\n';
      final before = load(src);
      expect(before.length, 2);
      // 紧凑列表 round-trip：保存后仍是单换行分隔（无空行）
      final out = roundTrip(src);
      expect(out.contains('- item one\n- item two'), isTrue,
          reason: '紧凑列表不应被插入空行。out=\n$out');
      expect(load(out).length, 2);
    });

    test('段落后接列表：两块', () {
      const src = 'para text\n\n- list item\n';
      expect(load(src).length, 2);
      final out = roundTrip(src);
      expect(load(out).length, 2, reason: 'out=\n$out');
    });

    test('列表后接段落：两块（list flush 不被段落合并）', () {
      const src = '- list item\n\npara text\n';
      final before = load(src);
      expect(before.length, 2);
      final out = roundTrip(src);
      expect(load(out).length, 2, reason: 'out=\n$out');
    });

    test('代码块前后段落：三块', () {
      const src = 'before para\n\n```dart\nvar x = 1;\n```\n\nafter para\n';
      expect(load(src).length, 3);
      final out = roundTrip(src);
      expect(load(out).length, 3, reason: 'out=\n$out');
    });

    test('引用块前后段落：三块', () {
      const src = 'before para\n\n> quote line\n\nafter para\n';
      expect(load(src).length, 3);
      final out = roundTrip(src);
      expect(load(out).length, 3, reason: 'out=\n$out');
    });

    test('水平线前后段落：三块', () {
      const src = 'before para\n\n---\n\nafter para\n';
      expect(load(src).length, 3);
      final out = roundTrip(src);
      expect(load(out).length, 3, reason: 'out=\n$out');
    });

    test('表格前后段落：三块', () {
      const src =
          'before para\n\n| h1 | h2 |\n| --- | --- |\n| a | b |\n\nafter para\n';
      expect(load(src).length, 3);
      final out = roundTrip(src);
      expect(load(out).length, 3, reason: 'out=\n$out');
    });
  });

  group('joinBlocks 直接契约', () {
    test('空列表返回空串', () {
      expect(joinBlocks(const <DocumentElement>[]), '');
    });

    test('单块无前导分隔符', () {
      expect(
        joinBlocks([ParagraphElement(children: const [TextElement('only')])]),
        'only',
      );
    });

    test('段落后接段落插入空行', () {
      expect(
        joinBlocks([
          ParagraphElement(children: const [TextElement('a')]),
          ParagraphElement(children: const [TextElement('b')]),
        ]),
        'a\n\nb',
      );
    });

    test('标题后接段落：单换行（标题自终止）', () {
      expect(
        joinBlocks([
          HeadingElement(level: 1, children: const [TextElement('title')]),
          ParagraphElement(children: const [TextElement('body')]),
        ]),
        '# title\nbody',
      );
    });

    test('段落后接标题：空行（段落非自终止）', () {
      expect(
        joinBlocks([
          ParagraphElement(children: const [TextElement('body')]),
          HeadingElement(level: 1, children: const [TextElement('title')]),
        ]),
        'body\n\n# title',
      );
    });
  });

  group('块数守恒属性（多维矩阵）', () {
    /// 对一组文档断言 roundTrip 后块数 >= 原始块数（保存不合并）。
    /// 大部分情况应是 ==；允许 > 是因为某些 parser 边界行为可能切分，
    /// 但绝不允许塌缩（<）。
    final cases = <(String name, String src)>[
      ('两段', 'p1\n\np2\n'),
      ('三段', 'p1\n\np2\n\np3\n'),
      ('标题+段+段+标题+段+段', '# h1\n\np1\n\np2\n\n## h2\n\np3\n\np4\n'),
      ('段+列表+段', 'para\n\n- a\n- b\n\npara2\n'),
      ('段+代码+段', 'para\n\n```\ncode\n```\n\npara2\n'),
      ('段+引用+段', 'para\n\n> quote\n\npara2\n'),
      ('段+表格+段', 'para\n\n| a | b |\n| --- | --- |\n| c | d |\n\npara2\n'),
      ('段+水平线+段', 'para\n\n---\n\npara2\n'),
      ('段+mermaid+段', 'para\n\n```mermaid\ngraph TD\nA-->B\n```\n\npara2\n'),
      ('段+段+列表+列表+段+段', 'p1\n\np2\n\n- a\n- b\n\np3\n\np4\n'),
    ];

    for (final c in cases) {
      test('${c.$1}：roundTrip 块数不塌缩', () {
        final before = load(c.$2);
        final out = roundTrip(c.$2);
        final after = load(out);
        expect(after.length, greaterThanOrEqualTo(before.length),
            reason: '保存不得合并块。before=${before.length} '
                'after=${after.length}\nsrc=\n${c.$2}\nout=\n$out');
      });
    }
  });
}