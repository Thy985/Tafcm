/// issue #336 批次 C 回归：解析器代码卫生缺陷（P3）。
///
/// 与既有 parser 测试的区别：本文件只覆盖 #336 静态审计出的**边界退化**场景，
/// 不重复 round-trip / 全量语法覆盖（见 edge_case_test / roundtrip_fuzz_test）。
/// 覆盖项：
///   1. CRLF 文件代码块内容逐行残留 `\r`
///   2. 单独一行竖线触发 RangeError 并误报 onError
///   3. 未闭合代码块在 EOF 的收尾不对称
///   5. 隐式公式提取误伤普通散文
///
/// 断言约定：`DocumentElement` 子类未实现 `operator==`（身份比较），
/// 而 [MarkdownSerializer.serialize] 遇 `EmptyLineElement` 会抛
/// `is not serializable as a Block`（它是块分隔符，不参与序列化）。
/// 故 AST 结构相等一律用 [areEqual]：逐元素比 runtimeType + toString。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/parser/formula_extractor.dart';
import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/data/models/document.dart';

/// 逐元素结构比较（避免 serialize 遇 EmptyLineElement 抛错）。
bool areEqual(List<DocumentElement> a, List<DocumentElement> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].runtimeType != b[i].runtimeType) return false;
    if (a[i].toString() != b[i].toString()) return false;
  }
  return true;
}

void main() {
  group('#336-1 CRLF 代码块不残留 \\r', () {
    test('CRLF 包裹的 js 代码块：code 尾部无 \\r', () {
      const md = '```js\r\nconst a = 1;\r\nconst b = 2;\r\n```\r\n';
      final code = MarkdownParser.parse(md).whereType<CodeElement>().toList();
      expect(code, hasLength(1), reason: '应产出单个代码块');
      expect(code[0].code, 'const a = 1;\nconst b = 2;',
          reason: 'CRLF 行尾的 \\r 应被剥离，多行内容以 \\n 连接');
    });

    test('CRLF 文档与 LF 文档产出完全一致的 AST', () {
      const lf = '# H1\n\n```mermaid\ngraph TD\n  A-->B\n```\n\n- [ ] task';
      expect(
        areEqual(
          MarkdownParser.parse(lf),
          MarkdownParser.parse(lf.replaceAll('\n', '\r\n')),
        ),
        isTrue,
        reason: 'CRLF 与 LF 是同一文档，AST 必须逐元素相等',
      );
    });

    test('CRLF 输入的 mermaid 代码内容与 LF 完全一致（不含 \\r）', () {
      const lf = '```mermaid\ngraph TD\n  A-->B\n```';
      final codeOf = (String md) =>
          MarkdownParser.parse(md).whereType<MermaidElement>().first.code;
      expect(codeOf(lf.replaceAll('\n', '\r\n')), codeOf(lf),
          reason: 'CRLF 围栏的代码正文应与 LF 逐字节一致');
      expect(codeOf(lf.replaceAll('\n', '\r\n')), isNot(contains('\r')));
    });
  });

  group('#336-2 单竖线行不触发 RangeError / 不误报 onError', () {
    test('单独一行 | 解析不崩溃且无错误上报', () {
      final errors = <Object>[];
      final elements = MarkdownParser.parse(
        '|',
        onError: (line, error, lineText) => errors.add(error),
      );
      expect(errors, isEmpty,
          reason: '单竖线行是普通内容，不应进入错误降级路径');
      expect(elements, isNotEmpty, reason: '该行应降级为段落文本而非丢弃');
    });

    test('各类单竖线 / 边界输入均不触发 RangeError', () {
      var reported = 0;
      for (final input in <String>['|', '||', '|-', '|-|', ' ', '| |']) {
        MarkdownParser.parse(input, onError: (_, error, ___) => reported++);
      }
      expect(reported, 0,
          reason: '上述边界输入均不应触发解析错误上报（原实现 substring(1,0) 抛 RangeError）');
    });

    test('合法表格仍正常解析（守卫未误伤正常路径）', () {
      final tables = MarkdownParser.parse('| a | b |\n| --- | --- |\n| 1 | 2 |\n')
          .whereType<TableElement>()
          .toList();
      expect(tables, hasLength(1));
      expect(tables[0].headers, hasLength(2));
      expect(tables[0].rows, hasLength(1));
      expect(tables[0].rows[0], hasLength(2));
    });
  });

  group('#336-3 未闭合代码块在 EOF 与闭合路径对称', () {
    test('未闭合的 mermaid 围栏产出 MermaidElement（而非 CodeElement）', () {
      final elements = MarkdownParser.parse('```mermaid\ngraph TD\n  A-->B\n');
      expect(elements.whereType<MermaidElement>(), hasLength(1),
          reason: '未闭合围栏也应走 mermaid 渲染路径');
      expect(elements.whereType<CodeElement>(), isEmpty,
          reason: '不应落回 CodeElement(language: mermaid) 走不同渲染路径');
    });

    test('未闭合的空代码块保真产出，与闭合空块产出同一 AST', () {
      final open = MarkdownParser.parse('```mermaid\n');
      final closed = MarkdownParser.parse('```mermaid\n```');
      expect(open.whereType<MermaidElement>(), hasLength(1),
          reason: '未闭合空块不应整体丢失（闭合空块是特意保真的）');
      expect(closed.whereType<MermaidElement>(), hasLength(1));
      expect(open, hasLength(1),
          reason: '未闭合围栏不得额外多产出元素');
      expect(areEqual(open, closed), isTrue,
          reason: '空代码块的未闭合与闭合形态应产出同一 AST');
    });

    test('未闭合的普通代码块保留已收集内容', () {
      final code = MarkdownParser.parse('```js\nconst a = 1;')
          .whereType<CodeElement>()
          .toList();
      expect(code, hasLength(1));
      expect(code[0].language, 'js');
      expect(code[0].code, 'const a = 1;');
    });
  });

  group('#336-5 隐式公式不误伤普通散文', () {
    test('散文中的 max(a,b) 不被提取为公式', () {
      expect(FormulaExtractor.extractFormulas('we compute max(a,b) here'),
          isEmpty,
          reason: '逗号多参的括号形式是散文函数调用常态，不应判为公式');
    });

    test('log / min / det 的多参括号形式同样不误伤', () {
      for (final text in <String>[
        'take log(x, y) of the ratio',
        'we need min(a, b, c) here',
        'the det(M, N) is nonzero',
      ]) {
        expect(FormulaExtractor.extractFormulas(text), isEmpty,
            reason: '"$text" 应视为散文');
      }
    });

    test('花括号形式仍是刻意特性（隐式 LaTeX 保留，含逗号）', () {
      final formulas = FormulaExtractor.extractFormulas('max{x, y}');
      expect(formulas, hasLength(1));
      expect(formulas[0].latex, r'\max{x, y}');
    });

    test('守卫只收窄括号形式：含逗号括号拦下、花括号保留', () {
      expect(FormulaExtractor.extractFormulas('max(a, b)'), isEmpty,
          reason: '含逗号的括号形式按散文处理');
      expect(FormulaExtractor.extractFormulas('max{a, b}'), isNotEmpty,
          reason: '含逗号的花括号形式是 LaTeX 惯用写法，仍应提取');
    });

    test('单参括号形式仍被提取（守卫只拦逗号 / 空白）', () {
      expect(FormulaExtractor.extractFormulas('ln(e)'), isNotEmpty);
      expect(FormulaExtractor.extractFormulas('cos(x)'), isNotEmpty);
    });
  });
}
