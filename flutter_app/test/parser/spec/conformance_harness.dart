/// U1 CommonMark 一致性评测 harness（TEST-SYSTEM-UPGRADE-PLAN §3.1）。
///
/// "规格即测试数据"范式（学 Markwon/commonmark-java）：spec.txt 的
/// 652 个用例作为参数化数据源，按 section 映射到 **AST 谓词**（我们
/// 输出 AST 而非 HTML，故用"结构期望"替代"html 逐字对比"）。
///
/// 本库无 main，供两处消费：
/// - `commonmark_conformance_test.dart`：ratchet 守门（禁止低于基线）
/// - `tool/gen_spec_baseline.dart`：生成/更新基线
///
/// 谓词设计原则：期望从 spec 的 **html 侧**推导（如 html 有 `<em>` 则
/// AST 必有 ItalicElement），而非手写 markdown 断言——spec 升级时
/// 谓词不需重写。当前不支持的语法（转义/实体/缩进代码块等，见
/// EXTERNAL-PROJECTS-EMPOWERMENT-PLAN §9）会自然 fail 并进入基线，
/// 实现后翻绿，ratchet 逐版收敛。
library;

import 'dart:convert';
import 'dart:io';

import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/data/models/document.dart';

/// 单条 spec 用例。
class SpecExample {
  const SpecExample({
    required this.section,
    required this.number,
    required this.markdown,
    required this.html,
  });

  factory SpecExample.fromJson(Map<String, dynamic> j) => SpecExample(
        section: j['section'] as String,
        number: j['number'] as int,
        markdown: j['markdown'] as String,
        html: j['html'] as String,
      );

  final String section;
  final int number;
  final String markdown;
  final String html;
}

/// 单 section 评测结果。
class SectionResult {
  int pass = 0;
  int fail = 0;
  final List<int> failedNumbers = [];

  Map<String, dynamic> toJson() => {
        'pass': pass,
        'fail': fail,
        if (failedNumbers.isNotEmpty) 'failed': failedNumbers,
      };
}

/// 加载 examples.json（与本文件同目录）。
List<SpecExample> loadExamples() {
  final path =
      '${Directory.current.path}/test/parser/spec/examples.json';
  final raw = jsonDecode(File(path).readAsStringSync()) as List<dynamic>;
  return raw.map((e) => SpecExample.fromJson(e as Map<String, dynamic>)).toList();
}

// ---- AST 遍历辅助 ----
//
// DocumentElement 与 InlineElement 是两个独立的 sealed 层级（无继承
// 关系），谓词探测只做 `is` 判断，统一用 List<dynamic> 容器。

/// 递归收集所有元素（块级 + inline 展开，便于谓词探测）。
void _collectBlocks(List<dynamic> blocks, List<dynamic> out) {
  for (final b in blocks) {
    out.add(b);
    if (b is BlockquoteElement) {
      // 引用内容存为 inline 列表，其中可能嵌套结构——继续按 inline 收集。
      _collectInlines(b.children, out);
    }
    if (b is ListElement) {
      for (final n in b.nested) {
        out.add(n);
      }
    }
  }
}

/// 递归收集所有 inline 元素。
void _collectInlines(List<InlineElement> inlines, List<dynamic> out) {
  for (final i in inlines) {
    out.add(i);
    if (i is BoldElement) _collectInlines(i.children, out);
    if (i is ItalicElement) _collectInlines(i.children, out);
    if (i is StrikethroughElement) _collectInlines(i.children, out);
  }
}

List<dynamic> _allNodes(List<DocumentElement> blocks) {
  final out = <dynamic>[];
  _collectBlocks(blocks, out);
  return out;
}

/// 拼接全部纯文本（用于内容存在性检查）。
String _joinedText(List<dynamic> nodes) {
  final buf = StringBuffer();
  for (final n in nodes) {
    if (n is TextElement) buf.write(n.text);
    if (n is CodeElement) buf.write(n.code);
    if (n is InlineCodeElement) buf.write(n.code);
    if (n is LinkElement) buf.write(n.text);
    if (n is ImageElement) buf.write(n.alt);
  }
  return buf.toString();
}

// ---- html 侧期望提取 ----

final _hTag = RegExp(r'<h([1-6])');
final _codeLang = RegExp(r'<code class="language-([^"]*)"');

bool _htmlHasEmphasis(String html) =>
    html.contains('<em>') || html.contains('<strong>');

// ---- 谓词：期望从 spec html 侧推导 ----

/// 通用"html 形状 ↔ AST 存在性"双向匹配：规范说有什么，AST 就该有什么；
/// 规范说没有的（如被转义的 emphasis），AST 也不该有。
bool _emphasisPredicate(List<dynamic> nodes, String md, String html) {
  final hasItalic = nodes.any((n) => n is ItalicElement);
  final hasBold = nodes.any((n) => n is BoldElement);
  final htmlItalic = html.contains('<em>');
  final htmlBold = html.contains('<strong>');
  return hasItalic == htmlItalic && hasBold == htmlBold;
}

bool _linksPredicate(List<dynamic> nodes, String md, String html) {
  final hasLink = nodes.any((n) => n is LinkElement);
  return hasLink == html.contains('<a ');
}

bool _imagesPredicate(List<dynamic> nodes, String md, String html) {
  final hasImage = nodes.any((n) => n is ImageElement);
  return hasImage == html.contains('<img');
}

bool _headingPredicate(List<dynamic> nodes, String md, String html) {
  final m = _hTag.firstMatch(html);
  if (m == null) return !nodes.any((n) => n is HeadingElement);
  final expectedLevel = int.parse(m.group(1)!);
  return nodes.any(
      (n) => n is HeadingElement && n.level == expectedLevel);
}

bool _fencedCodePredicate(List<dynamic> nodes, String md, String html) {
  final codes = nodes.whereType<CodeElement>().toList();
  if (!html.contains('<pre><code')) return codes.isEmpty;
  if (codes.isEmpty) return false;
  final langMatch = _codeLang.firstMatch(html);
  if (langMatch == null) return true;
  final expected = langMatch.group(1)!;
  return codes.any((c) => c.language == expected);
}

bool _codeSpanPredicate(List<dynamic> nodes, String md, String html) {
  final hasCodeSpan = nodes.any((n) => n is InlineCodeElement);
  return hasCodeSpan == html.contains('<code>');
}

bool _blockquotePredicate(List<dynamic> nodes, String md, String html) {
  final hasQuote = nodes.any((n) => n is BlockquoteElement);
  return hasQuote == html.contains('<blockquote>');
}

bool _hrPredicate(List<dynamic> nodes, String md, String html) {
  final hasHr = nodes.any((n) => n is HorizontalRuleElement);
  return hasHr == html.contains('<hr');
}

bool _listPredicate(List<dynamic> nodes, String md, String html) {
  final lists = nodes.whereType<ListElement>().toList();
  final htmlOrdered = html.contains('<ol>');
  final htmlUnordered = html.contains('<ul>');
  if (!htmlOrdered && !htmlUnordered) return lists.isEmpty;
  if (lists.isEmpty) return false;
  if (htmlOrdered && !lists.any((l) => l.ordered)) return false;
  if (htmlUnordered && !lists.any((l) => !l.ordered)) return false;
  return true;
}

bool _paragraphPredicate(List<dynamic> nodes, String md, String html) {
  final hasParagraph = nodes.any((n) => n is ParagraphElement);
  return hasParagraph == html.contains('<p>');
}

/// 实体引用：`&amp;` 类应解码为真实字符出现在文本中（当前不支持 → 基线 fail）。
bool _entityPredicate(List<dynamic> nodes, String md, String html) {
  if (!html.contains('&amp;')) return true;
  return _joinedText(nodes).contains('&');
}

/// 反斜杠转义：规范期望的 emphasis 形状必须与我们一致（当前不支持 → 基线 fail）。
bool _escapesPredicate(List<dynamic> nodes, String md, String html) {
  if (!md.contains('\\')) return true;
  if (!_htmlHasEmphasis(html)) return true;
  return nodes.any((n) =>
      n is ItalicElement || n is BoldElement);
}

/// 仅做"解析不崩"冒烟的 section（AST 不可精确表达或属渲染层）。
bool _parsesOk(List<dynamic> nodes, String md, String html) => true;

/// section → 谓词映射。section 名必须与 examples.json 逐字一致
///（0.31.2 共 25 节，缺省 fallback = [_parsesOk]）。
final Map<String, bool Function(List<dynamic>, String, String)>
    sectionPredicates = {
  'Tabs': _parsesOk,
  'Backslash escapes': _escapesPredicate,
  'Entity and numeric character references': _entityPredicate,
  'Precedence': _emphasisPredicate,
  'Thematic breaks': _hrPredicate,
  'ATX headings': _headingPredicate,
  'Setext headings': _headingPredicate,
  'Indented code blocks': _fencedCodePredicate, // 期望 CodeElement，同栅栏
  'Fenced code blocks': _fencedCodePredicate,
  'HTML blocks': _parsesOk,
  'Link reference definitions': _linksPredicate,
  'Paragraphs': _paragraphPredicate,
  'Blank lines': _parsesOk,
  'Block quotes': _blockquotePredicate,
  'List items': _listPredicate,
  'Lists': _listPredicate,
  'Code spans': _codeSpanPredicate,
  'Emphasis and strong emphasis': _emphasisPredicate,
  'Links': _linksPredicate,
  'Images': _imagesPredicate,
  'Autolinks': _linksPredicate, // <url> 应产出链接（当前不支持 → fail）
  'Raw HTML': _parsesOk,
  'Hard line breaks': _paragraphPredicate,
  'Soft line breaks': _paragraphPredicate,
  'Textual content': _paragraphPredicate,
};

/// 评测单例：解析失败（抛异常）= fail 并记录崩溃标记。
({bool pass, bool crashed}) evaluate(SpecExample e) {
  try {
    final blocks = MarkdownParser.parse(e.markdown);
    final predicate = sectionPredicates[e.section] ?? _parsesOk;
    return (pass: predicate(_allNodes(blocks), e.markdown, e.html), crashed: false);
  } catch (_) {
    return (pass: false, crashed: true);
  }
}

/// 跑全部用例，按 section 聚合。
Map<String, SectionResult> runConformance(List<SpecExample> examples) {
  final results = <String, SectionResult>{};
  for (final e in examples) {
    final r = results.putIfAbsent(e.section, SectionResult.new);
    final verdict = evaluate(e);
    if (verdict.pass) {
      r.pass++;
    } else {
      r.fail++;
      r.failedNumbers.add(e.number);
    }
  }
  return results;
}
