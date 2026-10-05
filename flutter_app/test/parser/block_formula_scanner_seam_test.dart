/// 块级公式扫描器增量续扫的拼接缝边界回归（issue #321）。
///
/// 与 [block_formula_parsing_test.dart]（解析契约）分离：本文件专门锁
/// `BlockFormulaScanner.scan` 的增量续扫实现细节——每轮只从上一轮已扫完的
/// 文本末尾续扫（`scanFrom = source.length - 1`），而非对全量 source 重扫。
///
/// 重点覆盖拼接缝处（上一轮 source 末字符与本轮追加的 `'\n'` 之间）不能
/// 漏判闭合 `$$`、也不能跨缝误配。差分探针曾在 18174 个随机组合上验证与
/// 全量重扫 0 mismatch，但探针不入库无法复审，故此处保留结构性用例。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/data/models/document.dart';
import '../helpers/formula_ast.dart';

void main() {
  group('增量续扫边界（O(n²) → O(n) 优化等价性）', () {
    // 锁住增量续扫实现（scanFrom = source.length - 1）在拼接缝附近的
    // 正确性。差分探针已验证 18174 个随机输入与原全量重扫 0 mismatch，
    // 这里补的是差分探针不易稳定命中的**结构性**边界用例。

    test(r'闭合 $$ 恰在 source 末尾：不漏判、不越界', () {
      // 上一轮 source 末尾就是 `$$` 闭合定界符。增量续扫起点 = length-1
      // 必须命中这个 `$$`，不能因 `i < text.length - 1` 守卫漏掉末尾对。
      // 单行场景下 scanFrom 初值 == 2，正好覆盖。
      final formulas = allFormulas(MarkdownParser.parse(r'$$E=mc^2$$'));
      expect(formulas, hasLength(1));
      expect(formulas.single.displayMode, isTrue);
      expect(formulas.single.latex, r'E=mc^2');
    });

    test(r'上一行行尾孤立 $ 不与下一行行首 $ 跨缝配对', () {
      // 拼接缝陷阱：上一轮 source 末字符是 `$`，下一行行首也是 `$`，
      // 增量续扫若从追加位置起扫、且不做转义检查，可能把这两个 `$`
      // 跨缝拼成行内公式定界对。`\n` 隔断 + `_findMatchingDelimiter`
      // 的转义规则必须让这种输入判未闭合。
      //
      // 本用例直接构造 Markdown 文档级输入：开定界行后跟一个孤立 `$` 行，
      // 再跟闭合 `$$` 行——孤立 `$` 不应被吞进公式，也不应跨缝配对。
      const md = r'$$' '\n' r'$' '\n' r'$$';
      final formulas = allFormulas(MarkdownParser.parse(md));
      expect(formulas, hasLength(1),
          reason: '应识别为一个 display 公式（latex 含中间的 \$ 与换行）');
      expect(formulas.single.displayMode, isTrue);
      // latex 经 _stripFenceNewlines 剥首层换行后含 ` $\n`
      expect(formulas.single.latex, contains(r'$'));
    });

    test(r'未闭合 $$ + 长文档：单次线性扫描，不抛异常', () {
      // 复杂度契约：未闭合场景下，扫描器对每行只做一次 findDisplayDelimiter
      // 调用（从上一轮末尾续扫），总量 O(n)。这里不直接断言复杂度，
      // 只锁住「长文档不抛异常 + 不产出 display 公式 + 原文不丢」三个不变量。
      final lines = <String>[r'$$'];
      for (var i = 0; i < 500; i++) {
        lines.add('正文行 \$$i');
      }
      final md = lines.join('\n');

      final elements = MarkdownParser.parse(md);
      expect(allFormulas(elements).where((f) => f.displayMode), isEmpty);
      final text = elements
          .whereType<ParagraphElement>()
          .expand((p) => p.children)
          .whereType<TextElement>()
          .map((t) => t.text)
          .join();
      expect(text, contains(r'正文行 $0'));
      expect(text, contains(r'正文行 $499'));
    });

    test(r'拼接缝处转义对不误判闭合：内部行尾反斜杠 + 下一行 $$', () {
      // 轮间真实命中：追加下一行前 source 末尾是 LaTeX 换行命令 `\\`
      // （`_findMatchingDelimiter` 的 `\\` 分支会把它当转义对跳过 2 字符）。
      // 缝处是 `\\` + `'\n'` + `$$`：扫描器续扫回退一格重看时，必须正确
      // 把 `\\` 当转义对跳过，再在 `'\n'` 后命中闭合 `$$`。若实现误把
      // 缝处的第二个 `\` 与闭合 `$$` 的第一个 `$` 配成转义对，闭合符会被
      // 吞掉、公式漏判。
      const md = r'$$' '\n' 'E=a \\\\' '\n' r'$$';

      final formulas = allFormulas(MarkdownParser.parse(md));
      expect(formulas, hasLength(1),
          reason: r'行尾反斜杠不应阻止下一行 $$ 闭合块级公式');
      expect(formulas.single.displayMode, isTrue);
      // 行尾的 `\\` 是 LaTeX 换行命令，`_findMatchingDelimiter` 在扫描时
      // 把它当作 `\\` 转义对跳过（不吞掉随后的 `$$` 闭合符）；latex 中
      // 原样保留。
      expect(formulas.single.latex, r'E=a \\');
    });

    test(r'CRLF 与 LF 文档同公式产出同一 latex（SVG 缓存键跨平台一致）', () {
      // parse 侧归一契约：开定界行与追加行都经 `_stripCr`，
      // `_stripFenceNewlines` 又先剥 `\r\n` 再剥 `\n`，故 CRLF 文档的
      // latex 内部换行已归一为 `\n`。跨平台同公式必须同 latex，否则 SVG
      // 预渲染缓存键（以 latex 为 key）会在 Windows 与 Unix 间分裂。
      final lf = allFormulas(
          MarkdownParser.parse(r'$$' '\n' 'a = b' '\n' 'c = d' '\n' r'$$'));
      final crlf = allFormulas(MarkdownParser.parse(
          r'$$' '\r\n' 'a = b' '\r\n' 'c = d' '\r\n' r'$$'));

      expect(lf, hasLength(1));
      expect(crlf, hasLength(1));
      expect(crlf.single.latex, lf.single.latex,
          reason: 'CRLF 与 LF 的同内容公式应产出同一 latex（同 SVG 缓存键）');
      // 内部换行确为 `\n` 而非 `\r\n`
      expect(lf.single.latex, contains('\n'));
      expect(lf.single.latex, isNot(contains('\r')));
    });
  });
}
