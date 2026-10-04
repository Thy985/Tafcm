/// 块级公式（`$$`）解析专项回归（issue #321）。
///
/// 缺陷现象：导入含多行块级公式（标准 Markdown 的 `$$\n...\n$$`）的 .md 后，
/// 块级公式完全不渲染——`$$` 定界行显示为空块，正文逐行以原始 LaTeX 文本
/// （serif 正文字体）显示。根因是 `MarkdownParser.parse` 逐行调用 `_parseInline`，
/// 多行 `$$` 块被拆散，永远匹配不成公式元素。
///
/// 本文件锁住的契约：
/// 1. 多行 `$$...$$` → **单个** displayMode FormulaElement，latex 与正文一致
/// 2. 单行 `$$...$$` 与行内 `$...$` 不回退
/// 3. 坏公式 / 未闭合 `$$` 优雅降级，不抛异常
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/parser/formula_extractor.dart';
import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/core/parser/markdown_serializer.dart';
import 'package:tafcm/data/models/document.dart';

/// 收集文档中全部 inline 公式（含嵌套块）。
List<FormulaElement> _allFormulas(List<DocumentElement> elements) {
  final out = <FormulaElement>[];
  void walkInline(List<InlineElement> children) {
    for (final child in children) {
      switch (child) {
        case FormulaElement():
          out.add(child);
        case BoldElement(:final children):
        case ItalicElement(:final children):
        case StrikethroughElement(:final children):
          walkInline(children);
        case TextElement():
        case InlineCodeElement():
        case LinkElement():
        case ImageElement():
          break;
      }
    }
  }

  void walk(List<DocumentElement> nodes) {
    for (final node in nodes) {
      switch (node) {
        case ParagraphElement(:final children):
        case ListElement(:final children):
        case TaskListItemElement(:final children):
        case BlockquoteElement(:final children):
          walkInline(children);
        case TableElement(:final headers, :final rows):
          for (final header in headers) {
            walkInline(header);
          }
          for (final row in rows) {
            for (final cell in row) {
              walkInline(cell);
            }
          }
        case HeadingElement(:final children):
          walkInline(children);
        case CodeElement():
        case MermaidElement():
        case HorizontalRuleElement():
        case EmptyLineElement():
          break;
      }
    }
  }

  walk(elements);
  return out;
}

/// 取仅含单个 display 公式的段落（`ParagraphBlock._isPureBlockFormula` 的契约）。
ParagraphElement _pureFormulaParagraph(List<DocumentElement> elements) {
  final candidates = elements
      .whereType<ParagraphElement>()
      .where((p) => p.children.length == 1 && p.children.first is FormulaElement)
      .toList();
  expect(candidates, hasLength(1),
      reason: '期望恰好一个「纯块级公式」段落，实际 AST：$elements');
  return candidates.single;
}

void main() {
  group(r'issue #321：多行 $$...$$ 块级公式', () {
    test(r'标准写法（$$ 定界行独占）解析为单个 display 公式元素', () {
      const md = '多行公式：\n\n'
          '\$\$\n'
          r'\int_0^\infty e^{-x^2} dx = \frac{\sqrt{\pi}}{2}'
          '\n'
          '\$\$';

      final elements = MarkdownParser.parse(md);
      final paragraph = _pureFormulaParagraph(elements);

      expect(paragraph.children, hasLength(1),
          reason: '块级公式段落只应有公式本身，不夹带空公式 / 原文文本');
      final formula = paragraph.children.single as FormulaElement;
      expect(formula.displayMode, isTrue);
      expect(formula.latex, r'\int_0^\infty e^{-x^2} dx = \frac{\sqrt{\pi}}{2}');
    });

    test('多行正文内部换行全部保留在同一个公式元素里', () {
      const latexBody = '\\begin{aligned}\n'
          'a &= b + c \\\\\n'
          'd &= e + f\n'
          '\\end{aligned}';
      const md = '\$\$\n$latexBody\n\$\$';

      final elements = MarkdownParser.parse(md);
      final formulas = _allFormulas(elements);

      expect(formulas, hasLength(1),
          reason: '多行块级公式必须合并为 1 个公式，而不是逐行拆成多个');
      expect(formulas.single.displayMode, isTrue);
      expect(formulas.single.latex, latexBody,
          reason: r'latex 必须与 $$ 之间的正文逐字一致（含内部换行）');
    });

    test('前后带空行的变体结构稳定（公式自成一块，不并入相邻段落）', () {
      const md = '正文\n\n'
          '\$\$\n'
          'E=mc^2\n'
          '\$\$\n\n'
          '后文';

      final elements = MarkdownParser.parse(md);
      final paragraphs = elements.whereType<ParagraphElement>().toList();

      expect(paragraphs, hasLength(3));
      expect(_allFormulas(elements), hasLength(1));
      expect((paragraphs[1].children.single as FormulaElement).latex, 'E=mc^2');
      expect((paragraphs[2].children.single as TextElement).text, '后文');
    });

    test('多个块级公式块互不吞并', () {
      const md = '\$\$\na=1\n\$\$\n\n\$\$\nb=2\n\$\$';

      final elements = MarkdownParser.parse(md);
      final formulas = _allFormulas(elements);

      expect(formulas.map((f) => f.latex).toList(), ['a=1', 'b=2']);
      expect(formulas.every((f) => f.displayMode), isTrue);
    });

    test('CRLF 文档同样解析为单个公式且 latex 无 \\r 残留', () {
      const md = '前置\r\n\r\n\$\$\r\nE=mc^2\r\n\$\$\r\n';

      final elements = MarkdownParser.parse(md);
      final formula = _pureFormulaParagraph(elements).children.single
          as FormulaElement;

      expect(formula.displayMode, isTrue);
      expect(formula.latex, 'E=mc^2');
      expect(formula.latex.contains('\r'), isFalse);
    });

    test(r'代码块内的 $$ 不被当作公式（fence 优先级不变）', () {
      const md = '前文\n\n```\n\$\$\nE=mc^2\n\$\$\n```\n';

      final elements = MarkdownParser.parse(md);

      expect(_allFormulas(elements), isEmpty);
      final code = elements.whereType<CodeElement>().single;
      expect(code.code, contains(r'$$'));
    });

    test('round-trip：多行公式 parse → serialize → parse 收敛且不丢内容', () {
      const md = '正文\n\n\$\$\na=1\nb=2\n\$\$';
      final first = MarkdownParser.parse(md);
      // EmptyLineElement 是块分隔符，序列化契约要求调用方过滤（roundtrip_fuzz_test）。
      final serializable = first.where((e) => e is! EmptyLineElement).toList();

      final md1 = MarkdownSerializer.serialize(serializable);
      final second =
          MarkdownParser.parse(md1).where((e) => e is! EmptyLineElement).toList();
      final md2 = MarkdownSerializer.serialize(second);

      expect(md2, md1, reason: '二次序列化应收敛到不动点');
      expect(_allFormulas(second).single.latex, 'a=1\nb=2',
          reason: 'round-trip 后多行正文不得丢失');
    });

    test('序列化回写形态（开闭定界符跨行）可被重新解析', () {
      // InlineSerializer 把含换行的 latex 写成 `$$a\nb$$` 单块，
      // 该形态必须同样被识别为一个公式，否则保存后再打开会退化成源码文本。
      const md = r'$$\begin{aligned}' '\n' r'a &= b' '\n' r'\end{aligned}$$';

      final formulas = _allFormulas(MarkdownParser.parse(md));

      expect(formulas, hasLength(1));
      expect(formulas.single.displayMode, isTrue);
      expect(formulas.single.latex, r'\begin{aligned}' '\n' r'a &= b' '\n' r'\end{aligned}');
    });

    test('FormulaExtractor 直接扫描多行文本也能拿到 display 公式', () {
      const text = '\$\$\nE=mc^2\n\$\$';

      final matches = FormulaExtractor.extractFormulas(text);

      expect(matches, hasLength(1));
      expect(matches.single.displayMode, isTrue);
      expect(matches.single.latex, 'E=mc^2');
      expect(FormulaExtractor.findDisplayDelimiter(text, 2), 10,
          reason: r'闭合定界符下标：text = 开定界 + 换行 + E=mc^2 + 换行 + 闭合定界');
    });
  });

  group('不回退：既有公式行为保持不变', () {
    test(r'单行 $$...$$ 仍是单个 display 公式', () {
      final elements = MarkdownParser.parse(r'$$\int_0^1 x^2 dx$$');

      final paragraph = _pureFormulaParagraph(elements);
      final formula = paragraph.children.single as FormulaElement;
      expect(formula.displayMode, isTrue);
      expect(formula.latex, r'\int_0^1 x^2 dx');
    });

    test('单行多段公式互不吞并', () {
      final elements = MarkdownParser.parse('前 \$\$a\$\$ 中 \$\$b\$\$ 后');

      final formulas = _allFormulas(elements);
      expect(formulas.map((f) => f.latex).toList(), ['a', 'b']);
      expect(formulas.every((f) => f.displayMode), isTrue);
    });

    test(r'行内 $...$ 仍为 inline 公式且不被跨行配对', () {
      final elements = MarkdownParser.parse('行内 \$x^2\$ 结束');

      final formulas = _allFormulas(elements);
      expect(formulas, hasLength(1));
      expect(formulas.single.latex, 'x^2');
      expect(formulas.single.displayMode, isFalse);
    });

    test('行内公式与多行块级公式混排各自保持 displayMode', () {
      const md = '行内 \$E=mc^2\$。\n\n\$\$\n\\int_0^1 x\\,dx\n\$\$';

      final formulas = _allFormulas(MarkdownParser.parse(md));

      expect(formulas.map((f) => f.displayMode).toList(), [false, true]);
      expect(formulas.map((f) => f.latex).toList(), ['E=mc^2', r'\int_0^1 x\,dx']);
    });

    test('表格 cell 内单行公式不回退（cell 不跨行）', () {
      const md = '| A | B |\n| --- | --- |\n| \$\$x\$\$ | \$y\$ |';

      final elements = MarkdownParser.parse(md);

      expect(_allFormulas(elements).map((f) => f.latex).toList(), ['x', 'y']);
    });
  });

  group('优雅降级：坏输入不抛异常', () {
    test(r'坏行内公式 $\sqrt[[[broken$ 降级为源码文本', () {
      final elements = MarkdownParser.parse(r'$\sqrt[[[broken$');

      // 解析不抛异常；坏公式不会产出公式元素（由 FormulaRenderer 走源码降级）
      expect(elements, isNotEmpty);
      final formulas = _allFormulas(elements);
      expect(formulas.where((f) => f.displayMode), isEmpty);
    });

    test(r'未闭合 $$ 不产出 display 公式，也不抛异常', () {
      final elements = MarkdownParser.parse('前文\n\n\$\$\n\\int_0^1 x dx');

      expect(elements, isNotEmpty);
      expect(_allFormulas(elements).where((f) => f.displayMode), isEmpty);
      // 原文不丢失：仍以文本形式可见
      final text = elements
          .whereType<ParagraphElement>()
          .expand((p) => p.children)
          .whereType<TextElement>()
          .map((t) => t.text)
          .join();
      expect(text, contains(r'\int_0^1 x dx'));
    });

    test(r'孤立 $$ 定界行降级为文本且不吞掉后续段落', () {
      final elements = MarkdownParser.parse('前文\n\n\$\$\n\n后文');

      final formulas = _allFormulas(elements);
      expect(formulas.where((f) => f.displayMode), isEmpty);
      final texts = elements
          .whereType<ParagraphElement>()
          .expand((p) => p.children)
          .whereType<TextElement>()
          .map((t) => t.text)
          .join();
      expect(texts, contains('前文'));
      expect(texts, contains('后文'));
    });
  });
}
