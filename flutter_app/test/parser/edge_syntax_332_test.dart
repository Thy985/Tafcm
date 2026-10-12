/// issue #332：QA 2026-10-04 边界语法巡检（动态测试 Agent C）——本批 3 项
/// 解析修复的回归测试：
///
/// 1. Setext 标题（`====` / `----` 紧随段落 → HeadingElement）
/// 2. 四空格缩进代码块（缩进 ≥4 列连续行 → CodeElement，language null）
/// 3. 粗斜体 `***text***`（→ BoldElement[ItalicElement]，不再残留多余 `*`）
///
/// 本批**未含**（另立 follow-up，各自需模型层或产品决策）：嵌套引用 `> >`、
/// 脚注 `[^1]`、HTML 块与行内 HTML、转义序列 `\_`（详见 #332 备注与 PR）。
///
/// 断言覆盖新行为 + 对照项无回归：`**加粗**` / `*斜体*` 不受粗斜体影响；
/// 嵌套列表（2 空格缩进）不被缩进代码块劫持；空行分隔的 `---` 仍是分隔线。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/editing/block_serializer.dart';
import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/core/parser/markdown_serializer.dart';
import 'package:tafcm/data/models/document.dart';

void main() {
  group('issue #332 Setext 标题', () {
    test('`====` 紧随段落 → HeadingElement level 1，内容为段落文本', () {
      final els = MarkdownParser.parse('Tafcm 标题\n====');
      expect(els, hasLength(1));
      final h = els.single as HeadingElement;
      expect(h.level, 1);
      expect(InlineSerializer.serialize(h.children), 'Tafcm 标题');
    });

    test('`----` 紧随段落 → HeadingElement level 2', () {
      final els = MarkdownParser.parse('子标题\n----');
      expect(els, hasLength(1));
      expect((els.single as HeadingElement).level, 2);
    });

    test('空行分隔的 `---` 仍是分隔线（非 Setext，无回归）', () {
      final els = MarkdownParser.parse('段落\n\n---');
      expect(els.whereType<HorizontalRuleElement>(), hasLength(1));
      expect(els.whereType<HeadingElement>(), isEmpty);
      expect(els.whereType<ParagraphElement>(), hasLength(1));
    });

    test('多行段落后的 `---` 回退为分隔线（单行限制，保 round-trip 稳定）', () {
      // `line1\nline2\n---`：多行段落升为 Setext 标题会让 ATX 序列化
      // `## line1\nline2` 把 line2 脱出标题（破坏不动点），故单行限制下
      // 回退为 段落 + 分隔线。此为已知 CommonMark 偏差（见 parse() 注释）。
      final els = MarkdownParser.parse('line1\nline2\n---');
      expect(els.whereType<HorizontalRuleElement>(), hasLength(1));
      expect(els.whereType<HeadingElement>(), isEmpty);
      expect(els.whereType<ParagraphElement>(), hasLength(1));
    });

    test('无前导段落时 `=` 行不误识别为标题', () {
      // 段落行必须是真实文本；`===` 独立成行（前面是空行或文件头）不是 Setext。
      final els = MarkdownParser.parse('\n=== 非纯分隔行');
      expect(els.whereType<HeadingElement>(), isEmpty);
    });

    test('round-trip：Setext 标题序列化为 ATX 标题后重解析仍为同级别标题', () {
      final els = MarkdownParser.parse('标题\n====');
      final serialized = MarkdownSerializer.serialize(els);
      expect(serialized, '# 标题');
      final reparsed = MarkdownParser.parse(serialized);
      expect(reparsed.single, isA<HeadingElement>());
      expect((reparsed.single as HeadingElement).level, 1);
      expect(InlineSerializer.serialize(
          (reparsed.single as HeadingElement).children), '标题');
    });
  });

  group('issue #332 四空格缩进代码块', () {
    test('连续缩进行收为 CodeElement（language null，剥离前导 4 空格）', () {
      final els = MarkdownParser.parse('    int x = 1;\n    if (x) { ok }');
      expect(els, hasLength(1));
      final c = els.single as CodeElement;
      expect(c.language, isNull);
      expect(c.code, 'int x = 1;\nif (x) { ok }');
    });

    test('空行分隔的独立缩进块不被误并入段落', () {
      final els = MarkdownParser.parse('intro\n\n    code line\n\nafter');
      final types = els.map((e) => e.runtimeType).toList();
      expect(types, [
        ParagraphElement,
        EmptyLineElement,
        CodeElement,
        EmptyLineElement,
        ParagraphElement,
      ]);
      expect((els[2] as CodeElement).code, 'code line');
    });

    test('缩进代码块不能打断段落（CommonMark）：续行并入段落', () {
      final els = MarkdownParser.parse('text\n    x');
      expect(els.whereType<CodeElement>(), isEmpty);
      final p = els.single as ParagraphElement;
      expect(InlineSerializer.serialize(p.children), 'text\nx');
    });

    test('Tab 缩进同样识别为代码块', () {
      final els = MarkdownParser.parse('\tcode1\n\tcode2');
      expect(els.single, isA<CodeElement>());
      expect((els.single as CodeElement).code, 'code1\ncode2');
    });

    test('round-trip：缩进代码块序列化为围栏块，重解析后内容一致', () {
      const src = '    line1\n    line2';
      final serialized = MarkdownSerializer.serialize(MarkdownParser.parse(src));
      expect(serialized, '```\nline1\nline2\n```');
      final reparsed = MarkdownParser.parse(serialized);
      expect(reparsed.single, isA<CodeElement>());
      expect((reparsed.single as CodeElement).code, 'line1\nline2');
    });

    test('对照：2 空格嵌套列表不被缩进代码块劫持（无回归）', () {
      final els = MarkdownParser.parse('- a\n  - b\n    - c');
      expect(els.whereType<CodeElement>(), isEmpty);
      // buildNestedTree 把 3 行合并为单个 ListElement（a），其 nested 链
      // b → c 共 2 层（ADR-0029）；验证结构完整、未被代码块拆散。
      expect(els.whereType<ListElement>(), hasLength(1));
      final a = els.whereType<ListElement>().single;
      expect(a.nested, hasLength(1));
      final b = a.nested.single;
      expect(b.nested, hasLength(1));
    });
  });

  group('issue #332 粗斜体 ***text***', () {
    test('***text*** → BoldElement[ItalicElement[Text]]，无残留星号', () {
      final inlines = MarkdownParser.parseInline('***粗斜体***');
      expect(inlines, hasLength(1));
      final bold = inlines.single as BoldElement;
      final inner = bold.children.single;
      expect(inner, isA<ItalicElement>());
      expect(InlineSerializer.serialize((inner as ItalicElement).children),
          '粗斜体');
    });

    test('对照：**加粗** 仍为 BoldElement（无回归）', () {
      final inlines = MarkdownParser.parseInline('**加粗**');
      final bold = inlines.single as BoldElement;
      expect(bold.children.whereType<ItalicElement>(), isEmpty);
    });

    test('对照：*斜体* 仍为 ItalicElement（无回归）', () {
      final inlines = MarkdownParser.parseInline('*斜体*');
      expect(inlines.single, isA<ItalicElement>());
    });

    test('行内混合：粗斜体与普通文本并存', () {
      final inlines = MarkdownParser.parseInline('前 ***中*** 后');
      expect(inlines.whereType<BoldElement>(), hasLength(1));
      expect(inlines.whereType<TextElement>(), hasLength(2));
    });

    test('round-trip：Bold[Italic[x]] 序列化为 ***x***', () {
      final inlines = MarkdownParser.parseInline('***x***');
      expect(InlineSerializer.serialize(inlines), '***x***');
    });

    test('未闭合 ***x 不误识别（不崩溃，原样保留）', () {
      final inlines = MarkdownParser.parseInline('***x 未闭合');
      expect(inlines.whereType<BoldElement>(), isEmpty);
      expect(inlines.whereType<TextElement>().map((t) => t.text).join(),
          contains('***'));
    });
  });
}
