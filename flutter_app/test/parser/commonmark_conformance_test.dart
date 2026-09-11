/// U1 CommonMark spec 一致性守门测试（TEST-SYSTEM-UPGRADE-PLAN §3.1）。
///
/// **Ratchet 语义**：以 `conformance_baseline.json` 为基线，
/// - 任何 section 通过数 **低于基线** → 测试失败（禁止回归）
/// - 高于基线 → 通过并提示更新基线（鼓励收敛）
/// - 未知 section（spec 升级新增）→ 直接计入当前值，提示纳入基线
///
/// 基线再生：`dart run tool/gen_spec_baseline.dart`（数值只能人工确认后
/// 上调，禁止下调）。
///
/// 谓词映射见 `conformance_harness.dart`；数据许可见 `spec/README.md`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'spec/conformance_harness.dart';

const _baselinePath = 'test/parser/spec/conformance_baseline.json';

void main() {
  final examples = loadExamples();
  final results = runConformance(examples);

  setUpAll(() {
    // ignore: avoid_print
    stdout.writeln('[U1] CommonMark 0.31.2 conformance: '
        '${examples.length} examples, ${results.length} sections');
  });

  test('基线文件存在且结构合法', () {
    final file = File(_baselinePath);
    expect(file.existsSync(), isTrue,
        reason: '缺少 $_baselinePath —— 运行 dart run tool/gen_spec_baseline.dart');
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(data['specVersion'], '0.31.2');
    expect(data['sections'], isA<Map<String, dynamic>>());
  });

  test('ratchet：每 section 通过数不低于基线', () {
    final baseline =
        (jsonDecode(File(_baselinePath).readAsStringSync())
                as Map<String, dynamic>)['sections']
            as Map<String, dynamic>;

    final regressions = <String>[];
    final improvements = <String>[];
    final unknown = <String>[];

    results.forEach((section, result) {
      final base = baseline[section];
      if (base == null) {
        unknown.add('$section (pass=${result.pass}, fail=${result.fail})');
        return;
      }
      final basePass = (base as Map<String, dynamic>)['pass'] as int;
      if (result.pass < basePass) {
        regressions.add(
            '$section: baseline=$basePass now=${result.pass} '
            '(new failures: ${result.failedNumbers})');
      } else if (result.pass > basePass) {
        improvements.add('$section: $basePass → ${result.pass}');
      }
    });

    // spec 升级出现新 section 时显式提示（不失败，待纳入基线）。
    if (unknown.isNotEmpty) {
      // ignore: avoid_print
      stdout.writeln('[U1] 新 section 未入基线（请更新 baseline）：$unknown');
    }

    expect(regressions, isEmpty,
        reason: 'CommonMark 一致性回归（禁止低于基线）:\n${regressions.join('\n')}');

    if (improvements.isNotEmpty) {
      // ignore: avoid_print
      stdout.writeln('[U1] 通过数提升（可更新基线固化）: $improvements');
    }
  });

  test('总通过率报告（观测用，不设阈值）', () {
    var totalPass = 0;
    var total = 0;
    final report = StringBuffer();
    final sorted = results.entries.toList()
      ..sort((a, b) => (b.value.pass / (b.value.pass + b.value.fail))
          .compareTo(a.value.pass / (a.value.pass + a.value.fail)));
    for (final e in sorted) {
      final r = e.value;
      totalPass += r.pass;
      total += r.pass + r.fail;
      final pct = ((r.pass / (r.pass + r.fail)) * 100).toStringAsFixed(0);
      report.writeln('  $pct%  ${r.pass}/${r.pass + r.fail}  ${e.key}');
    }
    // ignore: avoid_print
    stdout.writeln('[U1] 通过率 ${((totalPass / total) * 100).toStringAsFixed(1)}%'
        ' ($totalPass/$total)\n$report');
    expect(total, examples.length);
  });

  test('崩溃零容忍：解析抛异常的用例必须为 0（新增输入导致 parser 崩溃即失败）', () {
    // 逐例重跑定位崩溃（runConformance 已聚合，这里取证据）。
    final crashed = <String>[];
    for (final e in examples) {
      final verdict = evaluate(e);
      if (verdict.crashed) crashed.add('${e.section}#${e.number}');
    }
    expect(crashed, isEmpty, reason: 'parser 对以下 spec 输入抛异常: $crashed');
  });
}
