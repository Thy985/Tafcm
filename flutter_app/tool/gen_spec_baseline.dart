/// 生成/更新 U1 一致性基线（conformance_baseline.json）。
///
/// 用法（在 flutter_app/ 下）：
/// ```bash
/// dart run tool/gen_spec_baseline.dart
/// ```
///
/// 规则：
/// - 数值来自当前 parser 实测，只能**人工确认后上调**（收敛），禁止下调
///   ——守门测试的 ratchet 以此文件为准
/// - spec 升级（examples.json 变化）后重跑本工具，新增 section 会出现在
///   基线中，diff 审查时人工确认
///
/// 输出：`test/parser/spec/conformance_baseline.json`
library;

import 'dart:convert';
import 'dart:io';

import '../test/parser/spec/conformance_harness.dart';

void main() {
  final examples = loadExamples();
  final results = runConformance(examples);

  var totalPass = 0;
  final sections = <String, dynamic>{};
  final sorted = results.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  for (final e in sorted) {
    totalPass += e.value.pass;
    sections[e.key] = e.value.toJson();
  }

  final out = {
    'specVersion': '0.31.2',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'total': {'pass': totalPass, 'examples': examples.length},
    'sections': sections,
  };

  const path = 'test/parser/spec/conformance_baseline.json';
  File(path).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');

  final pct = (totalPass / examples.length * 100).toStringAsFixed(1);
  // ignore: avoid_print
  print('OK: baseline written → $path');
  // ignore: avoid_print
  print('Total: $totalPass/${examples.length} ($pct%)');
  for (final e in sorted) {
    final r = e.value;
    final p = ((r.pass / (r.pass + r.fail)) * 100).toStringAsFixed(0);
    // ignore: avoid_print
    print('  $p%  ${r.pass}/${r.pass + r.fail}  ${e.key}');
  }
}
