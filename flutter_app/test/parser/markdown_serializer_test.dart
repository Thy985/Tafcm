/// MarkdownSerializer 单元测试（ADR-0020 PR A review 反馈）。
///
/// 覆盖：空列表 / 单类型块 / 混合块 / 自定义 separator / FormulaElement 行内。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/parser/markdown_serializer.dart';
import 'package:tafcm/data/models/document.dart';

void main() {
  group('MarkdownSerializer.serialize', () {
    test('空列表 → 空字符串', () {
      expect(MarkdownSerializer.serialize([]), '');
    });

    test('单 Paragraph（纯文本）', () {
      final elements = [
        ParagraphElement(children: [TextElement('hello world')]),
      ];
      expect(MarkdownSerializer.serialize(elements), 'hello world');
    });

    test('单 Heading', () {
      final elements = [
        HeadingElement(level: 2, children: [TextElement('Section')]),
      ];
      expect(MarkdownSerializer.serialize(elements), '## Section');
    });

    test('单 Code 块', () {
      final elements = [
        const CodeElement(code: 'x = 1', language: 'py'),
      ];
      final result = MarkdownSerializer.serialize(elements);
      expect(result, contains('```py'));
      expect(result, contains('x = 1'));
      expect(result, contains('```'));
    });

    test('Paragraph 含 FormulaElement（行内公式）', () {
      final elements = [
        ParagraphElement(children: [
          TextElement('E = '),
          const FormulaElement(latex: 'mc^2', displayMode: false),
        ]),
      ];
      expect(MarkdownSerializer.serialize(elements), r'E = $mc^2$');
    });

    test('Paragraph 含 Bold + Italic 嵌套', () {
      final elements = [
        ParagraphElement(children: [
          BoldElement(children: [
            TextElement('bold'),
            ItalicElement(children: [TextElement('italic')]),
          ]),
        ]),
      ];
      expect(MarkdownSerializer.serialize(elements), r'**bold*italic***');
    });

    test('混合块类型（heading + paragraph + code + quote）', () {
      final elements = [
        HeadingElement(level: 1, children: [TextElement('Title')]),
        ParagraphElement(children: [TextElement('intro')]),
        const CodeElement(code: 'print(1)', language: 'dart'),
        const BlockquoteElement(children: [TextElement('quote')]),
      ];
      final result = MarkdownSerializer.serialize(elements, separator: '\n\n');
      expect(result, '# Title\n\nintro\n\n```dart\nprint(1)\n```\n\n> quote');
    });

    test('默认 separator=\\n', () {
      final elements = [
        ParagraphElement(children: [TextElement('a')]),
        ParagraphElement(children: [TextElement('b')]),
      ];
      expect(MarkdownSerializer.serialize(elements), 'a\nb');
    });

    test('自定义 separator=\\n\\n', () {
      final elements = [
        ParagraphElement(children: [TextElement('a')]),
        ParagraphElement(children: [TextElement('b')]),
      ];
      expect(MarkdownSerializer.serialize(elements, separator: '\n\n'), 'a\n\nb');
    });

    test('带 indent 的 ListElement', () {
      final elements = [
        ListElement(
          children: [TextElement('item')],
          ordered: false,
          indent: 0,
        ),
      ];
      expect(MarkdownSerializer.serialize(elements), '- item');
    });

    test('TaskListItemElement（checked）', () {
      final elements = [
        TaskListItemElement(
          children: [TextElement('done')],
          checked: true,
          indent: 0,
        ),
      ];
      expect(MarkdownSerializer.serialize(elements), '- [x] done');
    });
  });
}
