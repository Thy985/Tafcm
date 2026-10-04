/// BlockEditor 双向映射：source ↔ DocumentElement。
///
/// 实现两个顶层纯函数：
/// - [toElement]：单块 Markdown source + BlockType → [DocumentElement]
/// - [fromElement]：[DocumentElement] → 单块 Markdown source
///
/// 私有 [InlineSerializer] 类负责 8 类 [InlineElement] 的递归序列化。
///
/// 详见 ADR-0007 §1.3（Wrapping 而非 Flattening）+ §Phase 2.3。
///
/// **Round-trip 一致性边界**（docstring 标注，非 bit-perfect）：
/// - [TextElement] 含未配对 `*` / `_` / `` ` `` / `[` / `!` / `~` → 重解析时可能误识别
/// - [TableElement] cell 含 `|` → parser 用 `split('|')` 会误拆
/// - [CodeElement.code] 含 ``` ``` ``` → fence 冲突
/// - [CodeElement.language] 大小写不保（` ```MERMAID ``` ` round-trip 后变 `mermaid`）
library;

import '../../data/models/document.dart';
import '../parser/markdown_parser.dart';
import 'block_types.dart';

/// 单块解析：source + type → [DocumentElement]。
///
/// 按 [BlockType] 分派，对需要 inline 解析的类型调用 [MarkdownParser.parseInline]。
/// 不修改 AST 类型签名，与 [MarkdownParser.parse] 整篇解析的字段语义对齐。
DocumentElement toElement(String source, BlockType type) {
  switch (type) {
    case BlockType.heading:
      return _parseHeading(source);
    case BlockType.paragraph:
      return ParagraphElement(children: MarkdownParser.parseInline(source));
    case BlockType.listItem:
      return _parseListItem(source);
    case BlockType.taskListItem:
      return _parseTaskListItem(source);
    case BlockType.code:
      return _parseCode(source);
    case BlockType.table:
      return _parseTable(source);
    case BlockType.blockquote:
      return _parseBlockquote(source);
    case BlockType.mermaid:
      return _parseMermaid(source);
    case BlockType.horizontalRule:
      return const HorizontalRuleElement();
  }
}

/// 单块序列化：[DocumentElement] → Markdown source。
///
/// 9 类 [DocumentElement] 子类全覆盖（exhaustive switch）。
/// [EmptyLineElement] 不在 BlockEditor 范围，调用方需自行过滤。
String fromElement(DocumentElement element) {
  switch (element) {
    case HeadingElement(:final level, :final children):
      return '${'#' * level} ${InlineSerializer.serialize(children)}';
    case ParagraphElement(:final children):
      return InlineSerializer.serialize(children);
    case ListElement(:final children, :final ordered, :final indent, :final nested):
      final prefix = ordered ? '1. ' : '- ';
      final self = '${'  ' * indent}$prefix${InlineSerializer.serialize(children)}';
      if (nested.isEmpty) return self;
      // ADR-0029：递归序列化嵌套子项（其自身 indent 字段含正确缩进）
      return [self, ...nested.map(fromElement)].join('\n');
    case TaskListItemElement(:final children, :final checked, :final indent):
      final mark = checked ? 'x' : ' ';
      return '${'  ' * indent}- [$mark] ${InlineSerializer.serialize(children)}';
    case CodeElement(:final code, :final language):
      final lang = language ?? '';
      return '```$lang\n$code\n```';
    case TableElement(:final headers, :final rows):
      return _serializeTable(headers, rows);
    case BlockquoteElement(:final children):
      return '> ${InlineSerializer.serialize(children)}';
    case MermaidElement(:final code):
      return '```mermaid\n$code\n```';
    case HorizontalRuleElement():
      return '---';
    case EmptyLineElement():
      // 不在 BlockEditor 范围（BlockType 不含 emptyLine）。
      // 调用方（Document ↔ List<Block> 层）应过滤 EmptyLineElement。
      throw ArgumentError(
        'EmptyLineElement is not serializable as a Block (it is a block separator)',
      );
  }
}

/// 把过滤掉 [EmptyLineElement] 后的块列表序列化为完整 Markdown 文档。
///
/// 块间分隔符按**前一块类型**决定：前一块是 [ParagraphElement] 时用 `\n\n`，
/// 否则用 `\n`。理由：段落是非自终止块——`MarkdownParser.parse` 把连续的
/// 普通行累积进同一个 `pendingParagraph`（软换行合并），所以 `para1\npara2`
/// 会被解析成**一个**段落。保存时若块间一律 `join('\n')`，相邻段落的空行
/// 就被抹除，重新加载即合并塌缩（issue #343：9 块 → 7 块）。
///
/// 其余块类型（heading / list / fenced code / blockquote / hr / table / mermaid）
/// 的序列化形式都以可识别的行首前缀（`#` / `-` / ` ` `> ` / `|` / ```` ``` ```` / `---`）
/// 自终止，单 `\n` 已足以让 parser 起新块。列表行后的普通行也会被 parser 显式
/// `flushListItems()` 切断，不会合并进列表项。
///
/// 该函数是「加载 → 编辑 → 保存 → 重新加载」往返的**序列化侧**契约；
/// 配套的块数守恒属性测试见 `test/editing/paragraph_roundtrip_test.dart`。
String joinBlocks(List<DocumentElement> elements) {
  if (elements.isEmpty) return '';
  final buf = StringBuffer();
  for (var i = 0; i < elements.length; i++) {
    if (i > 0) {
      buf.write(elements[i - 1] is ParagraphElement ? '\n\n' : '\n');
    }
    buf.write(fromElement(elements[i]));
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// toElement 内部实现
// ---------------------------------------------------------------------------

HeadingElement _parseHeading(String source) {
  final match = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(source);
  if (match == null) {
    // 非法 heading 源，降级为 level=1 + 原文
    return HeadingElement(
      level: 1,
      children: MarkdownParser.parseInline(source),
    );
  }
  return HeadingElement(
    level: match.group(1)!.length,
    // PR-3：标题内容解析为 Inline AST（解析只发生一次）。
    children: MarkdownParser.parseInline(match.group(2) ?? ''),
  );
}

ListElement _parseListItem(String source) {
  // ^(\s*)([-*+]\s|\d+\.\s)([\s\S]*)$
  // 注：content 组用 [\s\S]* 而非 (.*)，以支持跨换行的多行列表源
  // （如自动续列表产生的 "- item\n- "）。(.*) 无法匹配内嵌 \n，
  // 会导致回退到"整段当文本"分支并重复前缀。
  final match = RegExp(r'^(\s*)([-*+]|\d+\.)\s+([\s\S]*)$').firstMatch(source);
  if (match == null) {
    // 非法 list 源，降级为无序 + 0 indent + 原文
    return ListElement(
      children: MarkdownParser.parseInline(source),
      ordered: false,
      indent: 0,
    );
  }
  final indent = match.group(1)!.length ~/ 2;
  final marker = match.group(2)!;
  final itemText = match.group(3) ?? '';
  return ListElement(
    children: MarkdownParser.parseInline(itemText),
    ordered: RegExp(r'^\d+\.$').hasMatch(marker),
    indent: indent,
  );
}

TaskListItemElement _parseTaskListItem(String source) {
  // ^(\s*)[-*+]\s\[(?: |x|X)\]\s(.*)$
  final match = RegExp(r'^(\s*)[-*+]\s\[( |x|X)\]\s+([\s\S]*)$').firstMatch(source);
  if (match == null) {
    // 非法 task list 源，降级为 unchecked + 原文
    return TaskListItemElement(
      children: MarkdownParser.parseInline(source),
      checked: false,
      indent: 0,
    );
  }
  final indent = match.group(1)!.length ~/ 2;
  final checked = match.group(2)! != ' ';
  final itemText = match.group(3) ?? '';
  return TaskListItemElement(
    children: MarkdownParser.parseInline(itemText),
    checked: checked,
    indent: indent,
  );
}

DocumentElement _parseCode(String source) {
  // ^```(\w*)\n([\s\S]*)\n```$
  final match = RegExp(r'^```(\w*)\n([\s\S]*)\n```$', dotAll: true).firstMatch(source);
  if (match == null) {
    // 非法 code 源，降级为无语言 + 原文
    return CodeElement(code: source, language: null);
  }
  final language = match.group(1)!;
  final code = match.group(2) ?? '';
  // 与 markdown_parser.dart:49 对齐：language.toLowerCase() == 'mermaid' → MermaidElement
  if (language.toLowerCase() == 'mermaid') {
    return MermaidElement(code: code);
  }
  return CodeElement(code: code, language: language.isEmpty ? null : language);
}

MermaidElement _parseMermaid(String source) {
  // mermaid block: ```mermaid\n...\n```
  final match = RegExp(r'^```mermaid\n([\s\S]*)\n```$', dotAll: true).firstMatch(source);
  if (match == null) {
    return MermaidElement(code: source);
  }
  return MermaidElement(code: match.group(1) ?? '');
}

TableElement _parseTable(String source) {
  final lines = source.split('\n');
  final dataRows = <List<List<InlineElement>>>[];
  for (final line in lines) {
    if (_isTableSeparatorRow(line)) continue;
    final cells = _parseTableRow(line);
    if (cells != null && cells.isNotEmpty) {
      // PR-2：cell 在序列化层即解析为 Inline AST（解析只发生一次）。
      dataRows.add(cells.map(MarkdownParser.parseInline).toList());
    }
  }
  if (dataRows.isEmpty) {
    return const TableElement(headers: [], rows: []);
  }
  return TableElement(headers: dataRows.first, rows: dataRows.skip(1).toList());
}

BlockquoteElement _parseBlockquote(String source) {
  // Bug1 修复（实测bug1.md §1）：回车在引用块 source 中插入 `\n` 后，
  // 旧实现用非 multiline 正则 `^>\s?(.*)$` 整体匹配失败（`$` 只在串尾匹配）
  // → 兜底 parseInline(source) 把 `>` 当字面文本 → 序列化叠加 `> ` 前缀
  // （用户所见「回车时前面加 >」）+ 状态错乱触发崩溃。
  //
  // 新实现：逐行剥离 `> ` 前缀（无前缀行按 lazy continuation 并入，
  // 与 CommonMark 引用块续行语义一致），join 后再统一走一次行内解析
  // （解析只发生一次，PR-2 原则不变）。
  final lines = source.split('\n');
  final contents = <String>[];
  for (final line in lines) {
    final match = RegExp(r'^>\s?(.*)$').firstMatch(line);
    contents.add(match?.group(1) ?? line);
  }
  final body = contents.join('\n');
  if (body.trim().isEmpty) {
    return const BlockquoteElement(children: [TextElement('')]);
  }
  return BlockquoteElement(children: MarkdownParser.parseInline(body));
}

bool _isTableSeparatorRow(String line) {
  if (!line.startsWith('|') || !line.endsWith('|')) return false;
  final inner = line.substring(1, line.length - 1);
  final cells = inner.split('|');
  for (final cell in cells) {
    final trimmed = cell.trim();
    if (trimmed.isEmpty) continue;
    if (!RegExp(r'^[-:]+$').hasMatch(trimmed)) {
      return false;
    }
  }
  return true;
}

List<String>? _parseTableRow(String line) {
  if (!line.startsWith('|') || !line.endsWith('|')) return null;
  final inner = line.substring(1, line.length - 1);
  if (inner.trim().isEmpty) return null;
  final cells = inner.split('|').map((s) => s.trim()).toList();
  if (cells.isEmpty || (cells.length == 1 && cells[0].isEmpty)) return null;
  return cells;
}

String _serializeTable(
  List<List<InlineElement>> headers,
  List<List<List<InlineElement>>> rows,
) {
  final buffer = StringBuffer();
  String cell(List<InlineElement> c) => InlineSerializer.serialize(c);
  // header row
  buffer.write('|');
  buffer.write(headers.map(cell).join('|'));
  buffer.writeln('|');
  // separator row
  buffer.write('|');
  buffer.write(headers.map((_) => '---').join('|'));
  buffer.writeln('|');
  // data rows
  for (final row in rows) {
    buffer.write('|');
    buffer.write(row.map(cell).join('|'));
    buffer.writeln('|');
  }
  // 移除末尾换行
  final result = buffer.toString();
  return result.endsWith('\n') ? result.substring(0, result.length - 1) : result;
}

// ---------------------------------------------------------------------------
// InlineSerializer：8 类 InlineElement 递归序列化
// ---------------------------------------------------------------------------

/// 8 类 [InlineElement] 的递归序列化器。
///
/// 详见 ADR-0007 §1.3（Wrapping）+ data/models/document.dart。
class InlineSerializer {
  const InlineSerializer._();

  /// 把 [InlineElement] 列表序列化为 Markdown inline 文本。
  static String serialize(List<InlineElement> elements) {
    return elements.map(serializeOne).join();
  }

  /// 把单个 [InlineElement] 序列化为 Markdown inline 片段。
  static String serializeOne(InlineElement element) {
    return switch (element) {
      TextElement(:final text) => text,
      FormulaElement(:final latex, :final displayMode) =>
        displayMode ? '\$\$$latex\$\$' : '\$$latex\$',
      BoldElement(:final children) => '**${serialize(children)}**',
      ItalicElement(:final children) => '*${serialize(children)}*',
      StrikethroughElement(:final children) => '~~${serialize(children)}~~',
      InlineCodeElement(:final code) => '`$code`',
      LinkElement(:final text, :final url) => '[$text]($url)',
      ImageElement(:final alt, :final url) => '![$alt]($url)',
    };
  }
}
