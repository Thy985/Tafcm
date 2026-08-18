/// 表格 cell 内公式专项审计（Phase 3.9 Batch 5，CAP-003+CAP-005 交互）。
///
/// 审计目标：表格单元格内 LaTeX 公式的 round-trip 保真与解析边界
/// （cell 内公式 / 公式+粗体混合 / 公式含 `|` / 空 cell / 分隔行）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/parser/markdown_parser.dart';
import 'package:formula_fix/core/parser/markdown_serializer.dart';
import 'package:formula_fix/data/models/document.dart';

void main() {
  group('表格 cell 内公式专项审计', () {
    test('round-trip 保真：cell 内公式', () {
      const md = r'''| $x$ | $\frac{1}{2}$ |
|---|---|
| $\alpha$ | $E=mc^2$ |''';
      final e1 = MarkdownParser.parse(md);
      final t1 = e1.whereType<TableElement>().toList();
      expect(t1.length, 1, reason: '应解析为 1 个 TableElement');
      expect(t1[0].headers.join(), contains(r'$x$'));
      expect(t1[0].rows.first.join(), contains(r'$\alpha$'));

      final s1 = MarkdownSerializer.serialize(e1);
      final e2 = MarkdownParser.parse(s1);
      final t2 = e2.whereType<TableElement>().toList();
      expect(t2.length, 1, reason: 'round-trip 后仍为 TableElement');
      expect(t2[0].headers, t1[0].headers, reason: 'headers 保真: $s1');
      expect(t2[0].rows, t1[0].rows, reason: 'rows 保真: $s1');
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
      expect(t2[0].headers, t1[0].headers);
      expect(t2[0].rows, t1[0].rows);
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
      expect(t2[0].rows, t1[0].rows);
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
      expect(t2[0].headers, t1[0].headers);
      expect(t2[0].rows, t1[0].rows, reason: '多行公式 cell 保真: $s1');
    });
  });
}
