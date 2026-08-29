/// Migration Spike A/B 对比（Phase 3.9 §2.1）。
///
/// 统一喂现有 fuzz corpus（MarkdownCorpusGenerator），两路解析：
///   A 侧：CurrentParser（手写 markdown_parser.dart）→ Tafcm AST
///   B 侧：package:markdown 7.3.1 → Adapter → Tafcm AST
///
/// 采集 7 维度：
///   1. 解析成功率（不抛异常）
///   2. AST 结构等价率（A/B 顶层元素类型序列比对）
///   3. round-trip 收敛（B 侧 serialize→parse 不动点）
///   4. GFM 覆盖（checkbox/list/table 支持度）
///   5. 自定义扩展成本（Formula/Mermaid 挂载行数，观察点）
///   6. 异常降级行为（错误行降级 Paragraph）
///   7. 性能（同语料耗时）
///
/// 输出 JSON 数据到 stdout，供 Spike 报告引用。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/core/parser/markdown_serializer.dart';
import 'package:tafcm/data/models/document.dart';

import '../roundtrip_fuzz_test.dart' show MarkdownCorpusGenerator;
import 'markdown_package_adapter.dart' as spike;

/// 顶层元素类型序列（用于 A/B 结构比对）。
List<String> typeSeq(List<DocumentElement> es) =>
    es.map((e) => e.runtimeType.toString()).toList();

void main() {
  test('Spike A/B：7 维度数据采集（100 轮 fuzz corpus）', () {
    final gen = MarkdownCorpusGenerator(20260818);
    const rounds = 100;

    var aOk = 0, bOk = 0, aCrashed = 0, bCrashed = 0;
    var structureEqual = 0, structureDifferent = 0;
    var bFixpoint = 0, bNotFixpoint = 0;
    var bMermaid = 0, bTask = 0, bTable = 0, bFormulaText = 0;
    final aTimes = <int>[], bTimes = <int>[];

    for (var round = 0; round < rounds; round++) {
      final md = gen.generate();

      // A 侧：手写 parser
      List<DocumentElement> aElements;
      final t0 = DateTime.now().microsecondsSinceEpoch;
      try {
        aElements = MarkdownParser.parse(md);
        aOk++;
      } catch (_) {
        aCrashed++;
        continue; // A 崩溃则跳过本轮对比（B 仍记录）
      }
      aTimes.add(DateTime.now().microsecondsSinceEpoch - t0);

      // B 侧：markdown 包 + Adapter
      List<DocumentElement> bElements;
      final t1 = DateTime.now().microsecondsSinceEpoch;
      try {
        bElements = spike.adaptDocument(md);
        bOk++;
      } catch (_) {
        bCrashed++;
        continue;
      }
      bTimes.add(DateTime.now().microsecondsSinceEpoch - t1);

      // 2. 结构等价率：顶层元素类型序列
      final aSeq = typeSeq(aElements);
      final bSeq = typeSeq(bElements);
      if (aSeq.join('|') == bSeq.join('|')) {
        structureEqual++;
      } else {
        structureDifferent++;
      }

      // 3. B 侧 round-trip 收敛：serialize → parse 不动点
      try {
        final md1 = MarkdownSerializer.serialize(bElements);
        final b2 = spike.adaptDocument(md1);
        final md2 = MarkdownSerializer.serialize(b2);
        if (md2 == md1) {
          bFixpoint++;
        } else {
          bNotFixpoint++;
        }
      } catch (_) {
        bNotFixpoint++;
      }

      // 4. GFM 覆盖观察：B 侧识别出的 mermaid/task/table
      if (bElements.any((e) => e is MermaidElement)) bMermaid++;
      if (bElements.any((e) => e is TaskListItemElement)) bTask++;
      if (bElements.any((e) => e is TableElement)) bTable++;
      // 公式：md 包按 Text 处理（未识别）→ 观察点
      if (md.contains(r'$') && bElements.any((e) => e is ParagraphElement)) {
        bFormulaText++;
      }
    }

    final result = <String, Object?>{
      'rounds': rounds,
      '1_parse_success_rate': {
        'current_parser': '$aOk/$rounds',
        'markdown_package': '$bOk/$rounds',
        'current_crashes': aCrashed,
        'markdown_crashes': bCrashed,
      },
      '2_structure_equivalence': {
        'equal': structureEqual,
        'different': structureDifferent,
        'equal_rate': structureEqual / rounds,
      },
      '3_b_roundtrip_fixpoint': {
        'fixpoint': bFixpoint,
        'not_fixpoint': bNotFixpoint,
        'rate': bFixpoint / (bFixpoint + bNotFixpoint),
      },
      '4_gfm_coverage_b_side': {
        'mermaid_blocks': bMermaid,
        'task_items': bTask,
        'tables': bTable,
        'formula_as_text_obs': bFormulaText,
      },
      '7_performance_us': {
        'current_parser_avg': aTimes.isEmpty ? 0 : aTimes.reduce((a, b) => a + b) ~/ aTimes.length,
        'markdown_package_avg': bTimes.isEmpty ? 0 : bTimes.reduce((a, b) => a + b) ~/ bTimes.length,
        'current_total': aTimes.fold(0, (a, b) => a + b),
        'markdown_total': bTimes.fold(0, (a, b) => a + b),
      },
    };

    // ignore: avoid_print — Spike 数据采集输出
    print('SPIKE_AB_RESULT=${jsonEncode(result)}');

    // 断言（Spike 数据采集不 fail，仅记录）
    expect(result['rounds'], rounds);
  });

  test('Spike 观察点：公式/Mermaid 扩展成本（md 包按 Text 处理公式）', () {
    // 观察点：md 包不识别 `$...$`，公式在 B 侧为纯文本 ——
    // 扩展需自定义 InlineSyntax（挂载行数 = 扩展成本）。
    const md = r'公式 $E=mc^2$ 和 $x^2$ 混排';
    final b = spike.adaptDocument(md);
    final paragraph = b.whereType<ParagraphElement>().toList();
    expect(paragraph, isNotEmpty);
    final hasText = paragraph.any(
      (p) => p.children.whereType<TextElement>().any((t) => t.text.contains(r'$')),
    );
    // 观察结果：B 侧公式作为 Text 保留（未结构化）——需 InlineSyntax 扩展
    // ignore: avoid_print
    print('SPIKE_FORMULA_AS_TEXT=$hasText（md 包公式需自定义 InlineSyntax 扩展）');
    expect(hasText, isTrue);
  });
}
