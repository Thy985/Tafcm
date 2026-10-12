/// #364 共享公式收集 dispatcher 单测。
///
/// 验证 [formulaElements] / [blockFormulas] 与重构前三处收集器
/// （pdf_exporter.collectAllFormulas / .collectAllFormulasByDisplayMode /
/// word_exporter._collectFormulas）的收集口径完全一致——本 PR 是纯重构
/// （0 行为变化），故此处逐条锁定「既有口径」而非「应有口径」。
///
/// 其中「Bold 子级不递归」一条尤其重要：它记录的是**继承自原三处实现**的
/// 约定（formula 是 leaf，由 markdown_parser 先抽公式再扫样式，故公式总是
/// 直接挂在块 children 上），不是本 dispatcher 新引入的语义。若未来要支持
/// Bold 内嵌公式，那属于行为变更，应另立 issue 并同步修改 dispatcher 与
/// 两处调用方，而不是在本 PR 静默扩展。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/domain/services/exporters/formula_collector.dart';

void main() {
  group('#364 formulaElements 元素类型覆盖', () {
    test('六种含公式的块元素全部命中', () {
      final els = <DocumentElement>[
        const ParagraphElement(children: [FormulaElement(latex: 'p')]),
        const ListElement(children: [FormulaElement(latex: 'l')]),
        const TableElement(
          headers: [[FormulaElement(latex: 'h')]],
          rows: [[[FormulaElement(latex: 'c')]]],
        ),
        const BlockquoteElement(children: [FormulaElement(latex: 'q')]),
        const HeadingElement(level: 2, children: [FormulaElement(latex: 'h2')]),
        const TaskListItemElement(children: [FormulaElement(latex: 't')]),
      ];

      final collected = formulaElements(els).map((f) => f.latex).toList();

      expect(
        collected,
        equals(const ['p', 'l', 'h', 'c', 'q', 'h2', 't']),
        reason: '类型集合 + 表头/cell 全覆盖，且与重构前三处收集器顺序一致',
      );
    });

    test('table 多表头多行列按 表头 → 行 → cell 顺序产出', () {
      const table = TableElement(
        headers: [
          [FormulaElement(latex: 'a')],
          [FormulaElement(latex: 'b')],
        ],
        rows: [
          [
            [FormulaElement(latex: 'r1c1')],
            [FormulaElement(latex: 'r1c2')],
          ],
          [[FormulaElement(latex: 'r2c1')]],
        ],
      );

      final collected = formulaElements([table]).map((f) => f.latex).toList();

      expect(
        collected,
        equals(const ['a', 'b', 'r1c1', 'r1c2', 'r2c1']),
      );
    });

    test('ADR-0029 嵌套列表任意深度递归', () {
      const nested = ListElement(
        children: [FormulaElement(latex: 'n1')],
        nested: [
          ListElement(
            children: [FormulaElement(latex: 'n2')],
            nested: [ListElement(children: [FormulaElement(latex: 'n3')])],
          ),
        ],
      );

      final collected = formulaElements([nested]).map((f) => f.latex).toList();

      expect(
        collected,
        equals(const ['n1', 'n2', 'n3']),
        reason: '不递归 nested 则深层公式漏收集 → 预渲染缓存 miss（round-3 漏补点）',
      );
    });

    test('无公式块元素被跳过，不产出、不崩溃', () {
      final els = <DocumentElement>[
        const CodeElement(code: r'$x^2$', language: 'text'),
        const MermaidElement(code: 'flowchart LR; A-->B'),
        const HorizontalRuleElement(),
        const TableElement(headers: [], rows: []),
        const ParagraphElement(children: [TextElement('纯文本 \$x\$')]),
      ];

      expect(formulaElements(els), isEmpty);
    });

    test('空元素列表返回空序列（不抛异常）', () {
      expect(formulaElements(const []), isEmpty);
    });

    test('多块混合按文档顺序产出，保留重复 latex（去重交给调用方）', () {
      final els = <DocumentElement>[
        const ParagraphElement(children: [
          TextElement('前'),
          FormulaElement(latex: 'f'),
          FormulaElement(latex: 'f'),
        ]),
        const ParagraphElement(children: [FormulaElement(latex: 'g')]),
      ];

      final collected = formulaElements(els).map((f) => f.latex).toList();

      expect(collected, equals(const ['f', 'f', 'g']));
    });

    test('displayMode 原样透传（调用方按 displayMode 分 Set 的契约）', () {
      const els = <DocumentElement>[
        ParagraphElement(children: [
          FormulaElement(latex: 'i', displayMode: false),
          FormulaElement(latex: 'b', displayMode: true),
        ]),
      ];

      final collected = formulaElements(els).toList();

      expect(collected, hasLength(2));
      expect(collected[0].displayMode, isFalse);
      expect(collected[1].displayMode, isTrue);
    });

    test('DocumentElement 全部 10 个子类型穷尽（新增类型必触发决策）', () {
      // 类型全集守门：把 DocumentElement 的全部子类型各喂一个，断言恰好 9 条
      // 公式产出。配合 dispatcher 的「无 default 分支」穷尽检查（新增子类型
      // 触发 non_exhaustive_switch_statement error），这条用例的价值是
      // **类型集合本身的变化**：
      // - 新增「含公式」块类型（如嵌套引用）：本测试先失败（数量不符），
      //   再经 case 补分支后改为断言新数量——决策显式化，不会静默漏收集。
      // - 新增「无公式」块类型：本测试同样先失败，提示在 dispatcher 补 skip
      //   分支，而非依赖某个 default 兜底。
      final els = <DocumentElement>[
        const ParagraphElement(children: [FormulaElement(latex: 'p')]),
        const ListElement(
          children: [FormulaElement(latex: 'l1')],
          nested: [ListElement(children: [FormulaElement(latex: 'l2')])],
        ),
        const TableElement(
          headers: [[FormulaElement(latex: 'h')]],
          rows: [[[FormulaElement(latex: 'c')]]],
        ),
        const BlockquoteElement(children: [FormulaElement(latex: 'q')]),
        const HeadingElement(level: 3, children: [FormulaElement(latex: 'g')]),
        const TaskListItemElement(children: [FormulaElement(latex: 't')]),
        const CodeElement(code: r'$x^2$', language: 'text'),
        const MermaidElement(code: 'flowchart LR; A-->B'),
        const EmptyLineElement(),
        const HorizontalRuleElement(),
      ];

      expect(els, hasLength(10), reason: 'DocumentElement 全部 10 个子类型');

      final collected = formulaElements(els).map((f) => f.latex).toList();

      expect(
        collected,
        equals(const ['p', 'l1', 'l2', 'h', 'c', 'q', 'g', 't']),
        reason: '6 类含公式块产出 8 条（列表含 nested 2 条），其余 4 类显式跳过',
      );
    });
  });

  group('#364 blockFormulas 单块接口', () {
    test('与 formulaElements 单元素列表口径一致', () {
      const element = TableElement(
        headers: [[FormulaElement(latex: 'h')]],
        rows: [[[FormulaElement(latex: 'c')]]],
      );

      final blockOnly = blockFormulas(element).map((f) => f.latex).toList();
      final listOnly =
          formulaElements([element]).map((f) => f.latex).toList();

      expect(blockOnly, equals(listOnly));
    });

    test('嵌套列表深度同样覆盖', () {
      const nested = ListElement(
        children: [FormulaElement(latex: 'n1')],
        nested: [ListElement(children: [FormulaElement(latex: 'n2')])],
      );

      expect(
        blockFormulas(nested).map((f) => f.latex).toList(),
        equals(const ['n1', 'n2']),
      );
    });
  });

  group('#364 继承口径锁定（纯重构，不扩展语义）', () {
    test('Bold 子级不递归——继承自原三处收集器的既定口径', () {
      // markdown_parser._parseInline 先抽 $$…$$ / $…$ 再扫 ** / * 样式，
      // 公式始终是块的直接子元素而非嵌套在 Bold/Italic 里；解析器也不会
      // 产出 BoldElement(children: [FormulaElement(...)]) 的结构。故三处
      // 收集器均为扁平遍历。
      //
      // 此断言锁定「本 PR 未改变收集口径」——若将来确需递归 Bold 子级，
      // 属行为变更，需另立 issue 同步修改 dispatcher 与两处调用方。
      const element = ParagraphElement(children: [
        FormulaElement(latex: 'leaf'),
        BoldElement(children: [FormulaElement(latex: 'nested')]),
        ItalicElement(children: [FormulaElement(latex: 'nested2')]),
      ]);

      final collected = blockFormulas(element).map((f) => f.latex).toList();

      expect(collected, equals(const ['leaf']));
    });
  });
}
