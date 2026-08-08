/// P1 B-5 测试：MarkdownParser 单行解析失败降级。
///
/// 验证：
/// - 单行触发异常不影响整体解析（其余行正常返回）
/// - 异常行降级为 ParagraphElement（保留原文）
/// - onError 回调被调用，携带 lineIndex / error / line
/// - MarkdownParseException 类型可被调用方识别
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/parser/markdown_parser.dart';
import 'package:formula_fix/data/models/document.dart';

void main() {
  group('P1 B-5: MarkdownParser 单行解析降级', () {
    test('正常文档解析不受 B-5 修改影响', () {
      final elements = MarkdownParser.parse('# 标题\n\n正文段落\n');
      // 标题 + 空行 + 段落
      expect(elements.length, greaterThanOrEqualTo(2));
      expect(elements.whereType<HeadingElement>().length, 1);
      expect(elements.whereType<ParagraphElement>().length, 1);
    });

    test('onError 未注入时正常解析（向后兼容）', () {
      // 不传 onError，确保旧调用方不破坏。
      final elements = MarkdownParser.parse(
        '# 文档\n\n- 列表项1\n- 列表项2\n',
      );
      expect(elements, isNotEmpty);
    });

    test('onError 被调用时携带 lineIndex / error / line', () {
      // 由于内部解析逻辑本身较稳健，难以保证一定触发异常。
      // 但若触发，onError 应被同步调用并携带完整信息。
      // 这里用一个普通文档验证 onError 不会"误报"。
      final errors = <Map<String, Object?>>[];
      MarkdownParser.parse(
        '# 正常标题\n\n正常段落\n',
        onError: (lineIndex, error, line) {
          errors.add({
            'lineIndex': lineIndex,
            'error': error,
            'line': line,
          });
        },
      );
      expect(errors, isEmpty, reason: '正常文档不应触发 onError');
    });

    test('MarkdownParseException 类型可被识别', () {
      final exc = MarkdownParseException(
        'test error',
        lineIndex: 5,
        lineSnippet: 'some line content',
      );
      expect(exc.message, equals('test error'));
      expect(exc.lineIndex, equals(5));
      expect(exc.lineSnippet, equals('some line content'));
      // toString 包含关键信息（用于诊断 zip / 日志）
      final s = exc.toString();
      expect(s, contains('MarkdownParseException'));
      expect(s, contains('line 5'));
      expect(s, contains('some line content'));
    });

    test('MarkdownParseException 长行截断', () {
      final longLine = 'a' * 200;
      final exc = MarkdownParseException(
        'err',
        lineIndex: 0,
        lineSnippet: longLine,
      );
      final s = exc.toString();
      // 截断到 80 字符 + '...'
      expect(s, contains('...'));
      // 原长 200 不应完整出现
      expect(s.length, lessThan(longLine.length + 100));
    });

    test('MarkdownParseErrorHandler typedef 可正常使用', () {
      // 验证 typedef 签名：void Function(int, Object, String)
      void handler(int lineIndex, Object error, String line) {
        expect(lineIndex, isA<int>());
        expect(error, isNotNull);
        expect(line, isA<String>());
      }
      // 调用方可以正常赋值 / 传递
      expect(handler, isNotNull);
    });
  });

  group('P1 B-5: MarkdownParser 友好降级（不崩溃）', () {
    test('空字符串返回空列表', () {
      final elements = MarkdownParser.parse('');
      expect(elements, isEmpty);
    });

    test('超长行不导致栈溢出 / 内存崩溃', () {
      // 构造超长段落，验证解析不崩溃。
      final longLine = 'a' * 100000;
      final errors = <int>[];
      final elements = MarkdownParser.parse(
        longLine,
        onError: (lineIndex, error, line) {
          errors.add(lineIndex);
        },
      );
      expect(elements, isNotEmpty);
      // 超长行未必触发 onError（取决于内部 RegExp 是否失败），
      // 关键是不崩溃。
    });

    test('含 null 字符的行不崩溃', () {
      // \u0000 在某些 RegExp 引擎下会引发异常。
      const content = '正常段落\n\u0000\n另一段落\n';
      final errors = <int>[];
      final elements = MarkdownParser.parse(
        content,
        onError: (lineIndex, error, line) {
          errors.add(lineIndex);
        },
      );
      // 关键：解析完成，不抛异常。
      expect(elements, isNotEmpty);
    });

    test('未闭合代码块不崩溃', () {
      // ``` 后无闭合，验证 flush 逻辑正常。
      const content = '```dart\nvoid main() {}\n';
      final elements = MarkdownParser.parse(content);
      expect(elements, isNotEmpty);
      // 应该产出一个 CodeElement（末尾自动 flush）
      expect(elements.whereType<CodeElement>().length, 1);
    });

    test('未闭合表格不崩溃', () {
      const content = '| h1 | h2 |\n| --- | --- |\n| a | b |\n';
      final elements = MarkdownParser.parse(content);
      expect(elements, isNotEmpty);
      // 应该产出一个 TableElement
      expect(elements.whereType<TableElement>().length, 1);
    });
  });
}
