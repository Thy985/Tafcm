/// U5 性能 ratchet 守门测试（TEST-SYSTEM-UPGRADE-PLAN §3.5）。
///
/// 与既有 TC-PERF-1/2/3 的分工：
/// - TC-PERF-* 是**绝对阈值**断言（如 <5ms），防御"慢到不可用"；
/// - 本测试是**基线 ratchet**：以 `perf_baseline.json` 实测值为基线 ×
///   slack 余量做断言，防御"悄悄变慢"——issue #245（按键 O(n²)）这类
///   渐进退化在绝对阈值宽松时无人报警，ratchet 负责。
///
/// 规则：
/// - 低于基线×slack → 失败（禁止回归）
/// - 显著优于基线（<70%）→ 通过并提示更新基线（鼓励收敛）
/// - 基线数值只能人工确认后下调（slack 收紧），禁止上调
/// - 全部指标纯 Dart 确定性运行，CI perf job 消费（`--tags perf`）
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/block_serializer.dart';
import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/core/services/file_repository.dart';

const _baselinePath = 'test/performance/perf_baseline.json';

/// 10 次采样取中位数（与 TC-PERF-* 同方法，保证可比）。
double _medianMs(int Function() run) {
  final samples = <int>[];
  for (var i = 0; i < 10; i++) {
    samples.add(run());
  }
  samples.sort();
  return samples[4] + (samples[5] - samples[4]) / 2;
}

/// 异步版中位数（listDocuments 等 Future API 用，完整 await 计时）。
Future<double> _medianMsAsync(Future<void> Function() run) async {
  final samples = <int>[];
  for (var i = 0; i < 10; i++) {
    final sw = Stopwatch()..start();
    await run();
    samples.add(sw.elapsedMilliseconds);
  }
  samples.sort();
  return samples[4] + (samples[5] - samples[4]) / 2;
}

/// 构造与 parser_perf_test._buildSampleMarkdown **同分布**的样本
///（1339 行 / ~12883 chars：标题+段落+列表+引用+代码+表格+分割线循环）。
///
/// 基线 38.12ms 就是在该样本上测的——样本不同则不可比（首轮实测教训：
/// 换成纯文本行样本后 108ms，被误判为回归）。
String _buildParserSample({int lines = 1000}) {
  final sb = StringBuffer();
  var i = 0;
  while (i < lines) {
    sb.writeln('# 标题 $i');
    i++;
    if (i >= lines) break;

    sb.writeln('');
    sb.writeln('这是第 $i 段正文，包含 **加粗** 与 *斜体* 和 `行内代码`。');
    i += 2;
    if (i >= lines) break;

    sb.writeln('');
    sb.writeln('- 无序项目 A');
    sb.writeln('- 无序项目 B');
    sb.writeln('- 无序项目 C');
    i += 3;
    if (i >= lines) break;

    sb.writeln('');
    sb.writeln('1. 有序项目');
    sb.writeln('2. 有序项目');
    i += 2;
    if (i >= lines) break;

    sb.writeln('');
    sb.writeln('> 引用内容：第 $i 行的引用块。');
    i++;
    if (i >= lines) break;

    sb.writeln('');
    sb.writeln('```dart');
    sb.writeln('void main() {');
    sb.writeln('  print("hello $i");');
    sb.writeln('}');
    sb.writeln('```');
    i += 5;
    if (i >= lines) break;

    sb.writeln('');
    sb.writeln('| 列 A | 列 B | 列 C |');
    sb.writeln('| --- | --- | --- |');
    sb.writeln('| $i | ${i + 1} | ${i + 2} |');
    i += 3;
    if (i >= lines) break;

    sb.writeln('');
    sb.writeln('---');
    i++;
  }
  return sb.toString();
}

/// 构造 1000 块混合文档（与 block_perf_test 同分布：7:2:1 paragraph/heading/code）。
List<(String, BlockType)> _buildBlocks({int count = 1000}) {
  final blocks = <(String, BlockType)>[];
  for (var i = 0; i < count; i++) {
    final r = i % 10;
    if (r < 7) {
      blocks.add((
        '这是第 $i 段正文，包含 **加粗** 与 *斜体*，公式 \$x^2 + y^2 = z^2\$。',
        BlockType.paragraph,
      ));
    } else if (r < 9) {
      blocks.add(('## 标题 $i', BlockType.heading));
    } else {
      blocks.add(('```dart\nvar x = $i;\n```', BlockType.code));
    }
  }
  return blocks;
}

String _buildFullDocument(List<(String, BlockType)> blocks) {
  final sb = StringBuffer();
  for (final (source, _) in blocks) {
    sb
      ..writeln(source)
      ..writeln();
  }
  return sb.toString();
}

void main() {
  late Map<String, dynamic> metrics;

  setUpAll(() {
    final file = File(_baselinePath);
    expect(file.existsSync(), isTrue,
        reason: '缺少 $_baselinePath（性能基线）。U5 ratchet 依赖它。');
    metrics =
        (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)['metrics']
            as Map<String, dynamic>;
  });

  test('perf ratchet: MarkdownParser.parse(1000 行)', () {
    // 与 TC-PERF-1 同分布样本（基线即在该样本上测得）。
    final md = _buildParserSample();
    final median = _medianMs(() {
      final sw = Stopwatch()..start();
      MarkdownParser.parse(md);
      return sw.elapsedMicroseconds ~/ 1000;
    });
    _assertRatchet(metrics, 'parser_parse_1000_lines', median);
  });

  test('perf ratchet: 单块 toElement（典型 1000 块）', () {
    final blocks = _buildBlocks();
    final median = _medianMs(() {
      final sw = Stopwatch()..start();
      for (final (source, type) in blocks) {
        toElement(source, type);
      }
      return sw.elapsedMicroseconds ~/ 1000;
    });
    // 注意：基线单位是 per-block ms，这里测的是 1000 块总耗时 → 换算。
    final perBlock = median / blocks.length;
    _assertRatchet(metrics, 'block_toelement_typical', perBlock);
  });

  test('perf ratchet: 整篇 1000 块 MarkdownParser.parse', () {
    final blocks = _buildBlocks();
    final fullDocument = _buildFullDocument(blocks);
    final median = _medianMs(() {
      final sw = Stopwatch()..start();
      MarkdownParser.parse(fullDocument);
      return sw.elapsedMicroseconds ~/ 1000;
    });
    _assertRatchet(metrics, 'fulldoc_parse_1000_blocks', median);
  });

  test('perf ratchet: listDocuments(1000 文件)', () async {
    final tempDir =
        Directory.systemTemp.createTempSync('tafcm_perf_u5');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    for (var i = 0; i < 1000; i++) {
      File('${tempDir.path}${Platform.pathSeparator}doc_$i.md')
          .writeAsStringSync('---\nid: doc_$i\n---\n# Doc $i\nbody\n');
    }
    final repo = FileRepository()..testDocsDir = tempDir.path;
    // listDocuments 是 async：必须完整 await 计时（首轮教训：同步计时只测
    // 了 Future 创建 ~0ms，且未等待导致 tearDown 提前删目录 → PathNotFound）。
    final median = await _medianMsAsync(() => repo.listDocuments());
    _assertRatchet(metrics, 'list_documents_1000_files', median);
  });
}

/// ratchet 断言：median ≤ baseline × slack；显著优于（<70%）时提示更新基线。
void _assertRatchet(
    Map<String, dynamic> metrics, String key, double medianMs) {
  final entry = metrics[key];
  expect(entry, isNotNull, reason: '基线缺指标 $key —— 请同步更新 perf_baseline.json');
  final baseline = (entry['baselineMs'] as num).toDouble();
  final slack = (entry['slack'] as num).toDouble();
  final budget = baseline * slack;

  // ignore: avoid_print
  print('[U5-ratchet] $key: median=${medianMs.toStringAsFixed(2)}ms '
      'baseline=${baseline}ms slack×$slack budget=${budget.toStringAsFixed(2)}ms');

  expect(medianMs, lessThanOrEqualTo(budget),
      reason: '性能回归：$key 中位数 ${medianMs.toStringAsFixed(2)}ms '
          '超过基线 $baseline ms × slack $slack = ${budget.toStringAsFixed(2)}ms。'
          '若为有意改动请人工下调基线；否则排查退化（参考 issue #245 的教训）。');

  if (medianMs < baseline * 0.7) {
    // ignore: avoid_print
    print('[U5-ratchet] $key 显著优于基线'
        '（${medianMs.toStringAsFixed(2)}ms < 70% of $baseline ms），'
        '建议人工下调基线固化收益');
  }
}
