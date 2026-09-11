/// 生成器：从 commonmark-spec 的 spec.txt 抽取一致性用例 → examples.json。
///
/// 用法（在 flutter_app/ 下）：
/// ```bash
/// dart run tool/gen_spec_examples.dart
/// ```
///
/// 输入：`test/parser/spec/spec.txt`（CommonMark 0.31.2，CC-BY-SA 4.0）
/// 输出：`test/parser/spec/examples.json`
///
/// spec.txt 用例格式（每个用例被反引号/波浪线长栅栏包裹）：
/// ```````````````````````````````` example
/// <markdown 源>
/// .
/// <html 输出>
/// ````````````````````````````````
/// `example` 后可带修饰（`example disabled` 等）。栅栏行长度可变，
/// 由首行推断，闭合行为等长的纯反引号/波浪线。
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final specPath = args.isNotEmpty
      ? args[0]
      : 'test/parser/spec/spec.txt';
  final outPath = args.length > 1
      ? args[1]
      : 'test/parser/spec/examples.json';

  final lines = File(specPath).readAsLinesSync();

  // 栅栏行：>=3 个反引号或波浪线，后跟 ` example`（可能带 disabled 等修饰）。
  final fenceRe = RegExp(r'^(`{3,}|~{3,}) ?example ?([a-z ]*)$');

  final examples = <Map<String, dynamic>>[];
  var currentSection = '';
  var number = 0;

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];

    // 跟踪所在 section（## 二级标题）。
    if (line.startsWith('## ')) {
      currentSection = line.substring(3).trim();
    }

    final fenceMatch = fenceRe.firstMatch(line);
    if (fenceMatch == null) {
      i++;
      continue;
    }

    final fence = fenceMatch.group(1)!;
    final modifiers = (fenceMatch.group(2) ?? '').trim();
    final disabled = modifiers.contains('disabled');
    final closeFence = fence[0] * fence.length;

    // 收集 markdown 段：直到单独的 `.` 行。
    i++;
    final markdownBuf = <String>[];
    while (i < lines.length && lines[i] != '.') {
      markdownBuf.add(lines[i]);
      i++;
    }
    if (i >= lines.length) {
      stderr.writeln('FATAL: unterminated example at line $i (section: $currentSection)');
      exitCode = 1;
      return;
    }
    i++; // 跳过 `.`

    // 收集 html 段：直到闭合栅栏。
    final htmlBuf = <String>[];
    while (i < lines.length && lines[i] != closeFence) {
      htmlBuf.add(lines[i]);
      i++;
    }
    if (i >= lines.length) {
      stderr.writeln('FATAL: missing closing fence after line $i (section: $currentSection)');
      exitCode = 1;
      return;
    }
    i++; // 跳过闭合栅栏

    number++;
    examples.add({
      'section': currentSection,
      'number': number,
      'markdown': markdownBuf.join('\n'),
      'html': htmlBuf.join('\n'),
      'disabled': disabled,
    });
  }

  // 计划内 section 白名单之外的用例也全部保留（基线按 section 聚合，
  // 无需在此过滤——过滤策略属守门测试的职责）。
  const encoder = JsonEncoder.withIndent('  ');
  File(outPath).writeAsStringSync('${encoder.convert(examples)}\n');

  final enabled = examples.where((e) => e['disabled'] != true).length;
  stdout.writeln('OK: ${examples.length} examples '
      '($enabled enabled, ${examples.length - enabled} disabled) → $outPath');
  final sections = examples.map((e) => e['section']).toSet();
  stdout.writeln('Sections: ${sections.length}');
}
