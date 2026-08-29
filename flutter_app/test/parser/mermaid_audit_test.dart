/// Mermaid 块专项审计（Phase 3.9 Batch 5，CAP-006 深化）。
///
/// 审计目标：Mermaid 代码块的 round-trip 保真与解析边界
/// （空块 / 无语言标注 / 尾随空格 / CRLF / 相邻块交互 / 内容含特殊字符）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/core/parser/markdown_serializer.dart';
import 'package:tafcm/data/models/document.dart';

void main() {
  group('Mermaid 块专项审计', () {
    test('round-trip 保真（graph/flowchart/sequence/class）', () {
      const cases = [
        '```mermaid\ngraph TD\n  A-->B\n```',
        '```mermaid\nflowchart LR\n  A[Start] --> B{Decide}\n  B -->|Yes| C[End]\n```',
        '```mermaid\nsequenceDiagram\n  Alice->>John: Hello\n  John-->>Alice: Hi\n```',
        '```mermaid\nclassDiagram\n  Animal <|-- Duck\n  Animal : +int age\n```',
        '```mermaid\ngraph TD\n  A[\"中文 节点\"] --> B[\"x < y\"]\n```',
      ];
      for (final md in cases) {
        final e1 = MarkdownParser.parse(md);
        expect(e1.whereType<MermaidElement>().length, 1,
            reason: '应解析为 1 个 MermaidElement: $md');
        final s1 = MarkdownSerializer.serialize(e1);
        final e2 = MarkdownParser.parse(s1);
        final m1 = e1.whereType<MermaidElement>().toList();
        final m2 = e2.whereType<MermaidElement>().toList();
        expect(m2.length, m1.length, reason: 'round-trip: $md');
        if (m1.isNotEmpty && m2.isNotEmpty) {
          expect(m2[0].code, m1[0].code, reason: 'Mermaid code 保真: $md');
        }
      }
    });

    test('边界：空 Mermaid 块', () {
      const md = '```mermaid\n```';
      final e1 = MarkdownParser.parse(md);
      final m = e1.whereType<MermaidElement>().toList();
      expect(m.length, 1, reason: '空 mermaid 块仍应识别为 MermaidElement');
      expect(m[0].code, isEmpty);
    });

    test('边界：无语言标注的 code block 不应误判为 Mermaid', () {
      const md = '```\ngraph TD\n  A-->B\n```';
      final e1 = MarkdownParser.parse(md);
      expect(e1.whereType<MermaidElement>().length, 0,
          reason: '无 mermaid 标注应为 CodeElement');
      expect(e1.whereType<CodeElement>().length, 1);
    });

    test('边界：mermaid 标注尾随空格', () {
      const md = '```mermaid \ngraph TD\n  A-->B\n```';
      final e1 = MarkdownParser.parse(md);
      final s1 = MarkdownSerializer.serialize(e1);
      final e2 = MarkdownParser.parse(s1);
      expect(e1.whereType<MermaidElement>().length, 1,
          reason: '```mermaid + 空格 应识别');
      expect(e2.whereType<MermaidElement>().length, 1,
          reason: 'round-trip 后仍为 MermaidElement');
    });

    test('边界：CRLF 混合', () {
      const md = '```mermaid\r\ngraph TD\r\n  A-->B\r\n```';
      final e1 = MarkdownParser.parse(md);
      final m1 = e1.whereType<MermaidElement>().toList();
      expect(m1.length, 1);
      expect(m1[0].code, contains('graph TD'),
          reason: 'code 不应残留 \\r');
      final s1 = MarkdownSerializer.serialize(e1);
      final e2 = MarkdownParser.parse(s1);
      expect(e2.whereType<MermaidElement>().length, 1);
    });

    test('边界：内容含反引号/尖括号/公式符号', () {
      const md = r'''```mermaid
graph TD
  A --> B
  B -->|"x `y` <z> $w$"| C
```''';
      final e1 = MarkdownParser.parse(md);
      final s1 = MarkdownSerializer.serialize(e1);
      final e2 = MarkdownParser.parse(s1);
      final m1 = e1.whereType<MermaidElement>().toList();
      final m2 = e2.whereType<MermaidElement>().toList();
      expect(m1.length, 1);
      expect(m2.length, 1, reason: 'round-trip 后仍为 MermaidElement');
      expect(m2[0].code, m1[0].code);
    });

    test('相邻块交互：Mermaid 紧邻列表/段落（无空行）', () {
      const md = '- item\n```mermaid\ngraph TD\n  A-->B\n```\ntrailing';
      final e1 = MarkdownParser.parse(md);
      final e2 = MarkdownParser.parse(MarkdownSerializer.serialize(e1));
      expect(e1.whereType<MermaidElement>().length, 1);
      expect(e2.whereType<MermaidElement>().length, 1,
          reason: '相邻块 round-trip 后 Mermaid 不丢失');
    });
  });
}
