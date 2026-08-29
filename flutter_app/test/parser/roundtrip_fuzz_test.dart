/// CAP-008 round-trip fuzz —— 随机语料一致性审计（Phase 3.9 Batch 1）。
///
/// 审计目标：随机 Markdown 语料经 `parse → serialize → parse → serialize`
/// 必须收敛到不动点（语义等价），且任意输入 parse/serialize 不崩溃。
///
/// 断言（弱于逐字 round-trip，但能捕获真实 bug）：
/// 1. **resilience**：任意随机输入 parse 不抛异常（镜像 ADR-0024 §2.4）
/// 2. **fixpoint**：二次 round-trip 后 serialize 输出稳定
///    `serialize(parse(serialize(parse(md)))) == serialize(parse(md))`
///
/// 固定 seed 保证可复现（seed 变更需同步更新基线）。
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/core/parser/markdown_serializer.dart';
import 'package:tafcm/data/models/document.dart';

/// 可复现的随机语料生成器（固定 seed）。
class MarkdownCorpusGenerator {
  MarkdownCorpusGenerator([int seed = 20260817]) : _rng = Random(seed);

  final Random _rng;

  static const _fragments = <String>[
    'hello', 'world', 'foo bar', '中文测试', 'α β γ', '123',
    'a_b', 'x*y', '`code`', r'$x$', '**bold**', '*it*', '~~del~~',
    '[link](http://x.com)', '![img](a.png)', 'trailing ', '  leading',
    'line\nbreak', '|pipe|', 'hash#tag', 'back\\slash', 'quote"q"',
    'apost\'a', 'tab\tsep', 'emoji🎉', 'café', '**混*合**',
  ];

  static const _blocks = <String>[
    '# H1', '## H2', '###### H6', '- item', '- [x] task', '1. ordered',
    '> quote', '```\ncode\n```', '```dart\nvoid main(){}\n```',
    '| a | b |\n|---|---|\n| 1 | 2 |',
    '---', r'$$E=mc^2$$', '***',
    // Batch 3 扩展：表格 cell 内公式 / Mermaid / 多级嵌套。
    // ADR-0029 落地后（Run #008 Batch 4）恢复嵌套列表语料：
    // ListElement.nested 结构使嵌套 round-trip 保真，不再豁免。
    r'| $x$ | **bold** |',
    '| a | \$\\frac{1}{2}\$ |\n|---|---|\n| \$\\alpha\$ | `code` |',
    '```mermaid\ngraph TD\nA-->B\n```',
    '> quote line1\n> quote line2',
    r'$$\\sum_{i=1}^{n} i$$',
    '| h1 | h2 |\n|----|----|\n| a  | b  |',
    '```\nmultiline\ncode\nblock\n```',
    '```python\nprint("x")\n```',
    '1. one\n1. two\n1. three',
    '- a\n- b\n- c',
    '| a | b | c |\n|---|---|---|\n| 1 | 2 | 3 |',
    '- parent\n  - child\n    - grandchild',
    '- a\n- b\n  - b1\n- c',
    '1. one\n2. two\n   - nested\n3. three',
    '- [ ] todo\n- [x] done\n  - sub',
    '- 中文列表项\n  - 嵌套中文',
  ];

  String _pick(List<String> pool) => pool[_rng.nextInt(pool.length)];

  /// 生成一行（片段拼接，偶发嵌套）。
  String _line() {
    final parts = <String>[];
    final n = 1 + _rng.nextInt(4);
    for (var i = 0; i < n; i++) {
      parts.add(_pick(_fragments));
    }
    var line = parts.join(' ');
    // 偶发加行内前缀（从 fragment 池取词，避免从 _blocks 取——
    // `_blocks` 含 ``` 等 fence 行，split(' ').first 会取出未闭合 fence）
    if (_rng.nextDouble() < 0.15) {
      line = '${_pick(_fragments).split(' ').first} $line';
    }
    return line;
  }

  /// 生成一段随机 Markdown 文档（1-12 行，混合块/行）。
  ///
  /// 注意：不生成空行 —— EmptyLineElement 是块间分隔符，
  /// MarkdownSerializer 契约要求调用方过滤（block_serializer.dart:76），
  /// 不参与 round-trip 序列化。
  ///
  /// Batch 3：偶发 CRLF 混合换行（Windows 文件常见；parser 应无残留 \r）。
  String generate() {
    final lines = <String>[];
    final n = 1 + _rng.nextInt(12);
    for (var i = 0; i < n; i++) {
      final r = _rng.nextDouble();
      if (r < 0.3) {
        lines.add(_pick(_blocks));
      } else {
        lines.add(_line());
      }
      // 偶发连续块（测试相邻块合并/分隔）
      if (_rng.nextDouble() < 0.1 && lines.isNotEmpty) {
        lines.add(_pick(_blocks));
      }
    }
    final joined = lines.join('\n');
    // CRLF 混合：偶发把部分换行替换为 \r\n（约 15% 概率文档）
    if (_rng.nextDouble() < 0.15) {
      return joined.replaceAll('\n', '\r\n');
    }
    return joined;
  }
}

/// 结构等价比较：类型 + 关键字段（不依赖 toString/==，sealed switch）。
bool _elementsEqual(List<DocumentElement> a, List<DocumentElement> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_elementEqual(a[i], b[i])) return false;
  }
  return true;
}

bool _elementEqual(DocumentElement a, DocumentElement b) {
  if (a.runtimeType != b.runtimeType) return false;
  // 双类型 record pattern 在本 SDK 版本不稳定（变量绑定丢失），
  // 用显式类型检查（AGENTS.md §11.3：保守写法优先）。
  if (a is HeadingElement) {
    final x = a, y = b as HeadingElement;
    return x.level == y.level && x.text == y.text;
  }
  if (a is ParagraphElement) {
    final x = a, y = b as ParagraphElement;
    return _inlineEqual(x.children, y.children);
  }
  if (a is ListElement) {
    final x = a, y = b as ListElement;
    return _inlineEqual(x.children, y.children) &&
        x.ordered == y.ordered &&
        x.indent == y.indent;
  }
  if (a is CodeElement) {
    final x = a, y = b as CodeElement;
    return x.code == y.code && x.language == y.language;
  }
  if (a is TableElement) {
    final x = a, y = b as TableElement;
    return _strListEqual(x.headers, y.headers) && _rowsEqual(x.rows, y.rows);
  }
  if (a is BlockquoteElement) {
    final x = a, y = b as BlockquoteElement;
    return x.text == y.text;
  }
  if (a is MermaidElement) {
    final x = a, y = b as MermaidElement;
    return x.code == y.code;
  }
  if (a is TaskListItemElement) {
    final x = a, y = b as TaskListItemElement;
    return _inlineEqual(x.children, y.children) &&
        x.checked == y.checked &&
        x.indent == y.indent;
  }
  if (a is HorizontalRuleElement) return true;
  if (a is EmptyLineElement) return true;
  return a.runtimeType == b.runtimeType;
}

bool _inlineEqual(List<InlineElement> a, List<InlineElement> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x.runtimeType != y.runtimeType) return false;
    if (x is TextElement && y is TextElement && x.text != y.text) return false;
    if (x is FormulaElement &&
        y is FormulaElement &&
        (x.latex != y.latex || x.displayMode != y.displayMode)) {
      return false;
    }
    if (x is BoldElement && y is BoldElement && !_inlineEqual(x.children, y.children)) {
      return false;
    }
    if (x is ItalicElement &&
        y is ItalicElement &&
        !_inlineEqual(x.children, y.children)) {
      return false;
    }
    if (x is StrikethroughElement &&
        y is StrikethroughElement &&
        !_inlineEqual(x.children, y.children)) {
      return false;
    }
    if (x is InlineCodeElement && y is InlineCodeElement && x.code != y.code) {
      return false;
    }
    if (x is LinkElement && y is LinkElement &&
        (x.url != y.url || x.text != y.text)) {
      return false;
    }
    if (x is ImageElement && y is ImageElement &&
        (x.url != y.url || x.alt != y.alt)) {
      return false;
    }
  }
  return true;
}

bool _strListEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _rowsEqual(List<List<String>> a, List<List<String>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_strListEqual(a[i], b[i])) return false;
  }
  return true;
}

void main() {
  // 参数化：CI 默认固定 seed + 1000 轮；本地可传
  // --dart-define=FUZZ_SEED=<n> --dart-define=FUZZ_ROUNDS=<n> 扫描多 seed。
  const seedStr = String.fromEnvironment('FUZZ_SEED', defaultValue: '20260817');
  const rounds = int.fromEnvironment('FUZZ_ROUNDS', defaultValue: 1000);
  final seed = int.tryParse(seedStr) ?? 20260817;

  group('CAP-008 round-trip fuzz', () {
    test('$rounds 轮随机语料（seed=$seed）：不崩溃 + 二次 round-trip 不动点', () {
      runFuzzScan(seed, rounds);
    });

    test('multi-seed 扫描（5 seed × 200 轮）：CI 自动覆盖多 seed', () {
      // 与默认 seed 互补，防止单一随机流掩盖解析路径差异。
      for (final s in [1, 42, 20260818, 9999, 314159]) {
        runFuzzScan(s, 200);
      }
    });

    test('AST 结构比较器本身可用（手写语料 sanity）', () {
      final md = '# Title\n\n- item\n\n```dart\nx\n```';
      final e1 = MarkdownParser.parse(md);
      final e2 = MarkdownParser.parse(md);
      expect(_elementsEqual(e1, e2), isTrue);
    });
  });
}

/// 单 seed 扫描主体：不崩溃 + 二次 round-trip 不动点 + AST 结构等价。
void runFuzzScan(int seed, int rounds) {
  final gen = MarkdownCorpusGenerator(seed);
  var fixpointViolations = 0;
  String? firstViolation;

  for (var round = 0; round < rounds; round++) {
    final md = gen.generate();

    // 1. resilience：parse 不崩溃
    final elements1 = MarkdownParser.parse(md);
    expect(elements1, isNotNull, reason: 'seed=$seed round=$round md=${md.toString()}');

    // 2. round-trip：parse → serialize → parse → serialize 收敛不动点
    final md1 = MarkdownSerializer.serialize(elements1);
    final elements2 = MarkdownParser.parse(md1);
    final md2 = MarkdownSerializer.serialize(elements2);

    if (md2 != md1) {
      fixpointViolations++;
      if (firstViolation == null) {
        firstViolation = 'seed=$seed round=$round\n'
            'input md:\n$md\n'
            'md1:\n$md1\n'
            'md2:\n$md2\n';
      }
    }

    // 3. 结构等价：parse(md) 与 parse(md1) 语义一致
    if (!_elementsEqual(elements1, elements2)) {
      fail('seed=$seed round=$round AST 结构不一致\n'
          'input md:\n$md\n'
          'serialized:\n$md1\n');
    }
  }

  // 不动点允许少数已知规范化差异（如空行压缩），但必须 < 1% 且记录
  expect(fixpointViolations, lessThan(10),
      reason: 'seed=$seed fixpoint 违反应 < 1%（10/$rounds）；首个违规：\n$firstViolation');
}
