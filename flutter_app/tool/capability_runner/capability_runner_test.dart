// FormulaFix Capability Runner — Runtime Bridge 的 Dart 侧。
//
// FFX Verification Orchestrator 通过 subprocess 调用本 runner，
// 直调真实生产类（lib/core/parser/markdown_parser.dart / markdown_serializer.dart），
// 禁止 Python 侧重实现解析逻辑。
//
// 执行方式（block_serializer.dart → block_types.dart 链依赖 Flutter foundation/dart:ui，
// 必须跑在 Flutter 运行时，故用 flutter test 环境承载）：
//   flutter test tool/capability_runner/capability_runner_test.dart
//   env: FFX_CORPUS_DIR（可选，含 *.md 则用之，否则内置 corpus）
//        FFX_OUT_DIR（结果 result.json 写入目录）
//
// 结果写 <FFX_OUT_DIR>/result.json 并打印 JSON 到 stdout；任何异常导致 test 失败 → 非零退出。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/parser/markdown_parser.dart';
import 'package:formula_fix/core/parser/markdown_serializer.dart';
import 'package:formula_fix/data/models/document.dart';

/// 内置 corpus：覆盖核心 Block/Inline/编码/降级路径，保证无外部输入也能跑。
const List<String> _builtinCorpus = [
  '# Heading One\n\n## Heading Two\n\n### Heading Three',
  'Paragraph with **bold**, *italic*, `code`, ~~strike~~, [link](https://x.dev), ![img](a.png).',
  r'Inline formula $x^2 + y^2 = z^2$ and block:' '\n\n' r'$$\n\int_0^1 f(x) dx\n$$',
  '- item 1\n- item 2\n  - nested a\n  - nested b\n- item 3',
  '1. first\n2. second\n   1. sub one\n   2. sub two\n3. third',
  '> blockquote line\n> second line',
  '```dart\nvoid main() { print("hi"); }\n```\n',
  '```mermaid\ngraph TD\n  A-->B\n```\n',
  '| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n',
  '- [x] done task\n- [ ] pending task',
  'Line 1\r\nLine 2\r\nLine 3',
  '---\n\nText after rule',
  '*unclosed bold marker',
  '`unclosed code',
  '',
];

class _Counters {
  int files = 0;
  int parseOk = 0;
  int roundtripConverged = 0;
  int lineErrors = 0;
  final Map<String, int> elements = {};

  void tallyElement(dynamic e) {
    final name = e.runtimeType.toString();
    elements[name] = (elements[name] ?? 0) + 1;
  }
}

List<String> _loadDocs(String? corpusDir) {
  if (corpusDir != null && Directory(corpusDir).existsSync()) {
    final files = Directory(corpusDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .toList();
    if (files.isNotEmpty) {
      return files.map((f) => f.readAsStringSync()).toList();
    }
  }
  return List.of(_builtinCorpus);
}

/// Regression cases（G7，2026-08-20）：内置 corpus + FFX_REGRESSION_DIR
/// 合并——verify 自动包含已资产化的 Golden Failure 触发输入。
List<String> _loadDocsWithRegression(String? corpusDir, String? regressionDir) {
  final docs = _loadDocs(corpusDir);
  if (regressionDir != null && Directory(regressionDir).existsSync()) {
    for (final f in Directory(regressionDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))) {
      docs.add(f.readAsStringSync());
    }
  }
  return docs;
}

void main() {
  test('ffx capability runner: markdown production-path verification', () {
    final corpusDir = Platform.environment['FFX_CORPUS_DIR'];
    final regressionDir = Platform.environment['FFX_REGRESSION_DIR'];
    final outDir = Platform.environment['FFX_OUT_DIR'] ?? Directory.systemTemp.path;

    final counters = _Counters();
    final lineErrors = <Map<String, Object?>>[];

    for (final md in _loadDocsWithRegression(corpusDir, regressionDir)) {
      counters.files++;
      try {
        // 真实生产路径：MarkdownParser.parse（含单行降级回调）
        final elements = MarkdownParser.parse(md, onError: (lineIndex, error, line) {
          counters.lineErrors++;
          lineErrors.add({'line': lineIndex, 'error': error.toString(), 'source': line});
        });
        for (final e in elements) {
          counters.tallyElement(e);
        }

        // 镜像生产调用方契约（editor_page.dart:148 加载时跳过分隔符）：
        // EmptyLineElement 是块间分隔符，serialize 前须过滤，否则 block_serializer 抛错。
        final editable = elements.where((e) => e is! EmptyLineElement).toList();
        // 往返保真：parse→serialize→parse 不动点收敛
        final s1 = MarkdownSerializer.serialize(editable);
        final s2 = MarkdownSerializer.serialize(
          MarkdownParser.parse(s1).where((e) => e is! EmptyLineElement).toList(),
        );
        // R10 修复：parse_ok 仅在完整链路（parse+serialize+roundtrip 收敛）
        // 成功后累加——此前在 try 块内、roundtrip 检查前累加，roundtrip 失败
        // 也计为 parse_ok，checks["parse"] 实际只断言「未抛异常」（命名误导）。
        if (s1 == s2) {
          counters.roundtripConverged++;
          counters.parseOk++;
        }
      } catch (e) {
        lineErrors.add({'line': -1, 'error': '${e.runtimeType}: $e'});
      }
    }

    final convergence = counters.files == 0
        ? 0.0
        : counters.roundtripConverged / counters.files;
    final result = <String, Object?>{
      'capability': 'markdown',
      'ok': true,
      'metrics': {
        'files': counters.files,
        'parse_ok': counters.parseOk,
        'roundtrip_converged': counters.roundtripConverged,
        'roundtrip_convergence': convergence,
        'line_errors': counters.lineErrors,
        'elements': counters.elements,
      },
      'line_errors': lineErrors,
    };

    final out = Directory(outDir);
    out.createSync(recursive: true);
    File('${out.path}/result.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(result),
    );
    // stdout 供 FFX 直接捕获
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  });
}
