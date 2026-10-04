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
import '../helpers/formula_ast.dart';

void main() {
  group(r'issue #321：多行 $$...$$ 块级公式', () {
    test(r'标准写法（$$ 定界行独占）解析为单个 display 公式元素', () {
      const md = '多行公式：\n\n'
          '\$\$\n'
          r'\int_0^\infty e^{-x^2} dx = \frac{\sqrt{\pi}}{2}'
          '\n'
          '\$\$';

      final elements = MarkdownParser.parse(md);
      final paragraph = pureFormulaParagraph(elements);

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
      final formulas = allFormulas(elements);

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
      expect(allFormulas(elements), hasLength(1));
      expect((paragraphs[1].children.single as FormulaElement).latex, 'E=mc^2');
      expect((paragraphs[2].children.single as TextElement).text, '后文');
    });

    test('开定界行紧邻非空文本（无空行）切成两个独立段落，不做 hard-break 合并', () {
      // 与上一个用例互补：那里开定界行前有**空行**，这里没有。
      // 块级公式分支追加公式段前会先 `flushParagraph()`，把紧邻的文本段 flush
      // 出去，二者成为两个独立元素而非合并段落——不经过 `pendingParagraph` 的
      // hard-break 合并逻辑（普通段落多行合并走那条路）。这是「公式自成一块
      // （独立卡片）」的刻意选择，锁住以免后续改成合并语义时静默回退。
      const md = '前一行正文\n\$\$\nE=mc^2\n\$\$';

      final elements = MarkdownParser.parse(md);
      final paragraphs = elements.whereType<ParagraphElement>().toList();

      expect(paragraphs, hasLength(2),
          reason: '文本段与公式段应各自独立，不合并为一个段落');
      expect((paragraphs[0].children.single as TextElement).text, '前一行正文');
      final paragraph = pureFormulaParagraph(elements);
      expect(paragraph, paragraphs[1]);
      final formula = paragraph.children.single as FormulaElement;
      expect(formula.displayMode, isTrue);
      expect(formula.latex, 'E=mc^2');
    });

    test('多个块级公式块互不吞并', () {
      const md = '\$\$\na=1\n\$\$\n\n\$\$\nb=2\n\$\$';

      final elements = MarkdownParser.parse(md);
      final formulas = allFormulas(elements);

      expect(formulas.map((f) => f.latex).toList(), ['a=1', 'b=2']);
      expect(formulas.every((f) => f.displayMode), isTrue);
    });

    test('CRLF 文档同样解析为单个公式且 latex 无 \\r 残留', () {
      const md = '前置\r\n\r\n\$\$\r\nE=mc^2\r\n\$\$\r\n';

      final elements = MarkdownParser.parse(md);
      final formula = pureFormulaParagraph(elements).children.single
          as FormulaElement;

      expect(formula.displayMode, isTrue);
      expect(formula.latex, 'E=mc^2');
      expect(formula.latex.contains('\r'), isFalse);
    });

    test(r'代码块内的 $$ 不被当作公式（fence 优先级不变）', () {
      const md = '前文\n\n```\n\$\$\nE=mc^2\n\$\$\n```\n';

      final elements = MarkdownParser.parse(md);

      expect(allFormulas(elements), isEmpty);
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
      expect(allFormulas(second).single.latex, 'a=1\nb=2',
          reason: 'round-trip 后多行正文不得丢失');
    });

    test('序列化回写形态（开闭定界符跨行）可被重新解析', () {
      // InlineSerializer 把含换行的 latex 写成 `$$a\nb$$` 单块，
      // 该形态必须同样被识别为一个公式，否则保存后再打开会退化成源码文本。
      const md = r'$$\begin{aligned}' '\n' r'a &= b' '\n' r'\end{aligned}$$';

      final formulas = allFormulas(MarkdownParser.parse(md));

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

    test(r'开定界行内已有正文保留，不静默丢弃', () {
      // trim 只剥首尾空白：`$$ E=mc^2` 的正文随 source 进入解析。
      // 锁住此契约是因为「定界符后紧跟正文」既可能是手写首行公式，
      // 也可能是 InlineSerializer 的回写形态——若当成非法形态降级为文本，
      // 保存后再打开就会把公式退化成源码字面量。
      const md = r'$$ E=mc^2' '\n' r'$$';

      final formulas = allFormulas(MarkdownParser.parse(md));

      expect(formulas, hasLength(1));
      expect(formulas.single.displayMode, isTrue);
      expect(formulas.single.latex, r' E=mc^2',
          reason: '开定界行内正文必须保留在 latex 中（含定界符后的空格）');
    });

    test(r'序列化回写形态的开定界行内正文同样保留', () {
      // 与上一个用例合起来锁住「不因为定界符后紧跟正文而丢内容」。
      final elements = MarkdownParser.parse(
        r'$$\begin{aligned}' '\n' r'\alpha' '\n' r'\end{aligned}$$',
      );

      final paragraph = pureFormulaParagraph(elements);
      expect((paragraph.children.single as FormulaElement).latex,
          r'\begin{aligned}' '\n' r'\alpha' '\n' r'\end{aligned}');
    });

    test(r'开定界行允许前导空白（indent 未识别为代码块）', () {
      // 刻意契约：本解析器只识别 ``` fence，无 4 空格缩进代码块分支，
      // 缩进行的 `$$` 仍按普通正文 → 块级公式处理。若日后引入 indent 代码块，
      // 必须同步收紧 BlockFormulaScanner 的判定，否则这里会静默失败。
      const md = '    \$\$\nE=mc^2\n\$\$';

      final formulas = allFormulas(MarkdownParser.parse(md));

      expect(formulas, hasLength(1),
          reason: '前导缩进的块级公式仍应被识别，不落入代码块/正文');
      expect(formulas.single.latex, r'E=mc^2');
    });

    test(r'空 latex 对称：$$\n$$ 与 $$$$ 同样解析为空 display 公式', () {
      // 刻意选择：空块按公式卡片渲染，而非降级为文本。
      // 若改为降级，必须同时改两条路径，否则同一内容不同写法走不同渲染路径，
      // 保存-重载 round-trip 会在文本与卡片之间翻转。
      final fromBlock = allFormulas(MarkdownParser.parse('\$\$\n\$\$'));
      final fromSingleLine = allFormulas(MarkdownParser.parse(r'$$$$'));

      expect(fromBlock, hasLength(1));
      expect(fromBlock.single.displayMode, isTrue);
      expect(fromBlock.single.latex, isEmpty);
      expect(fromSingleLine, hasLength(1));
      expect(fromSingleLine.single.displayMode, isTrue);
      expect(fromSingleLine.single.latex, isEmpty);
    });

    test('extractFormulas 的 display latex 规范化不移动 start/end', () {
      // extractFormulas 是 public API：display 分支的 latex 经
      // _stripFenceNewlines 归一，不再保证是原文逐字子串；
      // 但 start/end 必须仍指原文区间，否则依赖下标做二次处理的调用方会错位。
      const text = '前缀 \$\$\nE=mc^2\n\$\$ 后缀';

      final match = FormulaExtractor.extractFormulas(text).single;

      expect(match.displayMode, isTrue);
      expect(match.latex, r'E=mc^2', reason: '首尾各剥一层换行');
      expect(text.substring(match.start, match.end),
          r'$$' '\n' r'E=mc^2' '\n' r'$$',
          reason: 'start/end 仍指向原文区间');
      expect(text[match.start], r'$');
      expect(text[match.end - 1], r'$');
    });
  });

  group('不回退：既有公式行为保持不变', () {
    test(r'单行 $$...$$ 仍是单个 display 公式', () {
      final elements = MarkdownParser.parse(r'$$\int_0^1 x^2 dx$$');

      final paragraph = pureFormulaParagraph(elements);
      final formula = paragraph.children.single as FormulaElement;
      expect(formula.displayMode, isTrue);
      expect(formula.latex, r'\int_0^1 x^2 dx');
    });

    test('单行多段公式互不吞并', () {
      final elements = MarkdownParser.parse('前 \$\$a\$\$ 中 \$\$b\$\$ 后');

      final formulas = allFormulas(elements);
      expect(formulas.map((f) => f.latex).toList(), ['a', 'b']);
      expect(formulas.every((f) => f.displayMode), isTrue);
    });

    test(r'行内 $...$ 仍为 inline 公式且不被跨行配对', () {
      final elements = MarkdownParser.parse('行内 \$x^2\$ 结束');

      final formulas = allFormulas(elements);
      expect(formulas, hasLength(1));
      expect(formulas.single.latex, 'x^2');
      expect(formulas.single.displayMode, isFalse);
    });

    test('行内公式与多行块级公式混排各自保持 displayMode', () {
      const md = '行内 \$E=mc^2\$。\n\n\$\$\n\\int_0^1 x\\,dx\n\$\$';

      final formulas = allFormulas(MarkdownParser.parse(md));

      expect(formulas.map((f) => f.displayMode).toList(), [false, true]);
      expect(formulas.map((f) => f.latex).toList(), ['E=mc^2', r'\int_0^1 x\,dx']);
    });

    test('表格 cell 内单行公式不回退（cell 不跨行）', () {
      const md = '| A | B |\n| --- | --- |\n| \$\$x\$\$ | \$y\$ |';

      final elements = MarkdownParser.parse(md);

      expect(allFormulas(elements).map((f) => f.latex).toList(), ['x', 'y']);
    });

    test('表格后紧邻多行块级公式（无空行）：表格与公式块各自独立', () {
      // 块级公式分支位于表格分支**之前**，而表格是流式解析（currentTable 挂起、
      // 到非 `|` 行才 flushTable）。本用例锁住「表格行后紧邻多行 `$$...$$` 块」
      // 的边界：`$$` 行触发公式分支先 flushTable()，随后收集公式块——二者不得
      // 合并，也不得因分支顺序调整而静默回归。
      const md = '| a | b |\n| --- | --- |\n| x | y |\n\$\$\nE=mc^2\n\$\$';

      final elements = MarkdownParser.parse(md);

      expect(elements, hasLength(2),
          reason: '表格与公式段应各自独立，中间无空行也不合并');
      expect(elements[0], isA<TableElement>());
      final table = elements[0] as TableElement;
      expect(table.headers, hasLength(2));
      expect(table.rows, hasLength(1));

      final formulas = allFormulas(elements);
      expect(formulas, hasLength(1));
      expect(formulas.single.displayMode, isTrue);
      expect(formulas.single.latex, 'E=mc^2');
    });
  });

  group('优雅降级：坏输入不抛异常', () {
    test(r'坏行内公式 $\sqrt[[[broken$ 降级为源码文本', () {
      final elements = MarkdownParser.parse(r'$\sqrt[[[broken$');

      // 解析不抛异常；坏公式不会产出公式元素（由 FormulaRenderer 走源码降级）
      expect(elements, isNotEmpty);
      final formulas = allFormulas(elements);
      expect(formulas.where((f) => f.displayMode), isEmpty);
    });

    test(r'未闭合 $$ 不产出 display 公式，也不抛异常', () {
      final elements = MarkdownParser.parse('前文\n\n\$\$\n\\int_0^1 x dx');

      expect(elements, isNotEmpty);
      expect(allFormulas(elements).where((f) => f.displayMode), isEmpty);
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

      final formulas = allFormulas(elements);
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
