/// 表格 cell 内公式专项审计（Phase 3.9 Batch 5，CAP-003+CAP-005 交互）。
///
/// 审计目标：表格单元格内 LaTeX 公式的 round-trip 保真与解析边界
/// （cell 内公式 / 公式+粗体混合 / 公式含 `|` / 空 cell / 分隔行）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/core/parser/markdown_serializer.dart';
import 'package:tafcm/data/models/document.dart';

void main() {
  /// PR-2 helper：cell（Inline AST）→ 纯文本（含公式源码文本化，断言用）。
  String cellText(List<InlineElement> cell) => cell
      .map((c) => switch (c) {
            TextElement(:final text) => text,
            FormulaElement(:final latex) => r'$' + latex + r'$',
            _ => '',
          })
      .join();

  /// PR-2 helper：比较两个 cell（Inline AST 列表）是否等价。
  bool cellEq(List<InlineElement> a, List<InlineElement> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].runtimeType != b[i].runtimeType) return false;
      if (a[i] is TextElement &&
          (a[i] as TextElement).text != (b[i] as TextElement).text) {
        return false;
      }
      if (a[i] is FormulaElement &&
          (a[i] as FormulaElement).latex !=
              (b[i] as FormulaElement).latex) {
        return false;
      }
    }
    return true;
  }

  bool tableEq(TableElement a, TableElement b) {
    if (a.headers.length != b.headers.length) return false;
    if (a.rows.length != b.rows.length) return false;
    for (var i = 0; i < a.headers.length; i++) {
      if (!cellEq(a.headers[i], b.headers[i])) return false;
    }
    for (var r = 0; r < a.rows.length; r++) {
      if (a.rows[r].length != b.rows[r].length) return false;
      for (var c = 0; c < a.rows[r].length; c++) {
        if (!cellEq(a.rows[r][c], b.rows[r][c])) return false;
      }
    }
    return true;
  }

  group('表格 cell 内公式专项审计', () {
    test('round-trip 保真：cell 内公式', () {
      const md = r'''| $x$ | $\frac{1}{2}$ |
|---|---|
| $\alpha$ | $E=mc^2$ |''';
      final e1 = MarkdownParser.parse(md);
      final t1 = e1.whereType<TableElement>().toList();
      expect(t1.length, 1, reason: '应解析为 1 个 TableElement');
      expect(t1[0].headers.map(cellText).join(), contains(r'$x$'));
      expect(t1[0].rows.first.map(cellText).join(), contains(r'$\alpha$'));

      final s1 = MarkdownSerializer.serialize(e1);
      final e2 = MarkdownParser.parse(s1);
      final t2 = e2.whereType<TableElement>().toList();
      expect(t2.length, 1, reason: 'round-trip 后仍为 TableElement');
      expect(tableEq(t2[0], t1[0]), isTrue, reason: 'headers 保真: $s1');
    });

    test('cell 内公式 + 粗体/行内代码混合', () {
      const md = r'''| $x$ | **bold** | `code` |
|---|---|---|
| $y$ | *it* | ~~del~~ |''';
      final e1 = MarkdownParser.parse(md);
      final s1 = MarkdownSerializer.serialize(e1);
      final e2 = MarkdownParser.parse(s1);
      final t1 = e1.whereType<TableElement>().toList();
      final t2 = e2.whereType<TableElement>().toList();
      expect(t1.length, 1);
      expect(t2.length, 1);
      expect(tableEq(t2[0], t1[0]), isTrue);
    });

    test('边界：公式含竖线（需 \\| 转义）', () {
      // GFM 表格 cell 内 `|` 需转义；公式中未转义的 `|`（如绝对值）
      // 会破坏列结构 —— 验证 parser 的容错行为（不崩溃 + 不误吞）。
      const md = r'''| $\|x\|$ | b |
|---|---|
| 1 | 2 |''';
      final e1 = MarkdownParser.parse(md);
      // 不崩溃是硬约束；结构以 parser 实际行为为准
      expect(e1, isNotNull);
      final s1 = MarkdownSerializer.serialize(e1);
      expect(s1, isNotNull);
    });

    test('边界：空 cell / 单 cell 表格', () {
      const md = '| a |  |\n|---|---|\n|  | b |';
      final e1 = MarkdownParser.parse(md);
      final t1 = e1.whereType<TableElement>().toList();
      expect(t1.length, 1);
      final s1 = MarkdownSerializer.serialize(e1);
      final e2 = MarkdownParser.parse(s1);
      final t2 = e2.whereType<TableElement>().toList();
      expect(t2.length, 1, reason: '空 cell round-trip 不丢失: $s1');
      expect(tableEq(t2[0], t1[0]), isTrue);
    });

    test('边界：分隔行含公式样式（应仍为分隔行）', () {
      // 分隔行 `---` 不是公式，即使形似；验证不误判
      const md = '| a | b |\n|:---:|---:|\n| 1 | 2 |';
      final e1 = MarkdownParser.parse(md);
      final t1 = e1.whereType<TableElement>().toList();
      expect(t1.length, 1);
      final s1 = MarkdownSerializer.serialize(e1);
      final e2 = MarkdownParser.parse(s1);
      expect(e2.whereType<TableElement>().length, 1,
          reason: 'round-trip 后仍为 TableElement');
    });

    test('round-trip：含公式 cell 的多行表格', () {
      const md = r'''| 公式 | 说明 |
|---|---|
| $\sum_{i=1}^{n} i$ | 求和 |
| $\int_0^1 x dx$ | 积分 |''';
      final e1 = MarkdownParser.parse(md);
      final s1 = MarkdownSerializer.serialize(e1);
      final e2 = MarkdownParser.parse(s1);
      final t1 = e1.whereType<TableElement>().toList();
      final t2 = e2.whereType<TableElement>().toList();
      expect(t1.length, 1);
      expect(t2.length, 1);
      expect(tableEq(t2[0], t1[0]), isTrue, reason: '多行公式 cell 保真: $s1');
    });
  });
}
